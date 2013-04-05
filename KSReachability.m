//
//  KSReachability.m
//
//  Created by Karl Stenerud on 5/5/12.
//
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#import "KSReachability.h"
#import <netdb.h>


// ----------------------------------------------------------------------
#pragma mark - ARC-Safe Memory Management -
// ----------------------------------------------------------------------

// Full version at https://github.com/kstenerud/ARCSafe-MemManagement
#if __has_feature(objc_arc)
    #define as_release(X)
    #define as_autorelease(X)        (X)
    #define as_superdealloc()
    #define as_bridge                __bridge
#else
    #define as_release(X)           [(X) release]
    #define as_autorelease(X)       [(X) autorelease]
    #define as_superdealloc()       [super dealloc]
    #define as_bridge
#endif

#if defined(__clang__) || __has_feature(objc_arc)
    #define as_autoreleasepool_start(NAME) @autoreleasepool {
    #define as_autoreleasepool_end(NAME)   }
#else
    #define as_autoreleasepool_start(NAME) NSAutoreleasePool* NAME = [[NSAutoreleasePool alloc] init];
    #define as_autoreleasepool_end(NAME)   [NAME release];
#endif


#define kKVOProperty_Flags     @"flags"
#define kKVOProperty_Reachable @"reachable"
#define kKVOProperty_WWANOnly  @"WWANOnly"


// ----------------------------------------------------------------------
#pragma mark - KSReachability -
// ----------------------------------------------------------------------

@interface KSReachability ()

@property(nonatomic,readwrite,retain) NSString* hostname;
@property(nonatomic,readwrite,assign) SCNetworkReachabilityFlags flags;
@property(nonatomic,readwrite,assign) BOOL reachable;
@property(nonatomic,readwrite,assign) BOOL WWANOnly;
@property(nonatomic,readwrite,assign) SCNetworkReachabilityRef reachabilityRef;
@property(atomic,readwrite,assign) KSReachabilityState state;

@end

static void onReachabilityChanged(SCNetworkReachabilityRef target,
                                  SCNetworkReachabilityFlags flags,
                                  void* info);


@implementation KSReachability

@synthesize onReachabilityChanged = _onReachabilityChanged;
@synthesize flags = _flags;
@synthesize reachable = _reachable;
@synthesize WWANOnly = _WWANOnly;
@synthesize reachabilityRef = _reachabilityRef;
@synthesize hostname = _hostname;
@synthesize notificationName = _notificationName;
@synthesize state = _state;

+ (KSReachability*) reachabilityToHost:(NSString*) hostname
{
    return as_autorelease([[self alloc] initWithHost:hostname]);
}

+ (KSReachability*) reachabilityToLocalNetwork
{
    struct sockaddr_in address;
    bzero(&address, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(IN_LINKLOCALNETNUM);

    return as_autorelease([[self alloc] initWithAddress:(const struct sockaddr*)&address]);
}

- (id) initWithHost:(NSString*) hostname
{
    hostname = [self extractHostName:hostname];
    if([hostname length] == 0)
    {
        struct sockaddr_in address;
        bzero(&address, sizeof(address));
        address.sin_len = sizeof(address);
        address.sin_family = AF_INET;

        return [self initWithAddress:(const struct sockaddr*)&address];
    }

    return [self initWithReachabilityRef:SCNetworkReachabilityCreateWithName(NULL, [hostname UTF8String])
                                hostname:hostname];
}

- (id) initWithAddress:(const struct sockaddr*) address
{
    return [self initWithReachabilityRef:SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, address)
                                hostname:nil];
}

- (id) initWithReachabilityRef:(SCNetworkReachabilityRef) reachabilityRef
                      hostname:(NSString*)hostname
{
    if((self = [super init]))
    {
        if(reachabilityRef == NULL)
        {
            NSLog(@"KSReachability Error: %s: Could not resolve reachability destination", __PRETTY_FUNCTION__);
            as_release(self);
            self = nil;
        }
        else
        {
            self.state = KSReachabilityState_Initializing;
            self.hostname = hostname;
            [self installReachability:reachabilityRef];
        }
    }
    return self;
}

- (void) dealloc
{
    [self uninstallReachability];
    as_release(_hostname);
    as_release(_notificationName);
    as_release(_onReachabilityChanged);
    as_superdealloc();
}

- (void) installReachability:(SCNetworkReachabilityRef) reachabilityRef
{
    @synchronized(self)
    {
        self.reachabilityRef = reachabilityRef;
        dispatch_async(dispatch_get_global_queue(0,0), ^
                       {
                           @synchronized(self)
                           {
                               // Need to do manual flags update BEFORE scheduling the run loop or else
                               // the two interfere with each other.
                               SCNetworkReachabilityFlags flags = 0;
                               if(SCNetworkReachabilityGetFlags(self.reachabilityRef, &flags))
                               {
                                   [self onReachabilityFlagsChanged:flags];
                               }
                               else
                               {
                                   NSLog(@"KSReachability Error: %s: SCNetworkReachabilityGetFlags failed", __PRETTY_FUNCTION__);
                                   [self setFailedState];
                                   return;
                               }

                               SCNetworkReachabilityContext context = {0, (as_bridge void*)self, NULL,  NULL, NULL};
                               if(!SCNetworkReachabilitySetCallback(self.reachabilityRef,
                                                                    onReachabilityChanged,
                                                                    &context))
                               {
                                   NSLog(@"KSReachability Error: %s: SCNetworkReachabilitySetCallback failed", __PRETTY_FUNCTION__);
                                   [self setFailedState];
                                   return;
                               }

                               if(!SCNetworkReachabilityScheduleWithRunLoop(self.reachabilityRef,
                                                                            CFRunLoopGetCurrent(),
                                                                            kCFRunLoopDefaultMode))
                               {
                                   NSLog(@"KSReachability Error: %s: SCNetworkReachabilityScheduleWithRunLoop failed", __PRETTY_FUNCTION__);
                                   [self setFailedState];
                                   return;
                               }
                           }
                       });
    }
}

- (void) uninstallReachability
{
    @synchronized(self)
    {
        if(self.reachabilityRef != NULL)
        {
            SCNetworkReachabilityUnscheduleFromRunLoop(self.reachabilityRef,
                                                       CFRunLoopGetCurrent(),
                                                       kCFRunLoopDefaultMode);
            CFRelease(self.reachabilityRef);
            self.reachabilityRef = NULL;
        }
    }
}

- (void) setFailedState
{
    self.state = KSReachabilityState_Failed;
    self.flags = 0;
    [self uninstallReachability];
}

- (NSString*) extractHostName:(NSString*) potentialURL
{
    if(potentialURL == nil)
    {
        return nil;
    }

    NSUInteger startIndex = 0;
    NSRange range = [potentialURL rangeOfString:@"//"];
    if(range.location != NSNotFound)
    {
        startIndex = range.location + 2;
    }
    range = [potentialURL rangeOfString:@"/"
                                options:0
                                  range:NSMakeRange(startIndex, [potentialURL length] - startIndex)];
    if(range.location == NSNotFound)
    {
        return potentialURL;
    }
    return [potentialURL substringWithRange:NSMakeRange(startIndex, range.location - startIndex)];
}

- (BOOL) isReachableWithFlags:(SCNetworkReachabilityFlags) flags
{
    if(!(flags & kSCNetworkReachabilityFlagsReachable))
    {
        // Not reachable at all.
        return NO;
    }

    if(!(flags & kSCNetworkReachabilityFlagsConnectionRequired))
    {
        // Reachable with no connection required.
        return YES;
    }

    if((flags & (kSCNetworkReachabilityFlagsConnectionOnDemand |
                 kSCNetworkReachabilityFlagsConnectionOnTraffic)) &&
       !(flags & kSCNetworkReachabilityFlagsInterventionRequired))
    {
        // Automatic connection with no user intervention required.
        return YES;
    }

    return NO;
}

- (void) onReachabilityFlagsChanged:(SCNetworkReachabilityFlags) flags
{
    @synchronized(self)
    {
        if(self.state == KSReachabilityState_Failed)
        {
            return;
        }

        if(_flags != flags || self.state == KSReachabilityState_Initializing)
        {
            BOOL reachable = [self isReachableWithFlags:flags];
#if TARGET_OS_IPHONE
            BOOL WWANOnly = reachable && (flags & kSCNetworkReachabilityFlagsIsWWAN) != 0;
#else
            BOOL WWANOnly = NO;
#endif

            BOOL rChanged = (_reachable != reachable) || self.state == KSReachabilityState_Initializing;
            BOOL wChanged = (_WWANOnly != WWANOnly) || self.state == KSReachabilityState_Initializing;

            dispatch_async(dispatch_get_main_queue(), ^
                           {
                               as_autoreleasepool_start(pool);

                               [self willChangeValueForKey:kKVOProperty_Flags];
                               if(rChanged) [self willChangeValueForKey:kKVOProperty_Reachable];
                               if(wChanged) [self willChangeValueForKey:kKVOProperty_WWANOnly];

                               _flags = flags;
                               _reachable = reachable;
                               _WWANOnly = WWANOnly;

                               if(self.state == KSReachabilityState_Initializing)
                               {
                                   self.state = KSReachabilityState_Valid;
                               }

                               [self didChangeValueForKey:kKVOProperty_Flags];
                               if(rChanged) [self didChangeValueForKey:kKVOProperty_Reachable];
                               if(wChanged) [self didChangeValueForKey:kKVOProperty_WWANOnly];

                               if(self.onReachabilityChanged != nil)
                               {
                                   self.onReachabilityChanged(self);
                               }

                               if(self.notificationName != nil)
                               {
                                   NSNotificationCenter* nCenter = [NSNotificationCenter defaultCenter];
                                   [nCenter postNotificationName:self.notificationName object:self];
                               }

                               as_autoreleasepool_end(pool);
                           });
        }
    }
}


static void onReachabilityChanged(SCNetworkReachabilityRef target,
                                  SCNetworkReachabilityFlags flags,
                                  void* info)
{
#pragma unused(target)
    KSReachability* reachability = (as_bridge KSReachability*) info;
    [reachability onReachabilityFlagsChanged:flags];
}

@end


// ----------------------------------------------------------------------
#pragma mark - KSReachableOperation -
// ----------------------------------------------------------------------

@interface KSReachableOperation ()

@property(nonatomic,readwrite,retain) KSReachability* reachability;

@end


@implementation KSReachableOperation

@synthesize reachability = _reachability;

+ (KSReachableOperation*) operationWithHost:(NSString*) host
                                  allowWWAN:(BOOL) allowWWAN
                                      block:(void(^)()) block
{
    return as_autorelease([[self alloc] initWithHost:host
                                           allowWWAN:allowWWAN
                                               block:block]);
}

+ (KSReachableOperation*) operationWithReachability:(KSReachability*) reachability
                                          allowWWAN:(BOOL) allowWWAN
                                              block:(void(^)()) block
{
    return as_autorelease([[self alloc] initWithReachability:reachability
                                                   allowWWAN:allowWWAN
                                                       block:block]);
}

- (id) initWithHost:(NSString*) host
          allowWWAN:(BOOL) allowWWAN
              block:(void(^)()) block
{
    return [self initWithReachability:[KSReachability reachabilityToHost:host]
                            allowWWAN:allowWWAN
                                block:block];
}

- (id) initWithReachability:(KSReachability*) reachability
                  allowWWAN:(BOOL) allowWWAN
                      block:(void(^)()) block
{
    if((self = [super init]))
    {
        self.reachability = reachability;
        if(self.reachability == nil)
        {
            as_release(self);
            self = nil;
        }
        else
        {
            block = as_autorelease([block copy]);
            void(^onReachabilityChanged)(KSReachability* reachability) = ^(KSReachability* reachability2)
            {
                if(reachability2.state == KSReachabilityState_Valid &&
                   reachability2.reachable &&
                   (allowWWAN || !reachability2.WWANOnly))
                {
                    reachability2.onReachabilityChanged = nil;
                    block();
                }
            };

            self.reachability.onReachabilityChanged = onReachabilityChanged;
            if(self.reachability.state == KSReachabilityState_Valid)
            {
                onReachabilityChanged(self.reachability);
            }
        }
    }
    return self;
}

- (void) dealloc
{
    as_release(_reachability);
    as_superdealloc();
}

@end

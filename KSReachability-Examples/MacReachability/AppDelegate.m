//
//  AppDelegate.m
//  MacReachability
//
//  Created by Karl Stenerud on 5/6/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "AppDelegate.h"
#import <KSReachabilityMac/KSReachability.h>

@interface AppDelegate ()

@property(strong,nonatomic) KSReachability* reachability;
@property(strong,nonatomic) KSReachableOperation* reachableOperation;

- (void) updateLabels;

- (void) showAlertWithTitle:(NSString*) title
                    message:(NSString*) message;

- (void) onReachabilityChanged:(NSNotification*) notification;

@end


@implementation AppDelegate

@synthesize window = _window;
@synthesize hostField = _hostField;
@synthesize reachableLabel = _reachableLabel;
@synthesize flagsLabel = _flagsLabel;
@synthesize reachability = _reachability;
@synthesize reachableOperation = _reachableOperation;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    #pragma unused(aNotification)
    NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self
                           selector:@selector(onReachabilityChanged:)
                               name:kDefaultNetworkReachabilityChangedNotification
                             object:nil];
    
    [self updateLabels];
}

- (IBAction)onStartNewReachability:(id)sender
{
    #pragma unused(sender)
    __unsafe_unretained AppDelegate* blockSelf = self;
    NSString* hostname = [self.hostField stringValue];
    
    if(self.reachability != nil)
    {
        [self.reachability removeObserver:self forKeyPath:@"reachable"];
    }
    
    // Create a new reachability object.
    self.reachability = [KSReachability reachabilityToHost:hostname];
    
    // Find out when initialization has completed.
    self.reachability.onInitializationComplete = ^(KSReachability* reachability)
    {
        NSLog(@"Initialization complete. Reachability = %d. Flags = %x", reachability.reachable, reachability.flags);
    };

    // Set a callback.
    self.reachability.onReachabilityChanged = ^(KSReachability* reachability)
    {
        NSLog(@"Reachability changed to %d. Flags = %x (blocks)", reachability.reachable, reachability.flags);
        [blockSelf updateLabels];
    };
    
    // Enable notifications via NSNotificationCenter.
    self.reachability.notificationName = kDefaultNetworkReachabilityChangedNotification;
    
    // Enable notifications via KVO.
    [self.reachability addObserver:self
                        forKeyPath:@"reachable"
                           options:NSKeyValueObservingOptionNew
                           context:NULL];
    
    
    // Create a one-shot operation that gets fired once the host is reachable.
    self.reachableOperation = [KSReachableOperation operationWithHost:hostname
                                                            allowWWAN:NO
                                               onReachabilityAchieved:^
                               {
                                   [self showAlertWithTitle:@"One-time message"
                                                    message:@"Host is reachable!"];
                               }];
    
    
    [self updateLabels];
}

- (void) updateLabels
{
    SCNetworkReachabilityFlags flags = self.reachability.flags;
    [self.flagsLabel setStringValue:[NSString stringWithFormat:@"%c%c %c%c%c%c%c%c",
                                     (flags & kSCNetworkReachabilityFlagsReachable)            ? 'R' : '-',
                                     
                                     (flags & kSCNetworkReachabilityFlagsTransientConnection)  ? 't' : '-',
                                     (flags & kSCNetworkReachabilityFlagsConnectionRequired)   ? 'c' : '-',
                                     (flags & kSCNetworkReachabilityFlagsConnectionOnTraffic)  ? 'C' : '-',
                                     (flags & kSCNetworkReachabilityFlagsInterventionRequired) ? 'i' : '-',
                                     (flags & kSCNetworkReachabilityFlagsConnectionOnDemand)   ? 'D' : '-',
                                     (flags & kSCNetworkReachabilityFlagsIsLocalAddress)       ? 'l' : '-',
                                     (flags & kSCNetworkReachabilityFlagsIsDirect)             ? 'd' : '-']];
    
    [self.reachableLabel setStringValue:self.reachability.reachable ? @"YES" : @"NO"];
}

- (void) onReachabilityChanged:(NSNotification*) notification
{
    KSReachability* reachability = (KSReachability*)notification.object;
    NSLog(@"Reachability changed to %d. Flags = %x (NSNotification)", reachability.reachable, reachability.flags);
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    #pragma unused(keyPath)
    #pragma unused(change)
    #pragma unused(context)
    KSReachability* reachability = (KSReachability*)object;
    NSLog(@"Reachability changed to %d. Flags = %x (KVO)", reachability.reachable, reachability.flags);
}


- (void) showAlertWithTitle:(NSString*) title
                    message:(NSString*) message
{
    NSAlert* alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:@"OK"];
    [alert setMessageText:title];
    [alert setInformativeText:message];
    [alert setAlertStyle:NSInformationalAlertStyle];
    [alert runModal];
}

@end

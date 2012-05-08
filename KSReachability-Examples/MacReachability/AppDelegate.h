//
//  AppDelegate.h
//  MacReachability
//
//  Created by Karl Stenerud on 5/6/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (assign,nonatomic) IBOutlet NSWindow *window;

@property(strong, nonatomic) IBOutlet NSTextField* hostField;
@property(strong, nonatomic) IBOutlet NSTextField* reachableLabel;
@property(strong, nonatomic) IBOutlet NSTextField* flagsLabel;

- (IBAction)onStartNewReachability:(id)sender;

@end

//
//  ViewController.h
//  iOSReachability
//
//  Created by Karl Stenerud on 5/6/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//


/* Quick example of how to use KSReachability.
 *
 * Tap "Start new reachability" to create a new reachability object.
 *
 * Once reachability is established, a one-time alert will pop up (using KSReachableOperation).
 *
 * The status section at the bottom will update as reachability changes.
 */

#import <UIKit/UIKit.h>

@interface ViewController : UIViewController <UITextFieldDelegate>

@property(strong, nonatomic) IBOutlet UITextField* hostField;
@property(strong, nonatomic) IBOutlet UILabel* internetLabel;
@property(strong, nonatomic) IBOutlet UILabel* reachableLabel;
@property(strong, nonatomic) IBOutlet UILabel* wwanLabel;
@property(strong, nonatomic) IBOutlet UILabel* flagsLabel;

- (IBAction)onStartNewReachability:(id)sender;

@end

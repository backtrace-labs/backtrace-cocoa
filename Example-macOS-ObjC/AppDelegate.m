//
//  AppDelegate.m
//  Example-macOS-ObjC
//
//  Created by Marcin Karmelita on 09/12/2018.
//

#import "AppDelegate.h"
@import Backtrace;

@interface AppDelegate ()

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    [[BacktraceClient shared] registerWithEndpoint: @"https://yolo.sp.backtrace.io:6098" token: @"b06c6083414bf7b8e200ad994c9c8ea5d6c8fa747b6608f821278c48a4d408c3"];
    
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


@end

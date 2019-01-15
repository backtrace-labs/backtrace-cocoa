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
    [[BacktraceClient shared] registerWithEndpoint: @"" token: @""];
    
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


@end

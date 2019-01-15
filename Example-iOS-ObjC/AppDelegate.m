//
//  AppDelegate.m
//  Example-iOS-ObjC
//
//  Created by Marcin Karmelita on 08/12/2018.
//

#import "AppDelegate.h"
@import Backtrace;

@interface AppDelegate ()

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [[BacktraceClient shared] registerWithEndpoint: @"" token: @""];
    return YES;
}

@end

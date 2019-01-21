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
    BacktraceCredentials *credentials = [[BacktraceCredentials alloc]
                                         initWithEndpoint: [NSURL URLWithString: @"https://yolo.sp.backtrace.io:6098"]
                                         token: @"b06c6083414bf7b8e200ad994c9c8ea5d6c8fa747b6608f821278c48a4d408c3"];
    [BacktraceClient.shared registerWithCredentials: credentials];

    return YES;
}

@end

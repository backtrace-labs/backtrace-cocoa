#import "AppDelegate.h"
@import Backtrace;

@interface AppDelegate ()

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BacktraceCredentials *credentials = [[BacktraceCredentials alloc]
                                         initWithEndpoint: [NSURL URLWithString: @""]
                                         token: @""];
    [BacktraceClient.shared registerWithCredentials: credentials];

    return YES;
}

@end

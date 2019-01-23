#import "AppDelegate.h"
@import Backtrace;

@interface AppDelegate ()

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    BacktraceCredentials *credentials = [[BacktraceCredentials alloc]
                                         initWithEndpoint: [NSURL URLWithString: @""]
                                         token: @""];
    [BacktraceClient.shared registerWithCredentials: credentials];
    
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


@end

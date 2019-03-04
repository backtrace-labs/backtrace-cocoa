#import "AppDelegate.h"
@import Backtrace;

@interface AppDelegate ()

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    BacktraceCredentials *credentials = [[BacktraceCredentials alloc]
                                         initWithEndpoint: [NSURL URLWithString: @"https://backtrace.io"]
                                         token: @"token"];
    BacktraceClient.shared = [[BacktraceClient alloc] initWithCredentials: credentials error: NULL];
    [BacktraceClient.shared setClientAttributes: @{@"foo": @"bar"}];

    @try {
        NSArray *array = @[];
        NSObject *object = array[1]; //will throw exception
    } @catch (NSException *exception) {
        [[BacktraceClient shared] sendWithCompletion:^(BacktraceResult * _Nonnull result) {
            NSLog(@"%@", result);
        }];
    } @finally {

    }

}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

@end

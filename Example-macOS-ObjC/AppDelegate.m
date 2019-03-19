#import "AppDelegate.h"
@import Backtrace;

@interface AppDelegate ()

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    
    BacktraceCredentials *credentials = [[BacktraceCredentials alloc]
                                         initWithEndpoint: [NSURL URLWithString: @"https://backtrace.io"]
                                         token: @"token"];
    BacktraceClientConfiguration *configuration = [[BacktraceClientConfiguration alloc] initWithCredentials: credentials
                                                                                                 dbSettings: [BacktraceDatabaseSettings new]
                                                                                              reportsPerMin: 3];
    BacktraceClient.shared = [[BacktraceClient alloc] initWithConfiguration: configuration error: nil];
    [BacktraceClient.shared setUserAttributes: @{@"foo": @"bar"}];

    @try {
        NSArray *array = @[];
        NSObject *object = array[1]; //will throw exception
    } @catch (NSException *exception) {
        NSArray *paths = @[[[NSBundle mainBundle] pathForResource: @"test" ofType: @"txt"]];
        [[BacktraceClient shared] sendWithAttachmentPaths: paths completion: ^(BacktraceResult * _Nonnull result) {
            NSLog(@"%@", result);
        }];
    } @finally {

    }
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

@end

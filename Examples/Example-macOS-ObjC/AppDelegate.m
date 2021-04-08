#import "AppDelegate.h"
#import "Keys.h"
@import Backtrace;

@interface AppDelegate () <BacktraceClientDelegate>

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    
    BacktraceCredentials *credentials = [[BacktraceCredentials alloc]
                                         initWithSubmissionUrl: [NSURL URLWithString: Keys.backtraceSubmissionUrl]];
    BacktraceDatabaseSettings *backtraceDatabaseSettings = [[BacktraceDatabaseSettings alloc] init];
    backtraceDatabaseSettings.maxRecordCount = 1000;
    backtraceDatabaseSettings.maxDatabaseSize = 10;
    backtraceDatabaseSettings.retryInterval = 5;
    backtraceDatabaseSettings.retryLimit = 3;
    backtraceDatabaseSettings.retryBehaviour = RetryBehaviourInterval;
    backtraceDatabaseSettings.retryOrder = RetryOrderStack;
       
    BacktraceClientConfiguration *configuration = [[BacktraceClientConfiguration alloc]
                                                   initWithCredentials: credentials
                                                   dbSettings: backtraceDatabaseSettings
                                                   reportsPerMin: 3
                                                   allowsAttachingDebugger: TRUE
                                                   detectOOM: FALSE];
    BacktraceClient.shared = [[BacktraceClient alloc] initWithConfiguration: configuration error: nil];
    [BacktraceClient.shared setAttributes: @{@"foo": @"bar"}];
    BacktraceClient.shared.delegate = self;
    
    @try {
        NSArray *array = @[];
        (void)array[1]; //will throw exception
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

#pragma mark - BacktraceClientDelegate
- (BacktraceReport * _Nonnull) willSend: (BacktraceReport * _Nonnull) report {
    NSLog(@"%@", report);
    NSMutableDictionary *dict = [report.attributes mutableCopy];
    [dict setObject: @"just before send" forKey: @"added"];
    report.attributes = dict;
    return report;
}

- (NSURLRequest * _Nonnull) willSendRequest: (NSURLRequest * _Nonnull) request {
    NSLog(@"%@", request);
    return request;
}

- (void) serverDidRespond: (BacktraceResult * _Nonnull) result {
    NSLog(@"%@", result);
}

- (void)connectionDidFail:(NSError * _Nonnull) error {
    NSLog(@"%@", error);
}

- (void)didReachLimit:(BacktraceResult * _Nonnull) result {
    NSLog(@"%@", result);
}

@end

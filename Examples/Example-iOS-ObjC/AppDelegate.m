#import "AppDelegate.h"
#import "Keys.h"

@import Backtrace;

@interface AppDelegate () <BacktraceClientDelegate>

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BacktraceCredentials *credentials = [[BacktraceCredentials alloc]
                                         initWithEndpoint: [NSURL URLWithString: Keys.backtraceUrl]
                                         token: [Keys backtraceToken]];
    BacktraceDatabaseSettings *backtraceDatabaseSettings = [[BacktraceDatabaseSettings alloc] init];
    backtraceDatabaseSettings.maxRecordCount = 1000;
    backtraceDatabaseSettings.maxDatabaseSize = 10;
    backtraceDatabaseSettings.retryInterval = 5;
    backtraceDatabaseSettings.retryLimit = 3;
    backtraceDatabaseSettings.retryBehaviour = RetryBehaviourInterval;
    backtraceDatabaseSettings.retryOrder = RetryOderStack;
    
    BacktraceClientConfiguration *configuration = [[BacktraceClientConfiguration alloc]
                                                   initWithCredentials: credentials
                                                   dbSettings: backtraceDatabaseSettings
                                                   reportsPerMin: 3
                                                   allowsAttachingDebugger: TRUE];
    BacktraceClient.shared = [[BacktraceClient alloc] initWithConfiguration: configuration error: nil];
    BacktraceClient.shared.delegate = self;

    // sending NSException
    @try {
        NSArray *array = @[];
        NSObject *object = array[1]; // will throw exception
    } @catch (NSException *exception) {
        NSArray *paths = @[[[NSBundle mainBundle] pathForResource: @"test" ofType: @"txt"]];
        [[BacktraceClient shared] sendWithAttachmentPaths: paths completion: ^(BacktraceResult * _Nonnull result) {
            NSLog(@"%@", result);
        }];
    } @finally {

    }

    //sending NSError
    NSError *error = [NSError errorWithDomain: @"backtrace.domain" code: 100 userInfo: @{}];
    NSArray *paths = @[[[NSBundle mainBundle] pathForResource: @"test" ofType: @"txt"]];
    [[BacktraceClient shared] sendWithAttachmentPaths: paths completion: ^(BacktraceResult * _Nonnull result) {
        NSLog(@"%@", result);
    }];

    return YES;
}

#pragma mark - BacktraceClientDelegate
- (BacktraceReport *)willSend:(BacktraceReport *)report {
    NSMutableDictionary *dict = [report.attributes mutableCopy];
    [dict setObject: @"just before send" forKey: @"added"];
    report.attributes = dict;
    return report;
}

- (void)serverDidFail:(NSError *)error {
    
}

- (void)serverDidResponse:(BacktraceResult *)result {
    
}

- (NSURLRequest *)willSendRequest:(NSURLRequest *)request {
    return request;
}

- (void)didReachLimit:(BacktraceResult *)result {
    
}

@end

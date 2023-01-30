#import "AppDelegate.h"
#import "Keys.h"

@import Backtrace;

@interface AppDelegate () <BacktraceClientDelegate>

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    
    /*  Enable crash loop detector.
        You can pass crashes count threshold (maximum amount of launching events to evaluate) here.
        If threshold is not specified or you pass 0 - default value '5' will be used.
     */
    [BacktraceClient enableCrashLoopDetection: 0];
    
    if([BacktraceClient isSafeModeRequired]) {
        // When crash loop is detected we need to reset crash loop counter to restart crash loop detection from scratch
        [BacktraceClient resetCrashLoopDetection];
        // TODO: Perform any custom checks if necessary and decide if Backtrace should be launched
        return NO;
    }
    else {
        [BacktraceClient disableCrashLoopDetection];
    }

    NSArray *paths = @[[[NSBundle mainBundle] pathForResource: @"test" ofType: @"txt"]];
    NSString *fileName = @"myCustomFile.txt";
    NSURL *libraryUrl = [[[NSFileManager defaultManager] URLsForDirectory:NSLibraryDirectory
             inDomains:NSUserDomainMask] lastObject];
    NSURL *fileUrl = [libraryUrl URLByAppendingPathComponent:fileName];

    BacktraceCredentials *credentials = [[BacktraceCredentials alloc]
                                         initWithEndpoint: [NSURL URLWithString: Keys.backtraceUrl]
                                         token: [Keys backtraceToken]];
    BacktraceDatabaseSettings *backtraceDatabaseSettings = [[BacktraceDatabaseSettings alloc] init];
    backtraceDatabaseSettings.maxRecordCount = 10;

    BacktraceClientConfiguration *configuration = [[BacktraceClientConfiguration alloc]
                                                   initWithCredentials: credentials
                                                   dbSettings: backtraceDatabaseSettings
                                                   reportsPerMin: 3
                                                   allowsAttachingDebugger: TRUE
                                                   detectOOM: TRUE];
    BacktraceClient.shared = [[BacktraceClient alloc] initWithConfiguration: configuration error: nil];
    BacktraceClient.shared.attributes = @{@"foo": @"bar", @"testing": @YES};
    BacktraceClient.shared.attachments = [NSArray arrayWithObjects:fileUrl, nil];

    //sending NSError
    [[BacktraceClient shared] sendWithAttachmentPaths: paths completion: ^(BacktraceResult * _Nonnull result) {
        NSLog(@"%@", result);
    }];

    BacktraceClient.shared.delegate = self;

    // Enable error free metrics https://docs.saucelabs.com/error-reporting/web-console/overview/#stability-metrics-widgets
    [BacktraceClient.shared.metrics enableWithSettings: [BacktraceMetricsSettings alloc]];

    // Enable breadcrumbs https://docs.saucelabs.com/error-reporting/web-console/debug/#breadcrumbs-section
    [BacktraceClient.shared enableBreadcrumbs];
    NSDictionary *attributes = @{@"My Attribute":@"My Attribute Value"};

    // Add breadcrumb
    [[BacktraceClient shared] addBreadcrumb:@"My Native Breadcrumb"
                                 attributes:attributes
                                       type:BacktraceBreadcrumbTypeUser
                                      level:BacktraceBreadcrumbLevelError];
    return YES;
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

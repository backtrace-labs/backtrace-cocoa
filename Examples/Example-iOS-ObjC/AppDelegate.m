#import "AppDelegate.h"
#import "Keys.h"

@import Backtrace;

@interface AppDelegate () <BacktraceClientDelegate>

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
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

    // sending NSException
    @try {
        NSArray *array = @[];
        //array[1]; // will throw exception
    } @catch (NSException *exception) {
        [[BacktraceClient shared] sendWithAttachmentPaths: [NSArray init]  completion: ^(BacktraceResult * _Nonnull result) {
            NSLog(@"%@", result);
        }];
    } @finally {

    }

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

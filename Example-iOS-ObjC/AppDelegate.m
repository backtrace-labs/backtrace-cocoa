#import "AppDelegate.h"
@import Backtrace;

@interface AppDelegate () <BacktraceClientDelegate>

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BacktraceCredentials *credentials = [[BacktraceCredentials alloc]
                                         initWithEndpoint: [NSURL URLWithString: @"https://backtrace.io"]
                                         token: @""];
    [BacktraceClient.shared registerWithCredentials: credentials];
    
    BacktraceClient.shared.delegate = self;

    // sending NSException
    @try {
        NSArray *array = @[];
        NSObject *object = array[1]; // will throw exception
    } @catch (NSException *exception) {
        [[BacktraceClient shared] sendWithException: exception completion:^(BacktraceResult * _Nonnull result) {
            NSLog(@"%@", result);
        }];
    } @finally {

    }

    //sending NSError
    NSError *error = [NSError errorWithDomain: @"backtrace.domain" code: 100 userInfo: @{}];
    [[BacktraceClient shared] sendWithCompletion:^(BacktraceResult * _Nonnull result) {
        NSLog(@"%@", result);
    }];

    return YES;
}

#pragma mark - BacktraceClientDelegate
- (BacktraceCrashReport *)willSend:(BacktraceCrashReport *)report {
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

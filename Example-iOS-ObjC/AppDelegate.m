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

@end

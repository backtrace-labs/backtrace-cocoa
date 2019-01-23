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

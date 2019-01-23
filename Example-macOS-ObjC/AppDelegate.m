#import "AppDelegate.h"
@import Backtrace;

@interface AppDelegate ()

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    BacktraceCredentials *credentials = [[BacktraceCredentials alloc]
                                         initWithEndpoint: [NSURL URLWithString: @"https://yolo.sp.backtrace.io:6098"]
                                         token: @"b06c6083414bf7b8e200ad994c9c8ea5d6c8fa747b6608f821278c48a4d408c3"];
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

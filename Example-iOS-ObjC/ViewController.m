
#import "ViewController.h"
@import Backtrace;

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UITextView *textView;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
}
- (IBAction) liveReportAction: (id) sender {
    NSString *customErrorDomain = @"backtrace";
    NSInteger errorCode = 100;
    NSError *exampleError = [NSError errorWithDomain: customErrorDomain code: errorCode userInfo: nil];
    
    [[BacktraceClient shared] send: exampleError completion:^(BacktraceResult * _Nonnull result) {
        NSLog(@"%@", result.message);
    }];
    
    NSException *exception = [NSException exceptionWithName: @"backtrace.exception" reason: @"backtrace.reason" userInfo: @{}];
    [[BacktraceClient shared] sendWithException: exception completion:^(BacktraceResult * _Nonnull result) {
        NSLog(@"%@", result.message);
    }];
    
}

- (IBAction) crashAction: (id) sender {
    NSArray *array = @[];
    NSObject *o = array[1];
}


@end

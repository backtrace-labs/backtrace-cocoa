
#import "ViewController.h"
@import Backtrace;

@interface ViewController()
@property (unsafe_unretained) IBOutlet NSTextView *textView;
@property (weak) IBOutlet NSScrollView *scrollView;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view.
}
- (IBAction)crashAction:(id)sender {
    
}

- (IBAction)liveReportAction:(id)sender {
    
}

- (IBAction)liveReportButtonAction:(id)sender {
    NSString *customErrorDomain = @"backtrace";
    NSInteger errorCode = 100;
    NSError *exampleError = [NSError errorWithDomain: customErrorDomain code: errorCode userInfo: nil];
    
    [[BacktraceClient shared] send: exampleError completion:^(BacktraceResult * _Nonnull result) {
        NSLog(@"%@", result.message);
    }];
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}


@end

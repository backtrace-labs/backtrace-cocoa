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
    NSArray *paths = @[@"/home/test.txt"];
    [[BacktraceClient shared] sendWithAttachmentPaths:paths completion:^(BacktraceResult * _Nonnull result) {
        NSLog(@"%@", result.message);
    }];
}

- (IBAction) crashAction: (id) sender {
    NSArray *array = @[];
    NSObject *o = array[1];
}


@end

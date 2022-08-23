#import "ViewController.h"
@import Backtrace;

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UITextView *textView;

@end

@implementation ViewController

static NSMutableData *wastedMemory = nil;

- (void)viewDidLoad {
    [super viewDidLoad];
    wastedMemory = [[NSMutableData alloc] init];
}

- (IBAction) outOfMemoryReportAction: (id) sender {
    for (int i = 0; i < 100 ; i++) {
        [wastedMemory appendData:[NSMutableData dataWithLength:500000000]];
    }
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

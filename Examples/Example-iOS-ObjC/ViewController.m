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
    
    NSString * text = [NSString stringWithFormat: @"BadEvents: %ld\nIs Safe to Launch: %s",
                       [BacktraceClient consecutiveCrashesCount],
                       [BacktraceClient isInSafeMode] ? "FALSE" : "TRUE" ];
    [_textView setText: text];
}

- (IBAction) outOfMemoryReportAction: (id) sender {
    // The trick is: to aggressively take up memory but not allocate a block too large to cause a crash
    // This is obviously device dependent, so the 500k may have to be tweaked
    int size = 500000;
    for (int i = 0; i < 10000 ; i++) {
        [wastedMemory appendData:[NSMutableData dataWithLength:size]];
    }
    // Or if all that fails, just force a memory warning manually :)
    [[UIApplication sharedApplication] performSelector:@selector(_performMemoryWarning)];
}

- (IBAction) liveReportAction: (id) sender {
    NSArray *paths = @[@"/home/test.txt"];
    [[BacktraceClient shared] sendWithAttachmentPaths:paths completion:^(BacktraceResult * _Nonnull result) {
        NSLog(@"%@", result.message);
    }];
}

- (IBAction) crashAction: (id) sender {
    NSArray *array = @[];
    array[1];
}


@end

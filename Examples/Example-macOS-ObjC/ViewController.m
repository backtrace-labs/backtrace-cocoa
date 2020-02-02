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
    NSArray *array = @[];
    (void)array[1];
}

- (IBAction)liveReportAction:(id)sender {
    
}

- (IBAction)liveReportButtonAction:(id)sender {
    NSArray *array = @[];
    (void)array[1];
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}


@end

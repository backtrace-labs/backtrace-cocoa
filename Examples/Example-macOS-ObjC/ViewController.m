#import "ViewController.h"
@import Backtrace;

@interface ViewController()
@property (unsafe_unretained) IBOutlet NSTextView *textView;
@property (weak) IBOutlet NSScrollView *scrollView;

@end

@implementation ViewController

- (void) viewDidLoad {
    [super viewDidLoad];

    SEL selector = NSSelectorFromString(@"updateUI");
    [self performSelector: selector withObject: nil afterDelay: 0.5];

    // Do any additional setup after loading the view.
}

- (void) updateUI {
    NSString * text = [NSString stringWithFormat: @"BadEvents: %ld\nIs Safe to Launch: %@",
                       [BacktraceClient consecutiveCrashesCount],
                       [BacktraceClient isInSafeMode] ? @"FALSE" : @"TRUE" ];
    NSLog(@"updateUI: text = %@", text);
    [_textView setString: text];
}

- (IBAction) crashAction:(id)sender {
    // NOTE: crashing with array out of bounds case doesn't terminate app on some OS versions, so using runtime crash to be sure signal is received.
    NSString * string = [NSString stringWithFormat: @"%@", 12];
}

- (IBAction) liveReportAction:(id)sender {
    
}

- (IBAction) liveReportButtonAction:(id)sender {
    NSArray *array = @[];
    (void)array[1];
}

- (void) setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];
    // Update the view, if already loaded.
}

@end

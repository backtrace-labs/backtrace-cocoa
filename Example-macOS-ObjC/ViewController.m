//
//  ViewController.m
//  Example-macOS-ObjC
//
//  Created by Marcin Karmelita on 09/12/2018.
//

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
    
    NSString *reportInfo = [[BacktraceClient shared] generateLiveReport];
    [self.textView setString: reportInfo];
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}


@end

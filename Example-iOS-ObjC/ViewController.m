//
//  ViewController.m
//  Example-iOS-ObjC
//
//  Created by Marcin Karmelita on 08/12/2018.
//

#import "ViewController.h"
@import Backtrace;

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UITextView *textView;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.textView.text = [[BacktraceClient shared] pendingCrashReport];
    
}
- (IBAction) liveReportAction: (id) sender {
    self.textView.text = [[BacktraceClient shared] generateLiveReport];
}

- (IBAction) crashAction: (id) sender {
    NSArray *array = @[];
    NSObject *o = array[1];
}


@end

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
    
}
- (IBAction) liveReportAction: (id) sender {
    [[BacktraceClient shared] sendWithCompletion:^(BacktraceResult * _Nonnull result) {
        NSLog(@"%ld: %@", (long)result.status, result.message);
    }];
    
}

- (IBAction) crashAction: (id) sender {
    NSArray *array = @[];
    NSObject *o = array[1];
}


@end

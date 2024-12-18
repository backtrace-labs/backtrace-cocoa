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
    // The trick is: to aggressively take up memory but not allocate a block too large to cause a crash
    // This is obviously device dependent, so the 500k may have to be tweaked
//    int size = 500000;
//    for (int i = 0; i < 10000 ; i++) {
//        [wastedMemory appendData:[NSMutableData dataWithLength:size]];
//    }
//    // Or if all that fails, just force a memory warning manually :)
//    [[UIApplication sharedApplication] performSelector:@selector(_performMemoryWarning)];
    
    
//        NSArray *paths = @[@"/home/test.txt"];
//    
//        NSString *domain = @"com.backtrace.exampleApp";
//        NSInteger errorCode = 1001;
//        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: @"Something went wrong." };
//    
//        NSError *error = [NSError errorWithDomain:domain
//                                             code:errorCode
//                                         userInfo:userInfo];
//    
//        NSLog(@"Error: %@", error);
//    
//        [[BacktraceClient shared] sendWithError:error attachmentPaths:paths completion:^(BacktraceResult * _Nonnull result) {
//            NSLog(@"%@", result.message);
//        }];
   
    
    
//    NSException *exception = [self generateException];
//    @throw exception;
    
//    NSArray *paths = @[@"/home/test.txt"];
//    
//    @try {
//        [self throwTestException];
//
//    } @catch (NSException *exception) {
//        NSLog(@"Exception: %@", exception.callStackSymbols);
//        
//        
//            [[BacktraceClient shared] sendWithException:exception attachmentPaths:paths completion:^(BacktraceResult * _Nonnull result) {
//                NSLog(@"%@", result.message);
//            }];
//
//    }
    
    NSLog(@"Starting Crash Trigger Simulation...");
    [self simulateCrash];
    [[NSRunLoop currentRunLoop] run];
        
}

- (IBAction) liveReportAction: (id) sender {
    NSArray *paths = @[@"/home/test.txt"];
//    [[BacktraceClient shared] sendWithAttachmentPaths:paths completion:^(BacktraceResult * _Nonnull result) {
//        NSLog(@"%@", result.message);
//    }];
    
//    NSString *domain = @"com.backtrace.exampleApp";
//    NSInteger errorCode = 1001;
//    NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: @"Something went wrong." };
//
//    NSError *error = [NSError errorWithDomain:domain
//                                         code:errorCode
//                                     userInfo:userInfo];
//
//    NSLog(@"Error: %@", error);
//    
//    [[BacktraceClient shared] sendWithError:error attachmentPaths:paths completion:^(BacktraceResult * _Nonnull result) {
//        NSLog(@"%@", result.message);
//    }];
    
    //    @try {
    //        [self throwTestException];
    //
    //    } @catch (NSException *exception) {
    //        NSLog(@"Exception: %@", exception.callStackSymbols);
    //        [[BacktraceClient shared] sendWithException:exception attachmentPaths:paths completion:^(BacktraceResult * _Nonnull result) {
    //            NSLog(@"%@", result.message);
    //        }];
    //
    //
    //    }
        
    //    [[BacktraceClient shared] sendWithMessage:@"This is a message for Konrad" attachmentPaths:paths completion:^(BacktraceResult * _Nonnull result) {
    //        NSLog(@"%@", result.message);
    //    }];
    
    
//        @try {
//            [self throwTestException];
//    
//        } @catch (NSException *exception) {
//            NSLog(@"Exception: %@", exception.callStackSymbols);
//            
//            
////            [[BacktraceClient shared] sendWithException:exception attachmentPaths:paths completion:^(BacktraceResult * _Nonnull result) {
////                NSLog(@"%@", result.message);
////            }];
//    
//            [[BacktraceClient shared] sendWithMessage:@"OVERFLOW" attachmentPaths:paths completion:^(BacktraceResult * _Nonnull result) {
//                NSLog(@"%@", result.message);
//            }];
//    
//        }
        
    
    [[NSRunLoop currentRunLoop] run];

    
    
//    NSException *exception = [self generateException];
//
//        @try {
//            
//            @throw exception;
//    
//        } @catch (NSException *exception) {
//            NSLog(@"Exception: %@", exception.callStackSymbols);
//            [[BacktraceClient shared] sendWithException:exception attachmentPaths:paths completion:^(BacktraceResult * _Nonnull result) {
//                NSLog(@"%@", result.message);
//            }];
//    
//    
//        }
    

    
    
//    @try {
//            NSString *domain = @"com.backtrace.exampleApp";
//            NSInteger errorCode = 1001;
//            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: @"Something went wrong." };
//        
//            NSError *error = [NSError errorWithDomain:domain
//                                                 code:errorCode
//                                             userInfo:userInfo];
//        
//            NSLog(@"Error Try: %@", error);
//        
//    } @catch (NSError *error) {
//            NSLog(@"Error @catch: %@", error);
//            [[BacktraceClient shared] sendWithError:error attachmentPaths:paths completion:^(BacktraceResult * _Nonnull result) {
//                NSLog(@"%@", result.message);
//            }];
//        
//    }
    
    
//    @try {
//        [self throwTestException];
//        
//    } @catch (NSException *exception) {
//        NSLog(@"Exception: %@", exception.callStackSymbols);
//        [[BacktraceClient shared] sendWithException:exception attachmentPaths:paths completion:^(BacktraceResult * _Nonnull result) {
//            NSLog(@"%@", result.message);
//        }];
//        
//        
//    }
    
//    [[BacktraceClient shared] sendWithMessage:@"This is a message for Konrad" attachmentPaths:paths completion:^(BacktraceResult * _Nonnull result) {
//        NSLog(@"%@", result.message);
//    }];
    
}

- (NSException *)generateException {
    NSException *exception = [NSException exceptionWithName:@"Generated Exception"
                                                     reason:@"This is a generated exception."
                                                   userInfo:@{@"ExampleKey": @"ExampleValue"}];
    return exception;
}

- (void)throwTestException {
    @throw [NSException exceptionWithName:@"TestException"
                                   reason:@"TestException reason."
                                 userInfo:@{@"key": @"value"}];
}

- (IBAction) crashAction: (id) sender {
    NSArray *array = @[];
    array[1];
}

- (void)simulateCrash {
    // Generate large files to simulate excessive attachments
    //NSArray<NSString *> *attachmentPaths = [self generateInsaneAttachments];
    
    
    NSArray<NSString *> *attachmentPaths = nil;

    @try {
        attachmentPaths = [self generateInsaneAttachments];
    } @catch (NSException *exception) {
        NSLog(@"An exception occurred: %@", exception.reason);
        //attachmentPaths = @[]; // Return an empty array if an exception occurs
        
        // Send the report with the large attachments
        [[BacktraceClient shared] sendWithMessage:exception.name
                                  attachmentPaths:attachmentPaths
                                       completion:^(BacktraceResult * _Nonnull result) {
            NSLog(@"%@", result.message);
        }];
        
    }
    
    


}

- (NSArray<NSString *> *)generateLargeAttachments {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSString *directory = NSTemporaryDirectory();

    for (int i = 0; i < 5; i++) { // Generate 5 large files
        NSString *filePath = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"large_file_%d.dat", i]];
        NSData *largeData = [self generateLargeData:1024 * 1024 * 50]; // 50 MB per file

        NSError *error = nil;
        [largeData writeToFile:filePath options:NSDataWritingAtomic error:&error];
        if (error) {
            NSLog(@"Failed to write file: %@", error.localizedDescription);
        } else {
            [paths addObject:filePath];
            NSLog(@"Generated file: %@", filePath);
        }
    }
    return paths;
}

- (NSArray<NSString *> *)generateInsaneAttachments {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSString *directory = NSTemporaryDirectory();
    
    // Create 20 large files, each ~200 MB
    for (int i = 0; i < 20; i++) {
        NSString *filePath = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"insane_file_%d.dat", i]];
        NSData *largeData = [self generateLargeData:1024 * 1024 * 200]; // 200 MB per file

        NSError *error = nil;
        [largeData writeToFile:filePath options:NSDataWritingAtomic error:&error];
        if (error) {
            NSLog(@"Failed to write file: %@", error.localizedDescription);
        } else {
            [paths addObject:filePath];
            NSLog(@"Generated file: %@", filePath);
        }
    }
    return paths;
}

- (NSData *)generateLargeData:(NSUInteger)size {
    // Fill memory with huge blocks of data
    NSMutableData *data = [NSMutableData dataWithCapacity:size];
    uint8_t buffer[1024];
    memset(buffer, 'B', sizeof(buffer));
    
    for (NSUInteger i = 0; i < size / sizeof(buffer); i++) {
        [data appendBytes:buffer length:sizeof(buffer)];
    }
    return data;
}

//- (NSData *)generateLargeData:(NSUInteger)size {
//    // Create a block of repeating bytes to simulate large data
//    NSMutableData *data = [NSMutableData dataWithCapacity:size];
//    uint8_t buffer[1024]; // 1 KB buffer
//    memset(buffer, 'A', sizeof(buffer));
//
//    for (NSUInteger i = 0; i < size / sizeof(buffer); i++) {
//        [data appendBytes:buffer length:sizeof(buffer)];
//    }
//    return data;
//}

@end

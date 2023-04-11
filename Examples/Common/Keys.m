#import "Keys.h"

@implementation Keys

+ (NSString const *) universeName {
    // Set your universe name here - https://support.backtrace.io/hc/en-us/articles/360040516451-What-is-a-submission-url-
    // e.g.: yourteam
    return @"yourteam";
}

+ (NSString const *) backtraceUrl {
    // Set your submission URL - https://support.backtrace.io/hc/en-us/articles/360040516451-What-is-a-submission-url-
    // e.g.: https://yourteam.backtrace.io
    return [NSString stringWithFormat: @"https://%@.sp.backtrace.io:6098", [Keys universeName]];
}

+ (NSString const *) backtraceToken {
    // Set your submission token - https://support.backtrace.io/hc/en-us/articles/360040105172
    return @"token";
}

+ (NSString const *) backtraceSubmissionUrl {
    // Set your submission URL - https://support.backtrace.io/hc/en-us/articles/360040516451-What-is-a-submission-url-
    // e.g.: https://submit.backtrace.io/{universe}/{token}/plcrash
    return [NSString stringWithFormat: @"https://submit.backtrace.io/%@/%@/plcrash", [Keys universeName], [Keys backtraceToken]];
}

@end

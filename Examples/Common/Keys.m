#import "Keys.h"

@implementation Keys

+ (NSString const *) backtraceUrl {
    // Set your submission URL - https://help.backtrace.io/en/articles/1772855-what-is-a-submission-url
    // e.g.: https://yourteam.backtrace.io
    return @"https://yourteam.backtrace.io";
}

+ (NSString const *) backtraceToken {
    // Set your submission token - https://help.backtrace.io/en/articles/1772818-what-is-a-submission-token
    return @"token";
}

+ (NSString const *) backtraceSubmissionUrl {
    // Set your submission URL - https://help.backtrace.io/en/articles/1772855-what-is-a-submission-url
    // e.g.: https://submit.backtrace.io/{universe}/{token}/plcrash
    return @"https://submit.backtrace.io/{universe}/{token}/plcrash";
}

@end

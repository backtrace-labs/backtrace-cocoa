#import "Keys.h"

@implementation Keys

+ (NSString const *) universeName {
    // Set your universe name here - https://docs.saucelabs.com/error-reporting/project-setup/submission-url
    // e.g.: yourteam
    return @"yourteam";
}

+ (NSString const *) backtraceUrl {
    // Set your submission URL - https://docs.saucelabs.com/error-reporting/project-setup/submission-url/#creating-submission-urls
    // e.g.: https://yourteam.backtrace.io
    return [NSString stringWithFormat: @"https://%@.sp.backtrace.io:6098", [Keys universeName]];
}

+ (NSString const *) backtraceToken {
    // Set your submission token - https://docs.saucelabs.com/error-reporting/project-setup/submission-url/#creating-api-tokens
    return @"token";
}

+ (NSString const *) backtraceSubmissionUrl {
    // Set your submission URL - https://docs.saucelabs.com/error-reporting/project-setup/submission-url/#creating-submission-urls
    // e.g.: https://submit.backtrace.io/{universe}/{token}/plcrash
    return [NSString stringWithFormat: @"https://submit.backtrace.io/%@/%@/plcrash", [Keys universeName], [Keys backtraceToken]];
}

@end

#import "Keys.h"

@implementation Keys

+ (NSString const *) universeName {
    // Set your universe name here - https://support.backtrace.io/hc/en-us/articles/360040516451-What-is-a-submission-url-
    // e.g.: yourteam
    return @"melektest";
}

+ (NSString const *) backtraceUrl {
    // Set your submission URL - https://support.backtrace.io/hc/en-us/articles/360040516451-What-is-a-submission-url-
    // e.g.: https://yourteam.backtrace.io
    return [NSString stringWithFormat: @"https://%@.sp.backtrace.io:6098", [Keys universeName]];
    
    //"https://melektest.sp.backtrace.io:6098/post?format=json&token=66ca29ff4a9ebd9c9dd9a9accb725b0f023d790f27e2460a5f7572390dfef7d0"

}

+ (NSString const *) backtraceToken {
    // Set your submission token - https://support.backtrace.io/hc/en-us/articles/360040105172
    return @"66ca29ff4a9ebd9c9dd9a9accb725b0f023d790f27e2460a5f7572390dfef7d0";
}

+ (NSString const *) backtraceSubmissionUrl {
    // Set your submission URL - https://support.backtrace.io/hc/en-us/articles/360040516451-What-is-a-submission-url-
    // e.g.: https://submit.backtrace.io/{universe}/{token}/plcrash
    return [NSString stringWithFormat: @"https://submit.backtrace.io/%@/%@/plcrash", [Keys universeName], [Keys backtraceToken]];
}

@end

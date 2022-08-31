#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Keys : NSObject

@property(class, nonatomic, assign, readonly) NSString *universeName;

/// [Submission URL](https://support.backtrace.io/hc/en-us/articles/360040516451-What-is-a-submission-url-)
@property(class, nonatomic, assign, readonly) NSString *backtraceUrl;
@property(class, nonatomic, assign, readonly) NSString *backtraceSubmissionUrl;

/// [Submission token](https://support.backtrace.io/hc/en-us/articles/360040105172)
@property(class, nonatomic, assign, readonly) NSString *backtraceToken;

@end

NS_ASSUME_NONNULL_END

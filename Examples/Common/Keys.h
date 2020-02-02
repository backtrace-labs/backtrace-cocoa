#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Keys : NSObject

/// [Submission URL](https://help.backtrace.io/en/articles/1772855-what-is-a-submission-url)
@property(class, nonatomic, assign, readonly) NSString *backtraceUrl;
@property(class, nonatomic, assign, readonly) NSString *backtraceSubmissionUrl;

/// [Submission token](https://help.backtrace.io/en/articles/1772818-what-is-a-submission-token)
@property(class, nonatomic, assign, readonly) NSString *backtraceToken;

@end

NS_ASSUME_NONNULL_END

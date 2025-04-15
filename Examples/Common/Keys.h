#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Keys : NSObject

@property(class, nonatomic, assign, readonly) NSString *universeName;

/// [Submission URL](https://docs.saucelabs.com/error-reporting/project-setup/submission-url/#creating-submission-urls)
@property(class, nonatomic, assign, readonly) NSString *backtraceUrl;
@property(class, nonatomic, assign, readonly) NSString *backtraceSubmissionUrl;

/// [Submission token](https://docs.saucelabs.com/error-reporting/project-setup/submission-url/#creating-api-tokens)
@property(class, nonatomic, assign, readonly) NSString *backtraceToken;

@end

NS_ASSUME_NONNULL_END

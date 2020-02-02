#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Keys : NSObject

@property(class, nonatomic, assign, readonly) NSString const *backtraceUrl;
@property(class, nonatomic, assign, readonly) NSString const *backtraceToken;

@end

NS_ASSUME_NONNULL_END

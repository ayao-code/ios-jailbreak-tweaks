#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSDictionary<NSString *, id> *SDPCollectReport(NSString *component);
NSURL * _Nullable SDPSaveReport(NSDictionary<NSString *, id> *report, NSError **error);

NS_ASSUME_NONNULL_END

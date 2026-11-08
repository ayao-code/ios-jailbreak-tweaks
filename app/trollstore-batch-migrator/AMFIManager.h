#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, DeveloperModePreparationResult) {
    DeveloperModePreparationResultFailed = 0,
    DeveloperModePreparationResultEnabled = 1,
    DeveloperModePreparationResultArmed = 2,
};

@interface AMFIManager : NSObject
+ (DeveloperModePreparationResult)prepareDeveloperModeWithMessage:(NSString **)message;
@end

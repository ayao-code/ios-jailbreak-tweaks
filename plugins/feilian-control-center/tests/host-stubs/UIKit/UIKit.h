#import <Foundation/Foundation.h>
typedef NSUInteger UIBackgroundTaskIdentifier;
static const UIBackgroundTaskIdentifier UIBackgroundTaskInvalid=NSUIntegerMax;
typedef NS_ENUM(NSInteger, UIApplicationState) { UIApplicationStateActive, UIApplicationStateInactive, UIApplicationStateBackground };
@interface UIViewController : NSObject
@property BOOL isViewLoaded;
@property(strong) UIViewController *presentedViewController;
@property(copy) NSArray *childViewControllers;
@end
@interface UIButton : NSObject @end
@interface UIWindow : NSObject
@property(strong) UIViewController *rootViewController;
@end
@interface UIScene : NSObject @end
@interface UIWindowScene : UIScene
@property(copy) NSArray *windows;
@end
@interface UIApplication : NSObject
+ (instancetype)sharedApplication;
@property BOOL protectedDataAvailable;
@property UIApplicationState applicationState;
@property(copy) NSSet *connectedScenes;
- (UIBackgroundTaskIdentifier)beginBackgroundTaskWithName:(NSString *)name expirationHandler:(void (^)(void))handler;
- (void)endBackgroundTask:(UIBackgroundTaskIdentifier)task;
@end
FOUNDATION_EXPORT NSString *const UIApplicationDidBecomeActiveNotification;

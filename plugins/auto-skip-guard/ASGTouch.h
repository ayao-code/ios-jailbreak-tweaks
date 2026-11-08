#import <UIKit/UIKit.h>

// App-local fallback. No global device events, no eager touch pool.
BOOL ASGPerformLocalTap(UIView *target, UIWindow *window, void (^completion)(BOOL));
BOOL ASGPerformLocalTapAtPoint(UIView *target, UIWindow *window, CGPoint point, void (^completion)(BOOL));
BOOL ASGIsSyntheticTouch(UITouch *touch);
BOOL ASGPerformGuardedTap(UIView *target, UIWindow *window, CGPoint point,
                         BOOL (^stillValid)(void), void (^completion)(BOOL));

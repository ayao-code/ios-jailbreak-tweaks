// One-shot native UI unlock, only when the system reports no passcode protection.
// Not part of the VPN package. Never disables, guesses or bypasses a passcode.
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <objc/runtime.h>

@interface NSObject (VPNUnlockUIOnce)
+ (instancetype)sharedInstance;
- (void)lockScreenViewControllerRequestsUnlock;
- (BOOL)isUILocked;
+ (instancetype)sharedController;
- (BOOL)isPasscodeSet;
@end
static void Log(NSString *text) {
    [text writeToFile:@"/var/mobile/Library/Caches/ayao.vpn-native-ui-unlock.log"
        atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
__attribute__((constructor)) static void Initialize(void) {
    if(![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"])return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        Class cls=NSClassFromString(@"SBLockScreenManager");
        id manager=[cls respondsToSelector:@selector(sharedInstance)]?[cls sharedInstance]:nil;
        // Caller verified PasswordProtected=false via the paired device service.
        // Use the normal UI method; never call passcode authentication or alter it.
        if(![manager respondsToSelector:@selector(isUILocked)]) {
            Log(@"NATIVE_STATE_UNAVAILABLE=1\n");return;
        }
        if(![manager isUILocked]){Log(@"ALREADY_UNLOCKED=1\n");return;}
        Class backlightClass=NSClassFromString(@"SBBacklightController");
        id backlight=[backlightClass respondsToSelector:@selector(sharedInstance)]?[backlightClass sharedInstance]:nil;
        SEL wake=NSSelectorFromString(@"turnOnScreenFullyWithBacklightSource:");
        NSMethodSignature *wakeSignature=[backlight methodSignatureForSelector:wake];
        if(wakeSignature.numberOfArguments==3 && !strcmp(wakeSignature.methodReturnType,"v") &&
            !strcmp([wakeSignature getArgumentTypeAtIndex:2],"q"))
            ((void(*)(id,SEL,long long))[backlight methodForSelector:wake])(backlight,wake,0);
        NSMethodSignature *signature=[manager methodSignatureForSelector:@selector(lockScreenViewControllerRequestsUnlock)];
        if(!signature || signature.numberOfArguments!=2 || strcmp(signature.methodReturnType,"v")) {
            NSMutableString *text=[NSMutableString stringWithString:@"NATIVE_UI_API_UNAVAILABLE=1\n"];
            for(Class current=[manager class];current && current!=NSObject.class;current=class_getSuperclass(current)) {
                unsigned count=0;Method *methods=class_copyMethodList(current,&count);
                for(unsigned i=0;i<count;i++) {
                    NSString *name=NSStringFromSelector(method_getName(methods[i]));
                    if([name.lowercaseString containsString:@"unlock"] && ![name.lowercaseString containsString:@"passcode"])
                        [text appendFormat:@"%@ %s\n",name,method_getTypeEncoding(methods[i])];
                }free(methods);
            }Log(text);return;
        }
        [manager lockScreenViewControllerRequestsUnlock];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
            if([manager isUILocked])[manager lockScreenViewControllerRequestsUnlock];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            Log([NSString stringWithFormat:@"NATIVE_UI_UNLOCK_REQUESTED=1\nREADBACK=%d\nLOCKED=%d\n",
                YES,[manager isUILocked]]);
        });
    });
}

#import "CameraShortcut.h"
#import "CameraDiagnostics.h"
#import "Shared/AYCameraPolicy.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <string.h>
#import <roothide.h>
#include <dlfcn.h>

static BOOL AYCameraWakePending, AYCameraDisplayHookReady;
static unsigned long AYCameraPreferenceGeneration;
static unsigned long AYCameraWakeGeneration;
static __weak id AYCameraPendingCover;
static dispatch_source_t AYCameraWakeTimeout;
BOOL AYCameraHasPendingWake(void) {return NSThread.isMainThread && AYCameraWakePending;}
void AYCameraCancelPendingWake(void) {
    if(!NSThread.isMainThread)return;
    AYCameraWakeGeneration++;
    AYCameraWakePending=NO;AYCameraPendingCover=nil;
    if(AYCameraWakeTimeout) {dispatch_source_cancel(AYCameraWakeTimeout);AYCameraWakeTimeout=nil;}
}

static BOOL AYCameraEnabled, AYCameraLockedAllowed;
static unsigned AYCameraTrigger;
static double AYCameraLastAccepted;
static __weak id AYCameraLockManager;
static NSDictionary *AYCameraPreferenceSnapshot;
static id AYCameraPreference(NSString *key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("ayao.aipowerbutton")));
}
void AYCameraReloadPreferences(void) {
    AYCameraCancelPendingWake();AYCameraPreferenceGeneration++;
    CFPreferencesAppSynchronize(CFSTR("ayao.aipowerbutton"));
    // RootHide's SpringBoard CFPreferences view can miss the Preferences-written
    // jbroot file after respring. Read one immutable snapshot on reload only.
    NSDictionary *snapshot = [NSDictionary dictionaryWithContentsOfFile:jbroot(@"/var/mobile/Library/Preferences/ayao.aipowerbutton.plist")];
    AYCameraPreferenceSnapshot = snapshot;
    id enabled = snapshot ? snapshot[@"cameraDoublePressEnabled"] : AYCameraPreference(@"cameraDoublePressEnabled");
    id locked = snapshot ? snapshot[@"cameraOnLockScreen"] : AYCameraPreference(@"cameraOnLockScreen");
    id trigger = snapshot ? snapshot[@"cameraTrigger"] : AYCameraPreference(@"cameraTrigger");
    AYCameraEnabled = [enabled isKindOfClass:NSNumber.class] && [enabled boolValue];
    AYCameraLockedAllowed = [locked isKindOfClass:NSNumber.class] && [locked boolValue];
    // A legacy Home selection now selects its replacement; no disk rewrite.
    AYCameraTrigger = !trigger || [trigger isEqual:@"side"] ? 0 :
        ([trigger isEqual:@"volumeDown"] || [trigger isEqual:@"home"] ? 1 : 2);
    // A new preference generation must not inherit an old gesture's debounce.
    AYCameraLastAccepted = 0;
    AYCameraDiagnostic(@"preferences", @{@"enabled": @(AYCameraEnabled), @"lockedAllowed": @(AYCameraLockedAllowed), @"trigger": @(AYCameraTrigger)});
}
BOOL AYCameraVolumeDownEnabled(void) {return AYCameraEnabled && AYCameraTrigger==1;}
id AYCameraPreferenceSnapshotValue(NSString *key) {
    return AYCameraPreferenceSnapshot ? AYCameraPreferenceSnapshot[key] : AYCameraPreference(key);
}
void AYCameraRememberLockManager(id manager) { AYCameraLockManager = manager; }
static BOOL AYCameraMethod(id object, SEL selector, unsigned arguments) {
    if (!object || ![object respondsToSelector:selector]) return NO;
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    return signature && signature.numberOfArguments == arguments;
}
static BOOL AYCameraReadBool(id object, SEL selector, BOOL *value) {
    if(!AYCameraMethod(object,selector,2))return NO;
    const char *type=[object methodSignatureForSelector:selector].methodReturnType;
    if(strcmp(type,"B") && strcmp(type,"c"))return NO;
    *value=((BOOL (*)(id,SEL))objc_msgSend)(object,selector);return YES;
}
static BOOL AYCameraReadDisplayOn(BOOL *on) {
    Class cls=NSClassFromString(@"SBBacklightController");
    SEL existing=NSSelectorFromString(@"sharedInstanceIfExists");
    if(!AYCameraMethod(cls,existing,2) || [cls methodSignatureForSelector:existing].methodReturnType[0]!='@')return NO;
    id controller=((id (*)(id,SEL))objc_msgSend)(cls,existing);
    return AYCameraReadBool(controller,NSSelectorFromString(@"screenIsOn"),on);
}
void AYCameraDisplayDidAppear(id cover) {
    if(!NSThread.isMainThread || !AYCameraWakePending || cover!=AYCameraPendingCover)return;
    // Wait for an actual screen-on observation; a void wake call is not proof.
    BOOL on=NO;
    @try {
        if(!AYCameraReadDisplayOn(&on) || !on)return;
        unsigned long generation=AYCameraPreferenceGeneration;
        AYCameraCancelPendingWake();
        unsigned long wakeGeneration=AYCameraWakeGeneration;
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                BOOL locked=NO,currentOn=NO;
                BOOL displayKnown=AYCameraReadDisplayOn(&currentOn);
                BOOL lockKnown=AYCameraReadBool(AYCameraLockManager,NSSelectorFromString(@"isUILocked"),&locked);
                if(!AYCameraWakeMayActivate(wakeGeneration==AYCameraWakeGeneration,
                    generation==AYCameraPreferenceGeneration,AYCameraPendingVolumeAllowed(),
                    displayKnown,currentOn,lockKnown,locked)) {
                    AYCameraDiagnostic(@"wake_cancelled_state_changed",@{});return;
                }
                AYCameraDiagnostic(@"wake_display_ready",@{});
                AYCameraHandleDoublePress(1,NO,NO);
            } @catch(NSException *exception) {AYCameraDiagnostic(@"wake_resume_exception",@{});}
        });
    } @catch(NSException *exception) {AYCameraCancelPendingWake();}
}
// Called only after runtime ABI checks in the tweak constructor.
void AYCameraSetDisplayHooksReady(BOOL ready) {AYCameraDisplayHookReady=ready;}
BOOL AYCameraShouldWaitForDoublePress(BOOL protectedAction, BOOL recording) {
    if (!NSThread.isMainThread || !AYCameraEnabled || AYCameraTrigger != 0 || protectedAction || recording) return NO;
    @try {
        id manager = AYCameraLockManager;
        Class cls = NSClassFromString(@"SBLockScreenManager");
        SEL existing = NSSelectorFromString(@"sharedInstanceIfExists");
        if (!manager && AYCameraMethod(cls, existing, 2)
            && [cls methodSignatureForSelector:existing].methodReturnType[0] == '@')
            manager = ((id (*)(id, SEL))objc_msgSend)(cls, existing);
        SEL selector = NSSelectorFromString(@"isUILocked");
        if (!AYCameraMethod(manager, selector, 2)) return NO;
        const char *type = [manager methodSignatureForSelector:selector].methodReturnType;
        if (strcmp(type, "B") && strcmp(type, "c")) return NO;
        BOOL locked = ((BOOL (*)(id, SEL))objc_msgSend)(manager, selector);
        return !locked || AYCameraLockedAllowed;
    } @catch (NSException *exception) { return NO; }
}
BOOL AYCameraHandleDoublePress(unsigned trigger, BOOL protectedAction, BOOL recording) {
    AYCameraDiagnostic(@"double_received", @{@"trigger": @(trigger), @"mainThread": @(NSThread.isMainThread), @"enabled": @(AYCameraEnabled)});
    if (!NSThread.isMainThread || !AYCameraEnabled || trigger != AYCameraTrigger) return NO;
    @try {
        id manager = AYCameraLockManager;
        // Never initialize SBLockScreenManager at plugin load; avoid dispatch_once reentrancy.
        Class cls = NSClassFromString(@"SBLockScreenManager");
        SEL existing = NSSelectorFromString(@"sharedInstanceIfExists");
        if (!manager && AYCameraMethod(cls, existing, 2) && [cls methodSignatureForSelector:existing].methodReturnType[0] == '@') manager = ((id (*)(id, SEL))objc_msgSend)(cls, existing);
        if(manager)AYCameraLockManager=manager;
        SEL lockSelector = NSSelectorFromString(@"isUILocked");
        BOOL known = AYCameraMethod(manager, lockSelector, 2);
        if (known) { const char *type = [manager methodSignatureForSelector:lockSelector].methodReturnType; known = !strcmp(type, "B") || !strcmp(type, "c"); }
        BOOL locked = known ? ((BOOL (*)(id, SEL))objc_msgSend)(manager, lockSelector) : YES;
        double now = NSProcessInfo.processInfo.systemUptime;
        AYCameraDecision decision = AYCameraDecide(AYCameraEnabled, AYCameraTrigger, trigger,
            known, locked, AYCameraLockedAllowed, protectedAction, recording, now, AYCameraLastAccepted);
        AYCameraDiagnostic(@"decision", @{@"lockKnown": @(known), @"locked": @(locked), @"protected": @(protectedAction), @"recording": @(recording), @"decision": @(decision), @"manager": manager ? NSStringFromClass([manager class]) : @"absent"});
        if (decision == AYCameraPassThrough) return NO;
        // Repeat is consumed, not dispatched twice or forwarded to Wallet/app switcher.
        if (decision == AYCameraConsumeRepeat) return YES;
        if (locked) {
            SEL coverSelector = NSSelectorFromString(@"coverSheetViewController");
            id cover = AYCameraMethod(manager, coverSelector, 2)
                && [manager methodSignatureForSelector:coverSelector].methodReturnType[0] == '@'
                ? ((id (*)(id, SEL))objc_msgSend)(manager, coverSelector) : nil;
            SEL activate = NSSelectorFromString(@"activateCameraViewAnimated:sendingActions:completion:");
            if (!AYCameraMethod(cover, activate, 5)) { AYCameraDiagnostic(@"locked_camera_unavailable", @{}); return NO; }
            NSMethodSignature *signature = [cover methodSignatureForSelector:activate];
            const char *type = [signature getArgumentTypeAtIndex:2];
            if ((strcmp(type, @encode(BOOL)) && strcmp(type, "B") && strcmp(type, "c"))
                || strcmp(signature.methodReturnType, "v")
                || [signature getArgumentTypeAtIndex:3][0] != '@' || [signature getArgumentTypeAtIndex:4][0] != '@') return NO;
            if(trigger==1) {
                BOOL screenOn=NO;
                BOOL displayKnown=AYCameraReadDisplayOn(&screenOn);
                AYCameraDiagnostic(@"locked_display_state",@{@"known":@(displayKnown),@"on":@(screenOn)});
                if(!displayKnown)return NO;
                if(displayKnown && !screenOn) {
                    if(AYCameraWakePending)return YES;
                    void (*undim)(void)=dlsym(RTLD_DEFAULT,"SBSUndimScreen");
                    if(!undim || !AYCameraDisplayHookReady) {AYCameraDiagnostic(@"wake_unavailable",@{});return NO;}
                    AYCameraWakeGeneration++;
                    AYCameraWakePending=YES;AYCameraPendingCover=cover;
                    unsigned long requestGeneration=AYCameraWakeGeneration;
                    AYCameraWakeTimeout=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
                    if(!AYCameraWakeTimeout) {AYCameraCancelPendingWake();return NO;}
                    dispatch_source_set_timer(AYCameraWakeTimeout,dispatch_time(DISPATCH_TIME_NOW,1500*NSEC_PER_MSEC),DISPATCH_TIME_FOREVER,50*NSEC_PER_MSEC);
                    dispatch_source_set_event_handler(AYCameraWakeTimeout, ^{
                        if(AYCameraWakePending && requestGeneration==AYCameraWakeGeneration) {
                            AYCameraDiagnostic(@"wake_timeout",@{});AYCameraCancelPendingWake();
                        }
                    });
                    dispatch_resume(AYCameraWakeTimeout);
                    undim(); // Display-only request. Never request authentication/unlock.
                    AYCameraDiagnostic(@"wake_requested",@{});
                    return YES;
                }
            }
            // Native locked-camera page owns privacy/authentication. Never call unlock APIs.
            ((void (*)(id, SEL, BOOL, id, id))objc_msgSend)(cover, activate, YES, nil, nil);
        } else {
            Class serviceClass = NSClassFromString(@"FBSSystemService");
            SEL shared = NSSelectorFromString(@"sharedService");
            id service = AYCameraMethod(serviceClass, shared, 2)
                && [serviceClass methodSignatureForSelector:shared].methodReturnType[0] == '@'
                ? ((id (*)(id, SEL))objc_msgSend)(serviceClass, shared) : nil;
            SEL open = NSSelectorFromString(@"openApplication:options:withResult:");
            if (!AYCameraMethod(service, open, 5)) { AYCameraDiagnostic(@"camera_service_unavailable", @{}); return NO; }
            NSMethodSignature *signature = [service methodSignatureForSelector:open];
            if (strcmp(signature.methodReturnType, "v") || [signature getArgumentTypeAtIndex:2][0] != '@'
                || [signature getArgumentTypeAtIndex:3][0] != '@' || [signature getArgumentTypeAtIndex:4][0] != '@') return NO;
            ((void (*)(id, SEL, id, id, id))objc_msgSend)(service, open, @"com.apple.camera", @{}, nil);
        }
        AYCameraLastAccepted = now;
        AYCameraDiagnostic(@"camera_dispatched", @{@"locked": @(locked)});
        return YES; // Request dispatched, not a claim that camera reached foreground.
    } @catch (NSException *exception) { return NO; }
}

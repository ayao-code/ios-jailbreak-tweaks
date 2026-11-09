#import "CameraDiagnostics.h"
#if AYCAMERA_DIAGNOSTICS
#import <objc/runtime.h>
#import <roothide.h>
#include <stdio.h>

void AYCameraDiagnostic(NSString *event, NSDictionary *details) {
    // Finite test-only evidence: no polling, bounded events and 32 KiB on disk.
    static unsigned count;
#if AYVOLUME_DIAGNOSTICS
    const unsigned limit = 64;
    NSString *path = jbroot(@"/var/mobile/Documents/aipb-volume-test10.jsonl");
#else
    const unsigned limit = 48;
    NSString *path = jbroot(@"/var/mobile/Documents/aipb-camera-test4.jsonl");
#endif
    if (!NSThread.isMainThread || count >= limit) return;
    FILE *file = fopen(path.fileSystemRepresentation, "a");
    if (!file) return;
    if (fseek(file, 0, SEEK_END) || ftell(file) > 30 * 1024) { fclose(file); count = limit; return; }
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"event": event, @"details": details ?: @{},
        @"uptime": @(NSProcessInfo.processInfo.systemUptime)} options:0 error:NULL];
    if (json.length < 2048) { fwrite(json.bytes, 1, json.length, file); fputc('\n', file); count++; }
    fclose(file);
}
void AYCameraAuditRuntime(void) {
    for (NSString *name in @[@"SBLockHardwareButtonActions", @"SBLockScreenManager", @"CSCoverSheetViewController", @"FBSSystemService", @"SBVolumeHardwareButtonActions", @"SBBacklightController"]) {
        Class cls = NSClassFromString(name);
        NSMutableDictionary *methods = [NSMutableDictionary dictionary];
        for (NSString *methodName in @[@"performDoublePressActions", @"performInitialButtonDownActions",
              @"performSecondButtonDownActions", @"_shouldWaitForDoublePress", @"isUILocked", @"_reallySetUILocked:",
              @"coverSheetViewController", @"activateCameraViewAnimated:sendingActions:completion:", @"sharedInstanceIfExists",
              @"sharedService", @"openApplication:options:withResult:",
              @"isButtonDown", @"performInitialButtonUpActions", @"performFinalButtonUpActions",
              @"screenIsOn", @"_displayWillAppearImplementation", @"viewDidAppear:",
              @"setBacklightLevel:",
              @"volumeDecreasePressDownWithModifiers:", @"volumeDecreasePressUp",
              @"volumeIncreasePressDownWithModifiers:", @"volumeIncreasePressUp", @"cancelVolumePress",
              @"_handleVolumeButtonDownForIncrease:modifiers:", @"_handleVolumeButtonUpForIncrease:"]) {
            SEL selector = NSSelectorFromString(methodName);
            Method method = class_getInstanceMethod(cls, selector) ?: class_getClassMethod(cls, selector);
            if (method) methods[methodName] = @(method_getTypeEncoding(method));
        }
        AYCameraDiagnostic(@"runtime", @{@"class": name, @"present": @(cls != Nil), @"methods": methods});
    }
}
#endif

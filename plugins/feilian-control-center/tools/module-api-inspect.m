// Read-only runtime contract discovery. Never loads the candidate module.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

@interface NSObject (VPNStoreReadback)
+ (id)sharedInstance;
- (id)configurations;
- (unsigned int)vpnServiceCountDirty;
- (id)vpnServicesForCurrentSetWithGrade:(NSUInteger)grade;
@end

int main(void) {
    @autoreleasepool {
        dlopen("/System/Library/PrivateFrameworks/ControlCenterUIKit.framework/ControlCenterUIKit", RTLD_NOW);
        for (NSString *name in @[@"CCUIMenuModuleViewController", @"CCUIButtonModuleViewController", @"CCUIToggleViewController"]) {
            Class cls = NSClassFromString(name);
            printf("CLASS %s available=%d\n", name.UTF8String, cls != nil);
            unsigned int count = 0; Method *methods = class_copyMethodList(cls, &count);
            for (unsigned int index = 0; index < count; index++)
                printf("METHOD %s %s\n", sel_getName(method_getName(methods[index])), method_getTypeEncoding(methods[index]));
            free(methods);
        }
        if (![[NSBundle bundleWithPath:@"/System/Library/PreferenceBundles/VPNPreferences.bundle"] load]) return 2;
        id store = [NSClassFromString(@"VPNConnectionStore") sharedInstance];
        for (NSUInteger grade = 0; grade < 4; grade++) [store vpnServicesForCurrentSetWithGrade:grade];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:3]];
        printf("STORE configurations_method=%d dirty_method=%d configurations_present=%d dirty=%u\n",
            [store respondsToSelector:@selector(configurations)], [store respondsToSelector:@selector(vpnServiceCountDirty)],
            [store respondsToSelector:@selector(configurations)] && [store configurations] != nil,
            [store respondsToSelector:@selector(vpnServiceCountDirty)] ? [store vpnServiceCountDirty] : UINT_MAX);
    }
}

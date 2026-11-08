#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <sys/sysctl.h>

@interface NSObject (StoreInstallReadback)
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
- (NSString *)bundleIdentifier;
- (NSString *)shortVersionString;
- (NSString *)bundleVersion;
- (NSURL *)bundleURL;
- (BOOL)isInstalled;
- (BOOL)isPlaceholder;
- (NSProgress *)installProgress;
@end

// LaunchServices metadata only. No application launch, data-container access,
// account information, credentials, state modification, or background polling.
int main(int argc, const char **argv) {
    @autoreleasepool {
        char machine[128] = {0}; size_t size = sizeof(machine);
        if (argc < 2 || sysctlbyname("hw.machine", machine, &size, NULL, 0) ||
            strcmp(machine, "iPhone15,3")) return 2;
        if (!dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_NOW)) return 3;
        Class cls = NSClassFromString(@"LSApplicationProxy");
        if (![cls respondsToSelector:@selector(applicationProxyForIdentifier:)]) return 3;
        NSMutableArray *rows = [NSMutableArray array];
        for (int i = 1; i < argc; i++) {
            NSString *identifier = @(argv[i]);
            id proxy = [cls applicationProxyForIdentifier:identifier];
            NSMutableDictionary *row = [@{@"bundle_id": identifier, @"proxy_present": @(proxy != nil)} mutableCopy];
            for (NSString *name in @[@"isInstalled", @"isPlaceholder"]) {
                SEL selector = NSSelectorFromString(name);
                if ([proxy respondsToSelector:selector]) {
                    BOOL value = ((BOOL (*)(id, SEL))objc_msgSend)(proxy, selector);
                    row[name] = @(value);
                }
            }
            if ([proxy respondsToSelector:@selector(shortVersionString)]) row[@"version"] = [proxy shortVersionString] ?: @"";
            if ([proxy respondsToSelector:@selector(bundleVersion)]) row[@"build"] = [proxy bundleVersion] ?: @"";
            if ([proxy respondsToSelector:@selector(installProgress)]) {
                NSProgress *progress = [proxy installProgress];
                if ([progress isKindOfClass:NSProgress.class]) {
                    row[@"fraction_completed"] = @(progress.fractionCompleted);
                    row[@"progress_cancelled"] = @(progress.cancelled);
                    row[@"progress_paused"] = @(progress.paused);
                }
            }
            [rows addObject:row];
        }
        NSData *output = [NSJSONSerialization dataWithJSONObject:rows options:NSJSONWritingSortedKeys error:nil];
        return output && fwrite(output.bytes, 1, output.length, stdout) == output.length ? 0 : 1;
    }
}

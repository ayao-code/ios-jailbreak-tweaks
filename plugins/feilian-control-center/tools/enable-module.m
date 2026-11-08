#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

@interface NSObject (CCSettings)
+ (instancetype)sharedProvider;
+ (NSURL *)_configurationFileURL;
- (NSArray *)orderedUserEnabledModuleIdentifiers;
- (void)setAndSaveOrderedUserEnabledModuleIdentifiers:(NSArray *)identifiers;
@end

static NSString *ConfigurationPath;
static NSURL *ConfigurationURL(id self, SEL command) {
    return [NSURL fileURLWithPath:ConfigurationPath];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3 || strcmp(argv[1], "--add-feilian") != 0) return 2;
        NSString *path = @(argv[2]);
        if (![path hasSuffix:@"/Library/ControlCenter/ModuleConfiguration_CCSupport.plist"]) return 2;
        ConfigurationPath = path;
        NSDictionary *before = [NSDictionary dictionaryWithContentsOfFile:path];
        NSArray *old = before[@"module-identifiers"];
        if (![old isKindOfClass:NSArray.class]) return 3;
        NSString *backup = [path stringByAppendingFormat:@".feilian-backup-%.0f", NSDate.date.timeIntervalSince1970];
        if (![NSFileManager.defaultManager copyItemAtPath:path toPath:backup error:nil]) return 8;
        if (!dlopen("/System/Library/PrivateFrameworks/ControlCenterServices.framework/ControlCenterServices", RTLD_NOW)) return 4;
        Class cls = NSClassFromString(@"CCSModuleSettingsProvider");
        Method method = class_getClassMethod(cls, @selector(_configurationFileURL));
        if (!method || ![cls respondsToSelector:@selector(sharedProvider)]) return 5;
        // Process-local API adapter: CCSupport uses the same API with this URL.
        // No injection, target-process hooking, or raw configuration file write.
        IMP original = method_setImplementation(method, (IMP)ConfigurationURL);
        id provider = [cls sharedProvider];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        NSArray *loaded = [provider orderedUserEnabledModuleIdentifiers];
        if (![loaded isEqual:old]) { method_setImplementation(method, original); return 6; }
        NSMutableArray *desired = [old mutableCopy];
        NSString *identifier = @"ayao.feiliancontrolcenter.module";
        if (![desired containsObject:identifier]) [desired addObject:identifier];
        [provider setAndSaveOrderedUserEnabledModuleIdentifiers:desired];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        NSDictionary *after = [NSDictionary dictionaryWithContentsOfFile:path];
        NSMutableDictionary *expected = [before mutableCopy];
        expected[@"module-identifiers"] = desired;
        BOOL exact = [after isEqual:expected];
        method_setImplementation(method, original);
        printf("official_api_write_exact=%d old_count=%lu new_count=%lu\n", exact, (unsigned long)old.count, (unsigned long)desired.count);
        return exact ? 0 : 7;
    }
}

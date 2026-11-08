#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

static NSString *configurationPath;

static NSURL *configurationURL(id self, SEL selector) {
    (void)self;
    (void)selector;
    return [NSURL fileURLWithPath:configurationPath];
}

static NSURL *directoryURL(id self, SEL selector) {
    (void)self;
    (void)selector;
    return [NSURL fileURLWithPath:configurationPath.stringByDeletingLastPathComponent];
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc < 3) return 2;
        configurationPath = @(argv[2]);
        if (![configurationPath hasPrefix:@"/private/var/mobile/Containers/Shared/AppGroup/.jbroot-"] ||
            ![configurationPath hasSuffix:@"/var/mobile/Library/ControlCenter/ModuleConfiguration_CCSupport.plist"] ||
            [configurationPath containsString:@".."] || getuid() != 501) return 2;
        void *framework = dlopen("/System/Library/PrivateFrameworks/ControlCenterServices.framework/ControlCenterServices", RTLD_NOW);
        if (!framework) { fprintf(stderr, "framework_unavailable\n"); return 3; }
        Class base = NSClassFromString(@"CCSModuleSettingsProvider");
        SEL read = NSSelectorFromString(@"_readSettingsWithVersion:");
        SEL write = NSSelectorFromString(@"_writeOrderedIdentifiers:userEnabledFixedIdentifiers:userDisabledIdentifiers:");
        if (!strcmp(argv[1], "inspect") && argc == 3) {
            if (!base) return 4;
            for (int meta = 0; meta < 2; meta++) {
                unsigned int count = 0;
                Method *methods = class_copyMethodList(meta ? object_getClass(base) : base, &count);
                for (unsigned int i = 0; i < count; i++)
                    printf("%s %s %s\n", meta ? "+" : "-",
                        sel_getName(method_getName(methods[i])), method_getTypeEncoding(methods[i]));
                free(methods);
            }
            return 0;
        }
        BOOL versionedReader = base && [base respondsToSelector:read];
        if (!versionedReader) read = NSSelectorFromString(@"_readSettings");
        if (!base || ![base respondsToSelector:read] || ![base respondsToSelector:write]) {
            fprintf(stderr, "native_configuration_api_unavailable\n"); return 4;
        }
        // Isolate the official serializer to the installed CCSupport file.
        // No system class is hooked: only this process-local subclass has the
        // two file URL overrides used by the native reader/writer.
        Class local = objc_allocateClassPair(base, "MigrationCCSettingsProvider", 0);
        if (!local) return 4;
        Class meta = object_getClass(local);
        class_addMethod(meta, NSSelectorFromString(@"_configurationFileURL"), (IMP)configurationURL, "@@:");
        class_addMethod(meta, NSSelectorFromString(@"_configurationDirectoryURL"), (IMP)directoryURL, "@@:");
        objc_registerClassPair(local);
        if (!strcmp(argv[1], "apply") && argc == 4) {
            NSDictionary *desired = [NSDictionary dictionaryWithContentsOfFile:@(argv[3])];
            NSArray *ordered = desired[@"module-identifiers"];
            NSArray *fixed = desired[@"userenabled-fixed-module-identifiers"];
            NSArray *disabled = desired[@"disabled-module-identifiers"];
            for (id list in @[ordered ?: @0, fixed ?: @0, disabled ?: @0]) {
                if (![list isKindOfClass:NSArray.class]) return 2;
                for (id value in list) if (![value isKindOfClass:NSString.class]) return 2;
            }
            ((void (*)(id, SEL, id, id, id))objc_msgSend)(local, write, ordered, fixed, disabled);
        } else if (strcmp(argv[1], "read") || argc != 3) return 2;
        unsigned long long version = 0;
        id settings = versionedReader ?
            ((id (*)(id, SEL, unsigned long long *))objc_msgSend)(local, read, &version) :
            ((id (*)(id, SEL))objc_msgSend)(local, read);
        if (!settings) return 5;
        NSDictionary *result = @{@"native_version": @(version), @"native_settings": settings};
        NSError *error;
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:result
            format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
        if (!data) { fprintf(stderr, "native_settings_not_serializable\n"); return 5; }
        return fwrite(data.bytes, 1, data.length, stdout) == data.length ? 0 : 1;
    }
}

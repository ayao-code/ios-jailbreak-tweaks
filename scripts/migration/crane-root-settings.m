#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <dlfcn.h>

// Use Crane's own settings API for two global UI options only. Container,
// account, Keychain and application configuration are intentionally excluded.
int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc < 2 || argc > 3 || getuid() != 501) return 2;
        NSString *home = NSHomeDirectory();
        if (![home hasPrefix:@"/var/containers/Bundle/Application/.jbroot-"] ||
            ![home hasSuffix:@"/var/mobile"]) return 3;
        NSString *root = [home substringToIndex:home.length - @"/var/mobile".length];
        NSString *library = [root stringByAppendingPathComponent:@"usr/lib/libcrane.dylib"];
        if (!dlopen(library.fileSystemRepresentation, RTLD_NOW)) {
            fprintf(stderr, "native_library_unavailable: %s\n", dlerror()); return 3;
        }
        Class cls = NSClassFromString(@"CraneManager");
        SEL shared = NSSelectorFromString(@"sharedManager");
        SEL read = NSSelectorFromString(@"preferencesCopy");
        SEL write = NSSelectorFromString(@"setPreferenceValue:forKey:");
        if (!cls || ![cls respondsToSelector:shared]) return 3;
        id manager = ((id (*)(id, SEL))objc_msgSend)(cls, shared);
        if (![manager respondsToSelector:read] || ![manager respondsToSelector:write]) return 3;
        NSArray *allowed = @[@"expandContainersShortcutEnabled",
                              @"launchApplicationOnContainerSelectionEnabled"];
        if (!strcmp(argv[1], "apply") && argc == 3) {
            NSDictionary *patch = [NSDictionary dictionaryWithContentsOfFile:@(argv[2])];
            if (![patch isKindOfClass:NSDictionary.class]) return 2;
            for (NSString *key in patch)
                if (![allowed containsObject:key] ||
                    CFGetTypeID((__bridge CFTypeRef)patch[key]) != CFBooleanGetTypeID()) return 2;
            for (NSString *key in patch)
                ((void (*)(id, SEL, id, id))objc_msgSend)(manager, write, patch[key], key);
        } else if (strcmp(argv[1], "read") || argc != 2) return 2;
        NSDictionary *all = ((id (*)(id, SEL))objc_msgSend)(manager, read);
        if (![all isKindOfClass:NSDictionary.class]) return 4;
        NSMutableDictionary *selected = [NSMutableDictionary dictionary];
        for (NSString *key in allowed) if (all[key]) selected[key] = all[key];
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:selected
            format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        return data && fwrite(data.bytes, 1, data.length, stdout) == data.length ? 0 : 1;
    }
}

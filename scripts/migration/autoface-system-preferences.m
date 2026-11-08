#import <Foundation/Foundation.h>

@interface NSUserDefaults (ScopedSystemPreferences)
- (instancetype)_initWithSuiteName:(NSString *)suiteName container:(NSURL *)container;
@end

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (getuid() != 501 || argc < 2 || argc > 3) return 2;
        if (![NSUserDefaults instancesRespondToSelector:@selector(_initWithSuiteName:container:)])
            return 3;
        NSString *domain = @"com.netskao.autofaceunlock";
        NSArray *allowed = @[@"EnabledUnlock", @"CheckMediaing", @"CheckNotice",
            @"CheckFlashlight", @"EnabledAutoRetryFace", @"EnabledDelayUnlock",
            @"DelayUnlockValue"];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] _initWithSuiteName:domain
            container:[NSURL fileURLWithPath:@"/var/mobile" isDirectory:YES]];
        if (!defaults) return 3;
        if (!strcmp(argv[1], "apply") && argc == 3) {
            NSDictionary *values = [NSDictionary dictionaryWithContentsOfFile:@(argv[2])];
            if (![values isKindOfClass:NSDictionary.class]) return 2;
            for (NSString *key in values)
                if (![allowed containsObject:key] ||
                    CFGetTypeID((__bridge CFTypeRef)values[key]) != CFBooleanGetTypeID()) return 2;
            for (NSString *key in values) [defaults setObject:values[key] forKey:key];
            if (![defaults synchronize]) return 1;
        } else if (strcmp(argv[1], "read") || argc != 2) return 2;
        NSMutableDictionary *selected = [NSMutableDictionary dictionary];
        NSDictionary *all = [defaults dictionaryRepresentation];
        for (NSString *key in allowed) if (all[key]) selected[key] = all[key];
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:selected
            format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        return data && fwrite(data.bytes, 1, data.length, stdout) == data.length ? 0 : 1;
    }
}

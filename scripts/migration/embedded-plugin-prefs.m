#import <Foundation/Foundation.h>
#import <sys/sysctl.h>
#import "embedded-plugin-keys.h"

@interface NSUserDefaults (ScopedContainerPreferences)
- (instancetype)_initWithSuiteName:(NSString *)suiteName container:(NSURL *)container;
@end

// Exact reviewed plugin keys only; no account/license suites, process hooks,
// launches, notification broadcasts, or global preferences operations.
int main(int argc, const char **argv) {
    @autoreleasepool {
        char machine[128]={0};size_t length=sizeof(machine);
        if (argc<4 || sysctlbyname("hw.machine",machine,&length,NULL,0) || strcmp(machine,"iPhone15,3")) return 2;
        NSString *domain=@(argv[2]), *container=@(argv[3]);
        NSArray *keys=ReviewedEmbeddedKeys()[domain];
        if (!keys || ![container hasPrefix:@"/private/var/mobile/Containers/Data/Application/"] ||
            [container containsString:@".."] || ![[NSUUID alloc] initWithUUIDString:container.lastPathComponent] ||
            ![NSUserDefaults instancesRespondToSelector:@selector(_initWithSuiteName:container:)]) return 2;
        NSUserDefaults *defaults=[[NSUserDefaults alloc] _initWithSuiteName:domain
            container:[NSURL fileURLWithPath:container isDirectory:YES]];
        if (!defaults) return 3;
        if (!strcmp(argv[1],"apply") && argc==5) {
            NSDictionary *patch=[NSDictionary dictionaryWithContentsOfFile:@(argv[4])];
            if (![patch isKindOfClass:NSDictionary.class] || ![patch[@"set"] isKindOfClass:NSDictionary.class] ||
                [patch count]!=1) return 2;
            NSDictionary *set=patch[@"set"];
            for (NSString *key in set) if (![keys containsObject:key]) return 2;
            for (NSString *key in set) [defaults setObject:set[key] forKey:key];
            if (![defaults synchronize]) return 1;
        } else if (strcmp(argv[1],"read") || argc!=4) return 2;
        NSDictionary *raw=defaults.dictionaryRepresentation;
        NSMutableDictionary *values=[NSMutableDictionary dictionary];
        for (NSString *key in keys) if (raw[key]) values[key]=raw[key];
        // dictionaryRepresentation includes inherited global defaults; only
        // the exact reviewed plugin keys are returned. Disk evidence must be
        // read through SSH /rootfs: RootHide remaps ordinary Foundation paths.
        NSData *output=[NSPropertyListSerialization dataWithPropertyList:values
            format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        return output && fwrite(output.bytes,1,output.length,stdout)==output.length ? 0 : 1;
    }
}

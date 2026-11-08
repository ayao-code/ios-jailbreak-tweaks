#import <Foundation/Foundation.h>
#import <dlfcn.h>

// Opaque XPC declarations; the existing iOS SDK lacks public XPC headers.
typedef struct _xpc_object_s *xpc_object_t;
typedef const struct _xpc_type_s *xpc_type_t;
extern const struct _xpc_type_s _xpc_type_dictionary;
extern const struct _xpc_type_s _xpc_type_int64;
extern const struct _xpc_type_s _xpc_type_bool;
extern xpc_object_t xpc_dictionary_create(const char *const *, const xpc_object_t *, size_t);
extern void xpc_dictionary_set_string(xpc_object_t, const char *, const char *);
extern xpc_object_t xpc_dictionary_get_value(xpc_object_t, const char *);
extern int64_t xpc_dictionary_get_int64(xpc_object_t, const char *);
extern bool xpc_dictionary_get_bool(xpc_object_t, const char *);
extern xpc_type_t xpc_get_type(xpc_object_t);
extern void xpc_release(xpc_object_t);

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc < 3 || getuid() != 501) return 2;
        if (!strcmp(argv[1], "inspect")) {
            NSString *path = @(argv[2]);
            if (![path hasPrefix:@"/private/var/mobile/Containers/Shared/AppGroup/.jbroot-"] ||
                ![path containsString:@"/var/mobile/Library/RootHide/"] ||
                [path containsString:@".."]) return 2;
            NSDictionary *data = [NSDictionary dictionaryWithContentsOfFile:path];
            id config = data[@"appconfig"];
            if (![config isKindOfClass:NSMutableDictionary.class]) {
                fprintf(stderr, "appconfig_not_native_mutable_dictionary\n"); return 3;
            }
            NSDictionary *result = @{@"native_dictionary_class": NSStringFromClass([config class]),
                                     @"appconfig": config};
            NSData *output = [NSPropertyListSerialization dataWithPropertyList:result
                format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
            return output && fwrite(output.bytes, 1, output.length, stdout) == output.length ? 0 : 1;
        }
        if (strcmp(argv[1], "query")) return 2;
        NSString *home = NSHomeDirectory();
        if (![home hasPrefix:@"/var/containers/Bundle/Application/.jbroot-"] ||
            ![home hasSuffix:@"/var/mobile"]) return 2;
        NSString *root = [home substringToIndex:home.length - @"/var/mobile".length];
        void *lib = dlopen([[root stringByAppendingPathComponent:@"basebin/libjailbreak.dylib"] fileSystemRepresentation], RTLD_NOW);
        if (!lib) { fprintf(stderr, "native_query_library_unavailable: %s\n", dlerror()); return 4; }
        xpc_object_t (*send)(uint64_t, uint64_t, xpc_object_t) = dlsym(lib, "jbserver_xpc_send");
        if (!send) return 4;
        NSMutableDictionary *results = [NSMutableDictionary dictionary];
        for (int i = 2; i < argc; i++) {
            xpc_object_t request = xpc_dictionary_create(NULL, NULL, 0);
            xpc_dictionary_set_string(request, "checktype", "bundle");
            xpc_dictionary_set_string(request, "checkvalue", argv[i]);
            // Domain/action verified in this device's blacklist_check_bundle.
            xpc_object_t reply = send(6, 3, request);
            xpc_release(request);
            if (!reply || xpc_get_type(reply) != &_xpc_type_dictionary) {
                if (reply) xpc_release(reply);
                return 5;
            }
            xpc_object_t status = xpc_dictionary_get_value(reply, "result");
            xpc_object_t value = xpc_dictionary_get_value(reply, "blacklisted");
            if (!status || xpc_get_type(status) != &_xpc_type_int64 ||
                !value || xpc_get_type(value) != &_xpc_type_bool ||
                xpc_dictionary_get_int64(reply, "result") != 0) {
                xpc_release(reply);
                return 5;
            }
            results[@(argv[i])] = @(xpc_dictionary_get_bool(reply, "blacklisted"));
            xpc_release(reply);
        }
        NSData *output = [NSPropertyListSerialization dataWithPropertyList:results
            format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        return output && fwrite(output.bytes, 1, output.length, stdout) == output.length ? 0 : 1;
    }
}

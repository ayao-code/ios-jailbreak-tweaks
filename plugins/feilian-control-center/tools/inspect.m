#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "../FeilianRequest.h"

@interface NSObject (VPNInspection)
+ (instancetype)sharedInstance;
- (NSArray *)vpnServicesForCurrentSetWithGrade:(NSUInteger)grade;
- (id)connectionWithServiceID:(id)serviceID withGrade:(NSUInteger)grade;
- (id)displayName;
- (id)bundleID;
- (NSUInteger)status;
- (BOOL)connected;
- (void)connect;
- (void)disconnect;
- (BOOL)enabled;
- (BOOL)isProviderAvailable;
- (id)lastStopCause;
+ (instancetype)defaultWorkspace;
- (BOOL)openApplicationWithBundleID:(NSString *)identifier;
- (BOOL)openSensitiveURL:(NSURL *)url withOptions:(NSDictionary *)options;
+ (instancetype)sharedService;
- (void)openApplication:(NSString *)identifier options:(NSDictionary *)options withResult:(id)result;
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--silent-result") == 0) {
            int token = NOTIFY_TOKEN_INVALID;
            if (notify_register_check(FeilianResultName, &token) != NOTIFY_STATUS_OK) return 2;
            uint64_t result = 0;
            uint32_t code = notify_get_state(token, &result);
            notify_cancel(token);
            printf("silent_result_available=%d code=%llu\n", code == NOTIFY_STATUS_OK, result % 256);
            return code == NOTIFY_STATUS_OK ? 0 : 1;
        }
        if (argc > 1 && strcmp(argv[1], "--cc") == 0) {
            dlopen("/System/Library/PrivateFrameworks/ControlCenterServices.framework/ControlCenterServices", RTLD_NOW);
            unsigned int classCount = 0;
            Class *classes = objc_copyClassList(&classCount);
            for (unsigned int i = 0; i < classCount; i++) {
                NSString *name = NSStringFromClass(classes[i]);
                if (![name hasPrefix:@"CCS"] || (![name containsString:@"Settings"] && ![name containsString:@"Configuration"])) continue;
                printf("CLASS %s\n", name.UTF8String);
                for (int meta = 0; meta < 2; meta++) {
                    unsigned int count = 0;
                    Method *methods = class_copyMethodList(meta ? object_getClass(classes[i]) : classes[i], &count);
                    for (unsigned int j = 0; j < count; j++) printf("%c %s %s\n", meta ? '+' : '-', sel_getName(method_getName(methods[j])), method_getTypeEncoding(methods[j]));
                    free(methods);
                }
            }
            free(classes);
            return 0;
        }
        NSBundle *bundle = [NSBundle bundleWithPath:@"/System/Library/PreferenceBundles/VPNPreferences.bundle"];
        NSError *error = nil;
        BOOL loaded = [bundle loadAndReturnError:&error];
        NSLog(@"VPNPreferences loaded=%d error=%@", loaded, error);
        if (argc > 1 && strcmp(argv[1], "--background-open") == 0) {
            dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW);
            NSString *const *key = (NSString *const *)dlsym(RTLD_DEFAULT, "FBSOpenApplicationOptionKeyActivateSuspended");
            if (!key || !*key) return 2;
            printf("background_launch_option=%s\n", (*key).UTF8String);
            id service = [NSClassFromString(@"FBSSystemService") sharedService];
            [service openApplication:@"com.volcengine.corplink" options:@{*key: @YES}
                withResult:^(NSError *error) { printf("background_launch_error=%ld domain=%s reason=%s\n", (long)error.code, error.domain.UTF8String, error.localizedDescription.UTF8String); }];
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
            return 0;
        }
        if (argc > 1 && strcmp(argv[1], "--official-connect-fbs") == 0) {
            dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW);
            id service = [NSClassFromString(@"FBSSystemService") sharedService];
            if (![service respondsToSelector:@selector(openApplication:options:withResult:)]) return 2;
            [service openApplication:@"com.volcengine.corplink"
                options:@{@"__PayloadURL": [NSURL URLWithString:@"feilianx://vpn/connect"]} withResult:^(NSError *error) {
                    printf("fbs_official_url_error=%ld\n", (long)error.code);
                }];
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
            return 0;
        }
        if (argc > 1 && strcmp(argv[1], "--official-connect") == 0) {
            // Exact URL extracted from Feilian 3.3.26's own Today extension.
            // No tokens, session options, App injection or preferences writes.
            id workspace = [NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
            if (![workspace respondsToSelector:@selector(openSensitiveURL:withOptions:)]) return 2;
            BOOL opened = [workspace openSensitiveURL:[NSURL URLWithString:@"feilianx://vpn/connect"]
                withOptions:@{@"LSOpenApplicationIdentifier": @"com.volcengine.corplink"}];
            printf("official_connect_url_dispatched=%d\n", opened);
            return opened ? 0 : 1;
        }
        if (argc > 1 && (strcmp(argv[1], "--open") == 0 || strcmp(argv[1], "--settings") == 0)) {
            [NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
            NSString *identifier = strcmp(argv[1], "--settings") == 0 ? @"com.apple.Preferences" : @"com.volcengine.corplink";
            BOOL opened = [[NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace] openApplicationWithBundleID:identifier];
            printf("opened=%d\n", opened);
            return opened ? 0 : 1;
        }
        id store = [NSClassFromString(@"VPNConnectionStore") sharedInstance];
        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:nil object:nil queue:nil usingBlock:^(NSNotification *note) {
            if ([note.name.lowercaseString containsString:@"vpn"] || [note.name.lowercaseString containsString:@"connection"]) NSLog(@"NOTIFICATION %@", note.name);
        }];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while ([deadline timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        for (NSUInteger grade = 0; grade < 4; grade++) {
            id services = [store vpnServicesForCurrentSetWithGrade:grade];
            printf("GRADE %lu class=%s count=%lu\n", (unsigned long)grade, class_getName([services class]), (unsigned long)[services count]);
            for (id serviceID in services) {
                id connection = [store connectionWithServiceID:serviceID withGrade:grade];
                printf("PROFILE %s grade=%lu name=%s bundle=%s status=%lu connected=%d enabled=%d available=%d stop=%s\n", [[serviceID description] UTF8String], (unsigned long)grade, [[connection displayName] UTF8String], [[connection bundleID] UTF8String], (unsigned long)[connection status], [connection connected], [connection enabled], [connection isProviderAvailable], [[[connection lastStopCause] description] UTF8String]);
                if (argc > 1 && [[connection bundleID] isEqualToString:@"com.volcengine.corplink"]) {
                    NSString *action = @(argv[1]);
                    if ([action isEqualToString:@"--connect"]) [connection connect];
                    if ([action isEqualToString:@"--disconnect"]) [connection disconnect];
                }
            }
        }
        if (argc < 2) return 0;
        if (strcmp(argv[1], "--methods") != 0) {
            NSDate *stop = [NSDate dateWithTimeIntervalSinceNow:10];
            while ([stop timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
            [[NSNotificationCenter defaultCenter] removeObserver:observer];
            return 0;
        }
        for (NSString *name in @[@"VPNConnectionStore", @"VPNConnection", @"VPNBundleController"]) {
            Class cls = NSClassFromString(name);
            printf("CLASS %s %p\n", name.UTF8String, cls);
            for (int meta = 0; meta < 2; meta++) {
                unsigned int count = 0;
                Method *methods = class_copyMethodList(meta ? object_getClass(cls) : cls, &count);
                for (unsigned int i = 0; i < count; i++) printf("%c %s %s\n", meta ? '+' : '-', sel_getName(method_getName(methods[i])), method_getTypeEncoding(methods[i]));
                free(methods);
            }
        }
    }
    return 0;
}

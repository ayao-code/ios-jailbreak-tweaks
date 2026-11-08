#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import <sys/sysctl.h>
#import <string.h>

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allApplications;
- (BOOL)uninstallApplication:(NSString *)identifier withOptions:(NSDictionary *)options;
@end

@interface LSApplicationProxy : NSObject
@property(nonatomic, readonly) NSString *bundleIdentifier;
@property(nonatomic, readonly) NSString *applicationType;
@property(nonatomic, readonly) NSURL *bundleURL;
@property(nonatomic, readonly) NSURL *dataContainerURL;
@property(nonatomic, readonly) NSDictionary *entitlements;
@end

static NSArray<NSString *> *ApprovedApplications(void)
{
    return @[@"com.taobao.taobao4iphone", @"com.alipay.iphoneclient", @"com.taobao.tmall",
             @"cn.damai.iphone", @"com.taobao.fleamarket", @"com.quark.browser",
             @"com.autonavi.amap", @"com.alicloud.smartdrive", @"com.taobao.live",
             @"com.taobao.etaocoupon", @"com.alimama.moon", @"com.wdk.hmxs"];
}

static NSString *Machine(void)
{
    char machine[128] = {0};
    size_t length = sizeof(machine);
    return sysctlbyname("hw.machine", machine, &length, NULL, 0) == 0 ? @(machine) : @"unknown";
}

static LSApplicationProxy *FindApplication(NSString *identifier)
{
    for (LSApplicationProxy *proxy in [[LSApplicationWorkspace defaultWorkspace] allApplications]) {
        if ([proxy.bundleIdentifier isEqual:identifier]) return proxy;
    }
    return nil;
}

static NSDictionary *KeychainCount(NSString *group, CFStringRef itemClass, NSString *name)
{
    LAContext *context = [LAContext new];
    context.interactionNotAllowed = YES;
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)itemClass,
        (__bridge id)kSecAttrAccessGroup: group,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
        (__bridge id)kSecAttrSynchronizable: (__bridge id)kSecAttrSynchronizableAny,
        (__bridge id)kSecReturnPersistentRef: @YES,
        (__bridge id)kSecUseAuthenticationContext: context
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    id count = NSNull.null;
    if (status == errSecSuccess && result) {
        if (CFGetTypeID(result) == CFArrayGetTypeID()) count = @([(__bridge NSArray *)result count]);
        else if (CFGetTypeID(result) == CFDataGetTypeID()) count = @1;
    } else if (status == errSecItemNotFound) count = @0;
    if (result) CFRelease(result);
    return @{@"group": group, @"class": name, @"status": @(status), @"accessible_count": count};
}

static BOOL PrintJSON(id value)
{
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:NULL];
    if (!data) return NO;
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    return YES;
}

int main(int argc, char *argv[])
{
    @autoreleasepool {
        if (![Machine() isEqual:@"iPhone15,3"]) {
            PrintJSON(@{@"error": @"14PM_only_no_mutation"});
            return 1;
        }
        LSApplicationWorkspace *workspace = [LSApplicationWorkspace defaultWorkspace];
        if (argc == 2 && strcmp(argv[1], "--inventory") == 0) {
            NSMutableArray *applications = [NSMutableArray new];
            NSMutableSet *groups = [NSMutableSet new];
            for (NSString *identifier in ApprovedApplications()) {
                LSApplicationProxy *proxy = FindApplication(identifier);
                if (!proxy) continue;
                NSDictionary *entitlements = proxy.entitlements;
                NSArray *accessGroups = entitlements[@"keychain-access-groups"];
                if (![accessGroups isKindOfClass:NSArray.class] || accessGroups.count == 0) {
                    NSString *defaultGroup = entitlements[@"application-identifier"];
                    accessGroups = [defaultGroup isKindOfClass:NSString.class] ? @[defaultGroup] : @[];
                }
                for (id group in accessGroups) if ([group isKindOfClass:NSString.class]) [groups addObject:group];
                NSArray *appGroups = entitlements[@"com.apple.security.application-groups"];
                [applications addObject:@{
                    @"id": identifier, @"type": proxy.applicationType ?: @"unknown",
                    @"path": proxy.bundleURL.path ?: @"unknown",
                    @"container": proxy.dataContainerURL.path ?: @"unknown",
                    @"keychain_groups": accessGroups,
                    @"shared_groups": [appGroups isKindOfClass:NSArray.class] ? appGroups : @[]
                }];
            }
            NSMutableArray *counts = [NSMutableArray new];
            for (NSString *group in [groups.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
                [counts addObject:KeychainCount(group, kSecClassGenericPassword, @"generic_password")];
                [counts addObject:KeychainCount(group, kSecClassInternetPassword, @"internet_password")];
            }
            PrintJSON(@{@"machine": Machine(), @"mode": @"read_only_inventory", @"applications": applications,
                        @"keychain_counts": counts, @"no_secret_values_or_identifier_values_read": @YES});
            return 0;
        }
        if (argc == 3 && strcmp(argv[1], "--uninstall-approved") == 0) {
            NSString *identifier = @(argv[2]);
            if (![ApprovedApplications() containsObject:identifier]) return 2;
            LSApplicationProxy *proxy = FindApplication(identifier);
            NSString *path = proxy.bundleURL.path;
            BOOL userPath = [path hasPrefix:@"/private/var/containers/Bundle/Application/"] ||
                            [path hasPrefix:@"/var/containers/Bundle/Application/"];
            if (!proxy || ![proxy.applicationType isEqual:@"User"] || !userPath || [path containsString:@".jbroot-"]) {
                PrintJSON(@{@"id": identifier, @"error": @"unexpected_app_or_registration_no_uninstall"});
                return 1;
            }
            NSString *container = proxy.dataContainerURL.path;
            NSString *physical = [container hasPrefix:@"/rootfs/"] ? container :
                                 [@"/rootfs" stringByAppendingString:container ?: @""];
            NSString *nested = [physical stringByAppendingPathComponent:@"Library/___Crane_Containers"];
            if (!container || [NSFileManager.defaultManager fileExistsAtPath:nested]) {
                PrintJSON(@{@"id": identifier, @"error": @"missing_container_or_multicontainer_stop"});
                return 1;
            }
            BOOL success = [workspace uninstallApplication:identifier withOptions:nil];
            PrintJSON(@{@"id": identifier, @"system_uninstall_result": @(success),
                        @"no_direct_container_or_keychain_deletion": @YES});
            return success ? 0 : 1;
        }
        return 2;
    }
}

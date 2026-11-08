#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import <sys/sysctl.h>
#import <string.h>

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allApplications;
@end

@interface LSApplicationProxy : NSObject
@property(nonatomic, readonly) NSString *bundleIdentifier;
@property(nonatomic, readonly) NSDictionary *entitlements;
@end

static NSArray<NSString *> *ApprovedApplications(void)
{
    return @[@"com.taobao.taobao4iphone", @"com.alipay.iphoneclient", @"com.taobao.tmall",
             @"cn.damai.iphone", @"com.taobao.fleamarket", @"com.quark.browser",
             @"com.autonavi.amap", @"com.alicloud.smartdrive", @"com.taobao.live",
             @"com.taobao.etaocoupon", @"com.alimama.moon", @"com.wdk.hmxs"];
}

static NSArray<NSString *> *ApprovedGroups(void)
{
    return @[@"VJGTV94XY8.com.taobao.taobao4iphone", @"8H6B3SFEU4.com.ali.group",
             @"Q9J7SWGUN4.com.taobao.tmall", @"FFJNMLHK32.cn.damai.iphone",
             @"43Y657P48S.com.taobao.fleamarket", @"6TFXDT6MK5.com.quark.browser",
             @"Q6552JDTRL.com.autonavi.utdid", @"LJUJZGPE73.smartdrive.shared",
             @"MYV5GKGP85.com.taobao.live", @"VJGTV94XY8.com.taobao.etaocoupon",
             @"VMSRGD9Q5D.com.alimama.moon", @"H27CPCASR4.com.wdk.hmxs"];
}

static BOOL IsTargetDevice(void)
{
    char machine[128] = {0};
    size_t length = sizeof(machine);
    return sysctlbyname("hw.machine", machine, &length, NULL, 0) == 0 && strcmp(machine, "iPhone15,3") == 0;
}

static NSDictionary *Query(NSString *group, CFStringRef itemClass, BOOL synchronizable)
{
    LAContext *context = [LAContext new];
    context.interactionNotAllowed = YES;
    return @{
        (__bridge id)kSecClass: (__bridge id)itemClass,
        (__bridge id)kSecAttrAccessGroup: group,
        (__bridge id)kSecAttrSynchronizable: @(synchronizable),
        (__bridge id)kSecUseAuthenticationContext: context
    };
}

static NSSet<NSData *> *ReadReferences(NSString *group, CFStringRef itemClass, BOOL synchronizable, OSStatus *status)
{
    NSMutableDictionary *query = [Query(group, itemClass, synchronizable) mutableCopy];
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitAll;
    query[(__bridge id)kSecReturnPersistentRef] = @YES;
    CFTypeRef result = NULL;
    *status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    NSSet *references = nil;
    if (*status == errSecItemNotFound) {
        references = [NSSet set];
    } else if (*status == errSecSuccess && result && CFGetTypeID(result) == CFArrayGetTypeID()) {
        NSArray *items = (__bridge NSArray *)result;
        BOOL valid = items.count <= 1000;
        for (id item in items) if (![item isKindOfClass:NSData.class]) valid = NO;
        NSSet *unique = [NSSet setWithArray:items];
        if (valid && unique.count == items.count) references = unique;
    } else if (*status == errSecSuccess && result && CFGetTypeID(result) == CFDataGetTypeID()) {
        references = [NSSet setWithObject:(__bridge NSData *)result];
    }
    if (result) CFRelease(result);
    return references;
}

static NSArray<NSString *> *InstalledConsumers(void)
{
    NSMutableArray *consumers = [NSMutableArray new];
    NSArray *applications = [[LSApplicationWorkspace defaultWorkspace] allApplications];
    if (![applications isKindOfClass:NSArray.class] || applications.count == 0) return nil;
    NSSet *targetGroups = [NSSet setWithArray:ApprovedGroups()];
    for (LSApplicationProxy *proxy in applications) {
        NSString *identifier = proxy.bundleIdentifier;
        if (![identifier isKindOfClass:NSString.class]) return nil;
        if ([ApprovedApplications() containsObject:identifier]) {
            [consumers addObject:identifier];
            continue;
        }
        NSDictionary *entitlements = proxy.entitlements;
        if (entitlements && ![entitlements isKindOfClass:NSDictionary.class]) return nil;
        NSArray *groups = entitlements[@"keychain-access-groups"];
        NSString *defaultGroup = entitlements[@"application-identifier"];
        if (groups && ![groups isKindOfClass:NSArray.class]) return nil;
        if ([defaultGroup isKindOfClass:NSString.class] && [targetGroups containsObject:defaultGroup]) {
            [consumers addObject:identifier];
        } else {
            for (id group in groups) {
                if ([targetGroups containsObject:group] || [group isEqual:@"*"]) {
                    [consumers addObject:identifier];
                    break;
                }
            }
        }
    }
    return consumers;
}

static BOOL PrintJSON(id value)
{
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:NULL];
    if (!data) return NO;
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
    return YES;
}

static int ResetDiantaoSync(void)
{
    NSString *targetGroup = @"MYV5GKGP85.com.taobao.live";
    NSArray *classes = @[@[(__bridge id)kSecClassGenericPassword, @"generic_password"],
                         @[(__bridge id)kSecClassInternetPassword, @"internet_password"]];
    NSMutableArray<NSSet *> *beforeReferences = [NSMutableArray new];
    NSMutableArray *beforeCounts = [NSMutableArray new];
    BOOL preconditions = YES;
    for (NSString *group in ApprovedGroups()) {
        for (NSArray *item in classes) {
            for (NSNumber *synchronizable in @[@NO, @YES]) {
                OSStatus status = 0;
                CFStringRef itemClass = (__bridge CFStringRef)item[0];
                NSSet *references = ReadReferences(group, itemClass, synchronizable.boolValue, &status);
                BOOL isTarget = [group isEqual:targetGroup] && itemClass == kSecClassGenericPassword && synchronizable.boolValue;
                NSUInteger expectedCount = isTarget ? 3 : 0;
                if (!references || references.count != expectedCount) preconditions = NO;
                [beforeReferences addObject:references ?: [NSSet set]];
                [beforeCounts addObject:@{@"group": group, @"class": item[1],
                                          @"synchronizable": synchronizable, @"status": @(status),
                                          @"count": references ? @(references.count) : NSNull.null}];
            }
        }
    }
    if (!preconditions) {
        PrintJSON(@{@"operation": @"diantao_sync_precondition_failed", @"delete_attempted": @NO,
                    @"counts": beforeCounts});
        return 1;
    }
    OSStatus currentStatus = 0;
    NSSet *current = ReadReferences(targetGroup, kSecClassGenericPassword, YES, &currentStatus);
    NSUInteger targetIndex = [ApprovedGroups() indexOfObject:targetGroup] * 4 + 1;
    if (!current || ![current isEqualToSet:beforeReferences[targetIndex]]) {
        PrintJSON(@{@"operation": @"diantao_sync_precondition_failed", @"delete_attempted": @NO,
                    @"reason": @"target_changed_before_delete"});
        return 1;
    }
    NSArray *consumers = InstalledConsumers();
    if (!consumers || consumers.count) {
        PrintJSON(@{@"operation": @"diantao_sync_precondition_failed", @"delete_attempted": @NO,
                    @"reason": @"consumer_query_changed"});
        return 1;
    }
    OSStatus deleteStatus = SecItemDelete((__bridge CFDictionaryRef)Query(targetGroup, kSecClassGenericPassword, YES));
    NSMutableArray *afterCounts = [NSMutableArray new];
    BOOL otherReferencesUnchanged = YES;
    BOOL targetAbsent = NO;
    NSUInteger position = 0;
    for (NSString *group in ApprovedGroups()) {
        for (NSArray *item in classes) {
            for (NSNumber *synchronizable in @[@NO, @YES]) {
                OSStatus status = 0;
                CFStringRef itemClass = (__bridge CFStringRef)item[0];
                NSSet *references = ReadReferences(group, itemClass, synchronizable.boolValue, &status);
                if (position == targetIndex) {
                    targetAbsent = references && references.count == 0 && status == errSecItemNotFound;
                } else if (!references || ![references isEqualToSet:beforeReferences[position]]) {
                    otherReferencesUnchanged = NO;
                }
                [afterCounts addObject:@{@"group": group, @"class": item[1],
                                         @"synchronizable": synchronizable, @"status": @(status),
                                         @"count": references ? @(references.count) : NSNull.null}];
                position++;
            }
        }
    }
    BOOL verified = deleteStatus == errSecSuccess && targetAbsent && otherReferencesUnchanged;
    PrintJSON(@{@"operation": @"user_authorized_diantao_sync_reset", @"target_group": targetGroup,
                @"class": @"generic_password", @"synchronizable": @YES,
                @"before_target_count": @(current.count), @"delete_status": @(deleteStatus),
                @"target_absent_on_device": @(targetAbsent), @"other_checked_references_unchanged": @(otherReferencesUnchanged),
                @"verified_on_device": @(verified), @"after_counts": afterCounts,
                @"icloud_propagation": @"not_observed_no_other_device_access",
                @"no_secret_values_read": @YES, @"no_hardware_or_system_id_modification": @YES,
                @"scope": @"exact_diantao_group_generic_password_sync_true_only"});
    return verified ? 0 : 1;
}

int main(int argc, char *argv[])
{
    @autoreleasepool {
        BOOL erase = argc == 2 && strcmp(argv[1], "--erase-local-approved-groups") == 0;
        BOOL inspect = argc == 2 && strcmp(argv[1], "--inspect") == 0;
        BOOL eraseDiantaoSync = argc == 2 && strcmp(argv[1], "--erase-diantao-sync-only") == 0;
        if ((!erase && !inspect && !eraseDiantaoSync) || !IsTargetDevice()) return 2;
        NSArray *consumers = InstalledConsumers();
        if (!consumers || consumers.count) {
            PrintJSON(@{@"operation": @"precondition_failed", @"delete_attempted": @NO,
                        @"reason": @"target_or_shared_consumer_still_installed_or_query_failed",
                        @"consumers": consumers ?: @[]});
            return 1;
        }
        if (eraseDiantaoSync) return ResetDiantaoSync();
        NSArray *classes = @[@[(__bridge id)kSecClassGenericPassword, @"generic_password"],
                             @[(__bridge id)kSecClassInternetPassword, @"internet_password"]];
        NSMutableArray *counts = [NSMutableArray new];
        NSMutableArray<NSSet *> *localBefore = [NSMutableArray new];
        NSMutableArray<NSSet *> *synchronizedBefore = [NSMutableArray new];
        NSArray<NSNumber *> *expectedLocalCounts = @[@23, @29, @0, @11, @23, @6, @25, @14, @44, @14, @11, @0];
        BOOL preconditions = YES;
        BOOL approvedCountsMatch = YES;
        NSUInteger groupIndex = 0;
        for (NSString *group in ApprovedGroups()) {
            for (NSArray *item in classes) {
                CFStringRef itemClass = (__bridge CFStringRef)item[0];
                OSStatus localStatus = 0;
                OSStatus synchronizedStatus = 0;
                NSSet *local = ReadReferences(group, itemClass, NO, &localStatus);
                NSSet *synchronized = ReadReferences(group, itemClass, YES, &synchronizedStatus);
                [counts addObject:@{@"group": group, @"class": item[1],
                                     @"local_status": @(localStatus), @"local_count": local ? @(local.count) : NSNull.null,
                                     @"sync_status": @(synchronizedStatus), @"sync_count": synchronized ? @(synchronized.count) : NSNull.null}];
                if (!local || !synchronized) preconditions = NO;
                NSUInteger expectedLocal = itemClass == kSecClassGenericPassword ? expectedLocalCounts[groupIndex].unsignedIntegerValue : 0;
                NSUInteger expectedSync = itemClass == kSecClassGenericPassword && groupIndex == 8 ? 3 : 0;
                if (!local || !synchronized || local.count != expectedLocal || synchronized.count != expectedSync) approvedCountsMatch = NO;
                [localBefore addObject:local ?: [NSSet set]];
                [synchronizedBefore addObject:synchronized ?: [NSSet set]];
            }
            groupIndex++;
        }
        PrintJSON(@{@"operation": @"read_only_preflight", @"counts": counts,
                    @"preconditions_met": @(preconditions), @"delete_attempted": @NO,
                    @"approved_counts_match": @(approvedCountsMatch),
                    @"scope": @"12_exact_groups_local_generic_and_internet_passwords_no_secret_values"});
        if (!preconditions) return 1;
        if (inspect) return 0;
        if (!approvedCountsMatch) return 1;

        NSUInteger position = 0;
        NSUInteger totalDeleted = 0;
        for (NSString *group in ApprovedGroups()) {
            for (NSArray *item in classes) {
                CFStringRef itemClass = (__bridge CFStringRef)item[0];
                OSStatus beforeStatus = 0;
                NSSet *current = ReadReferences(group, itemClass, NO, &beforeStatus);
                if (!current || ![current isEqualToSet:localBefore[position]]) {
                    PrintJSON(@{@"operation": @"stopped", @"reason": @"local_items_changed_before_delete",
                                @"group": group, @"class": item[1], @"earlier_deleted_count": @(totalDeleted)});
                    return 1;
                }
                OSStatus deletionStatus = errSecItemNotFound;
                if (current.count) {
                    deletionStatus = SecItemDelete((__bridge CFDictionaryRef)Query(group, itemClass, NO));
                }
                OSStatus afterStatus = 0;
                OSStatus synchronizedStatus = 0;
                NSSet *after = ReadReferences(group, itemClass, NO, &afterStatus);
                NSSet *synchronized = ReadReferences(group, itemClass, YES, &synchronizedStatus);
                BOOL verified = (deletionStatus == errSecSuccess || (!current.count && deletionStatus == errSecItemNotFound)) &&
                                after && after.count == 0 && synchronized &&
                                [synchronized isEqualToSet:synchronizedBefore[position]];
                if (deletionStatus == errSecSuccess) totalDeleted += current.count;
                PrintJSON(@{@"operation": @"local_group_reset", @"group": group, @"class": item[1],
                            @"before_count": @(current.count), @"delete_status": @(deletionStatus),
                            @"after_count": after ? @(after.count) : NSNull.null,
                            @"sync_references_unchanged": @(synchronized && [synchronized isEqualToSet:synchronizedBefore[position]]),
                            @"verified": @(verified)});
                if (!verified) return 1;
                position++;
            }
        }
        PrintJSON(@{@"operation": @"complete", @"deleted_local_password_items": @(totalDeleted),
                    @"sync_items_preserved": @YES, @"other_groups_not_queried_or_deleted": @YES,
                    @"certificates_and_private_keys_not_deleted": @YES,
                    @"no_hardware_or_system_id_modification": @YES,
                    @"business_recovery_not_verified": @YES});
        return 0;
    }
}

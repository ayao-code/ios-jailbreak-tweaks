#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import <string.h>

static NSString *const TargetGroup = @"VJGTV94XY8.com.taobao.taobao4iphone";
static NSString *const SecurityPrefix = @"com.alipay.alisecx.localstorage.";
static NSString *const AppService = @"com.taobao.taobao4iphone";

static NSDictionary *BaseQuery(void)
{
    LAContext *authentication = [LAContext new];
    authentication.interactionNotAllowed = YES;
    return @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccessGroup: TargetGroup,
        (__bridge id)kSecAttrSynchronizable: @NO,
        (__bridge id)kSecUseAuthenticationContext: authentication
    };
}

static NSArray *ReadMetadata(OSStatus *status)
{
    NSMutableDictionary *query = [BaseQuery() mutableCopy];
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitAll;
    query[(__bridge id)kSecReturnAttributes] = @YES;
    query[(__bridge id)kSecReturnPersistentRef] = @YES;
    CFTypeRef result = NULL;
    *status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    NSArray *items = nil;
    if (*status == errSecSuccess && result && CFGetTypeID(result) == CFArrayGetTypeID()) {
        items = [(__bridge NSArray *)result copy];
    }
    if (result) CFRelease(result);
    return items;
}

static BOOL IsSecurityService(id service)
{
    return [service isKindOfClass:NSString.class] && [(NSString *)service hasPrefix:SecurityPrefix];
}

static BOOL IsTargetService(id service)
{
    return IsSecurityService(service) || [service isEqual:AppService];
}

static NSDictionary *NonTargetMetadata(NSArray *items)
{
    if (!items) return nil;
    NSMutableDictionary *preserved = [NSMutableDictionary new];
    for (id item in items) {
        if (![item isKindOfClass:NSDictionary.class]) return nil;
        NSDictionary *metadata = item;
        if (![metadata[(__bridge id)kSecAttrAccessGroup] isEqual:TargetGroup]) return nil;
        if ([metadata[(__bridge id)kSecAttrSynchronizable] boolValue]) return nil;
        if (IsTargetService(metadata[(__bridge id)kSecAttrService])) continue;
        id reference = metadata[(__bridge id)kSecValuePersistentRef];
        if (![reference isKindOfClass:NSData.class] || preserved[reference]) return nil;
        preserved[reference] = metadata;
    }
    return preserved;
}

static BOOL PrintReport(NSDictionary *report)
{
    NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL];
    if (!data) return NO;
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    return YES;
}

int main(int argc, char *argv[])
{
    @autoreleasepool {
        BOOL deletionRequested = argc == 2 && strcmp(argv[1], "--delete-approved-services") == 0;
        BOOL inspectOnly = argc == 2 && strcmp(argv[1], "--inspect") == 0;
        if (!deletionRequested && !inspectOnly) return 2;

        OSStatus beforeStatus = errSecSuccess;
        NSArray *before = ReadMetadata(&beforeStatus);
        NSDictionary *preserved = NonTargetMetadata(before);
        NSUInteger securityCount = 0;
        NSUInteger appCount = 0;
        NSMutableSet<NSString *> *securityServices = [NSMutableSet new];
        for (id item in before) {
            if (![item isKindOfClass:NSDictionary.class]) continue;
            id service = item[(__bridge id)kSecAttrService];
            if (IsSecurityService(service)) {
                securityCount++;
                [securityServices addObject:service];
            } else if ([service isEqual:AppService]) {
                appCount++;
            }
        }
        BOOL preconditions = beforeStatus == errSecSuccess && preserved && before.count == 18 &&
                             securityCount == 8 && appCount == 3 && preserved.count == 7 && securityServices.count == 1;
        NSMutableDictionary *report = [@{
            @"operation": deletionRequested ? @"user_authorized_exact_service_reset" : @"read_only_preflight",
            @"access_group": TargetGroup, @"before_status": @(beforeStatus),
            @"before_total": @(before.count), @"security_target_count": @(securityCount),
            @"app_target_count": @(appCount), @"preserved_count": @(preserved.count),
            @"preconditions_met": @(preconditions), @"delete_attempted": @NO,
            @"scope": @"generic_password_exact_group_service_non_sync_only",
            @"limitations": @[
                @"no_secret_values_read_no_account_or_identity_values_exported",
                @"security_sdk_state_reset_may_require_reauthentication_not_a_coupon_recovery_guarantee",
                @"no_idfv_umid_adiu_changes_no_other_group_deletion_no_app_injection",
                @"user_declined_backup_deletion_is_irreversible"
            ]
        } mutableCopy];
        if (inspectOnly || !preconditions) {
            PrintReport(report);
            return preconditions ? 0 : 1;
        }

        NSMutableArray *results = [NSMutableArray new];
        NSArray *services = @[securityServices.anyObject, AppService];
        for (NSUInteger index = 0; index < services.count; index++) {
            NSMutableDictionary *query = [BaseQuery() mutableCopy];
            query[(__bridge id)kSecAttrService] = services[index];
            OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
            [results addObject:@{@"category": index == 0 ? @"alisecx_localstorage" : @"taobao_app_service",
                                 @"status": @(status)}];
            if (status != errSecSuccess) break;
        }
        OSStatus afterStatus = errSecSuccess;
        NSArray *after = ReadMetadata(&afterStatus);
        NSDictionary *remaining = NonTargetMetadata(after);
        BOOL unchanged = remaining && [preserved isEqualToDictionary:remaining];
        BOOL verified = results.count == 2 && afterStatus == errSecSuccess && after.count == 7 &&
                        remaining.count == after.count && unchanged;
        for (NSDictionary *result in results) {
            if ([result[@"status"] intValue] != errSecSuccess) verified = NO;
        }
        report[@"delete_attempted"] = @YES;
        report[@"delete_results"] = results;
        report[@"after_status"] = @(afterStatus);
        report[@"after_total"] = @(after.count);
        report[@"non_target_metadata_unchanged"] = @(unchanged);
        report[@"verified"] = @(verified);
        PrintReport(report);
        return verified ? 0 : 1;
    }
}

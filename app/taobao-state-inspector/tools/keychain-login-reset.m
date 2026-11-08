#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import <string.h>

static NSString *const TargetGroup = @"VJGTV94XY8.com.taobao.taobao4iphone";
static NSString *const TargetService = @"com.taobao.login.service";

static NSDictionary *MatchingQuery(void)
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
    NSMutableDictionary *query = [MatchingQuery() mutableCopy];
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

static NSDictionary *NonTargetMetadata(NSArray *items)
{
    NSMutableDictionary *metadata = [NSMutableDictionary new];
    for (id item in items) {
        if (![item isKindOfClass:NSDictionary.class]) return nil;
        if ([item[(__bridge id)kSecAttrService] isEqual:TargetService]) continue;
        id reference = item[(__bridge id)kSecValuePersistentRef];
        if (![reference isKindOfClass:NSData.class] || metadata[reference]) return nil;
        metadata[reference] = item;
    }
    return metadata;
}

int main(int argc, char *argv[])
{
    @autoreleasepool {
        if (argc != 2 || strcmp(argv[1], "--delete-login-only") != 0) return 2;
        OSStatus beforeStatus = errSecSuccess;
        NSArray *before = ReadMetadata(&beforeStatus);
        NSDictionary *preserved = before ? NonTargetMetadata(before) : nil;
        NSUInteger targetCount = before.count - preserved.count;
        if (!preserved || beforeStatus != errSecSuccess || before.count != 20 || targetCount != 2) {
            printf("PRECONDITION_FAILED status=%d total=%lu target=%lu; nothing deleted\n",
                   (int)beforeStatus, (unsigned long)before.count, (unsigned long)targetCount);
            return 1;
        }
        NSMutableDictionary *deletion = [MatchingQuery() mutableCopy];
        deletion[(__bridge id)kSecAttrService] = TargetService;
        OSStatus deleteStatus = SecItemDelete((__bridge CFDictionaryRef)deletion);
        OSStatus afterStatus = errSecSuccess;
        NSArray *after = ReadMetadata(&afterStatus);
        NSDictionary *remaining = after ? NonTargetMetadata(after) : nil;
        BOOL preservedUnchanged = remaining && [preserved isEqualToDictionary:remaining];
        BOOL verified = deleteStatus == errSecSuccess && afterStatus == errSecSuccess &&
                        after.count == 18 && remaining.count == after.count && preservedUnchanged;
        NSDictionary *report = @{
            @"operation": @"user_authorized_exact_login_service_reset",
            @"access_group": TargetGroup, @"service": TargetService,
            @"before_total": @(before.count), @"before_target": @(targetCount),
            @"delete_status": @(deleteStatus), @"after_status": @(afterStatus),
            @"after_total": @(after.count), @"non_target_metadata_unchanged": @(preservedUnchanged),
            @"verified": @(verified),
            @"scope": @"no_password_or_token_values_read_no_identity_reset_no_other_group_deletion"
        };
        NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL];
        if (data) fwrite(data.bytes, 1, data.length, stdout);
        fputc('\n', stdout);
        return verified ? 0 : 1;
    }
}

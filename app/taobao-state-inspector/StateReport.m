#import "StateReport.h"
#import <Security/Security.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import <sys/utsname.h>

static NSString *const TSIKeychainGroup = @"VJGTV94XY8.com.taobao.taobao4iphone";
static NSString *const TSISharedGroup = @"group.com.taobao.taobao4iphone.extension";

static NSDictionary *TSICountClass(CFStringRef itemClass, NSString *className, id synchronizable)
{
    LAContext *authentication = [LAContext new];
    authentication.interactionNotAllowed = YES;
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)itemClass,
        (__bridge id)kSecAttrAccessGroup: TSIKeychainGroup,
        (__bridge id)kSecAttrSynchronizable: synchronizable,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
        (__bridge id)kSecReturnPersistentRef: @YES,
        (__bridge id)kSecUseAuthenticationContext: authentication
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    NSMutableDictionary *entry = [@{
        @"class": className,
        @"status": @(status),
        @"count": NSNull.null,
        @"interpretation": @"query_failed_not_evidence_of_absence"
    } mutableCopy];
    if (status == errSecSuccess) {
        id references = (__bridge id)result;
        if ([references isKindOfClass:NSArray.class]) {
            entry[@"count"] = @([(NSArray *)references count]);
            entry[@"interpretation"] = @"accessible_item_count_only";
        } else if ([references isKindOfClass:NSData.class]) {
            entry[@"count"] = @1;
            entry[@"interpretation"] = @"accessible_item_count_only";
        } else {
            entry[@"interpretation"] = @"unexpected_result_type";
        }
    } else if (status == errSecItemNotFound) {
        entry[@"count"] = @0;
        entry[@"interpretation"] = @"no_accessible_match_not_proof_of_total_absence";
    }
    if (result) CFRelease(result);
    return entry;
}

static NSString *TSISafeName(NSString *name)
{
    NSString *safeName = name;
    for (NSString *pattern in @[@"[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", @"[0-9]{5,}"]) {
        NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern
            options:NSRegularExpressionCaseInsensitive error:NULL];
        safeName = [expression stringByReplacingMatchesInString:safeName options:0
            range:NSMakeRange(0, safeName.length) withTemplate:@"[REDACTED]"];
    }
    return safeName.length > 120 ? [[safeName substringToIndex:120] stringByAppendingString:@"..."] : safeName;
}

static void TSIListDirectory(NSURL *directory, NSString *relativePath, NSUInteger depth,
                             NSMutableArray *entries, NSMutableArray *errors, BOOL *truncated)
{
    if (entries.count >= 150) {
        *truncated = YES;
        return;
    }
    NSError *error = nil;
    NSArray<NSURL *> *children = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory
        includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLIsSymbolicLinkKey]
        options:NSDirectoryEnumerationSkipsHiddenFiles error:&error];
    if (!children) {
        [errors addObject:@{@"directory": relativePath, @"domain": error.domain ?: @"unknown",
                            @"code": @(error.code)}];
        return;
    }
    children = [children sortedArrayUsingComparator:^NSComparisonResult(NSURL *first, NSURL *second) {
        return [first.lastPathComponent compare:second.lastPathComponent];
    }];
    for (NSURL *child in children) {
        if (entries.count >= 150) {
            *truncated = YES;
            return;
        }
        NSNumber *isDirectory = nil;
        NSNumber *isSymbolicLink = nil;
        NSError *directoryError = nil;
        NSError *linkError = nil;
        BOOL directoryKnown = [child getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&directoryError];
        BOOL linkKnown = [child getResourceValue:&isSymbolicLink forKey:NSURLIsSymbolicLinkKey error:&linkError];
        NSString *safePath = [relativePath stringByAppendingPathComponent:TSISafeName(child.lastPathComponent)];
        NSString *kind = !directoryKnown || !linkKnown ? @"unknown" :
            (isSymbolicLink.boolValue ? @"symlink_not_followed" : (isDirectory.boolValue ? @"directory" : @"file"));
        [entries addObject:@{@"path": safePath, @"kind": kind}];
        if (directoryKnown && linkKnown && isDirectory.boolValue && !isSymbolicLink.boolValue && depth < 2) {
            TSIListDirectory(child, safePath, depth + 1, entries, errors, truncated);
        }
    }
}

static NSDictionary *TSISharedDirectoryReport(void)
{
    NSString *parent = @"/private/var/mobile/Containers/Shared/AppGroup";
    NSError *error = nil;
    NSArray<NSString *> *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:parent error:&error];
    if (!names) {
        return @{@"identifier": TSISharedGroup, @"state": @"parent_unreadable",
                 @"domain": error.domain ?: @"unknown", @"code": @(error.code)};
    }
    NSMutableArray *matches = [NSMutableArray new];
    NSUInteger checked = 0;
    for (NSString *name in [names sortedArrayUsingSelector:@selector(compare:)]) {
        if (![[NSUUID alloc] initWithUUIDString:name]) continue;
        if (checked >= 512) break;
        checked++;
        NSURL *root = [NSURL fileURLWithPath:[parent stringByAppendingPathComponent:name] isDirectory:YES];
        NSNumber *isSymbolicLink = nil;
        if (![root getResourceValue:&isSymbolicLink forKey:NSURLIsSymbolicLinkKey error:NULL] || isSymbolicLink.boolValue) continue;
        NSURL *metadataURL = [root URLByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
        NSNumber *metadataIsLink = nil;
        NSNumber *metadataSize = nil;
        if (![metadataURL getResourceValue:&metadataIsLink forKey:NSURLIsSymbolicLinkKey error:NULL] || metadataIsLink.boolValue) continue;
        if (![metadataURL getResourceValue:&metadataSize forKey:NSURLFileSizeKey error:NULL] || metadataSize.unsignedLongLongValue > 65536) continue;
        NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfURL:metadataURL];
        if (![metadata[@"MCMMetadataIdentifier"] isEqual:TSISharedGroup]) continue;
        NSMutableArray *entries = [NSMutableArray new];
        NSMutableArray *errors = [NSMutableArray new];
        BOOL truncated = NO;
        TSIListDirectory(root, @".", 0, entries, errors, &truncated);
        [matches addObject:@{@"entries": entries, @"errors": errors, @"truncated": @(truncated)}];
    }
    return @{@"identifier": TSISharedGroup, @"state": matches.count ? @"matching_directory_metadata_only" : @"not_identified",
             @"matches": matches, @"candidate_roots_checked": @(checked), @"root_scan_limited": @(checked >= 512),
             @"note": @"only_group_identification_metadata_read_no_app_content_or_group_membership_added"};
}

NSDictionary *TSICollectReport(void)
{
    struct utsname systemInfo;
    NSString *machine = uname(&systemInfo) == 0 ? @(systemInfo.machine) : @"unknown";
    NSArray *classes = @[
        @[(__bridge id)kSecClassGenericPassword, @"generic_password"],
        @[(__bridge id)kSecClassInternetPassword, @"internet_password"]
    ];
    NSMutableArray *counts = [NSMutableArray new];
    for (NSArray *item in classes) {
        for (NSNumber *synchronizable in @[@NO, @YES]) {
            NSMutableDictionary *entry = [TSICountClass((__bridge CFStringRef)item[0], item[1], synchronizable) mutableCopy];
            entry[@"synchronizable"] = synchronizable;
            [counts addObject:entry];
        }
    }
    return @{
        @"schema": @1, @"helper_version": @"0.1.0", @"mode": @"read_only_non_app_store_diagnostic",
        @"created_at": [[NSISO8601DateFormatter new] stringFromDate:NSDate.date],
        @"machine": machine, @"os": NSProcessInfo.processInfo.operatingSystemVersionString,
        @"keychain_access_group": TSIKeychainGroup, @"keychain_counts": counts,
        @"shared_directory": TSISharedDirectoryReport(),
        @"limitations": @[
            @"counts_do_not_identify_account_history_or_coupon_failure_cause",
            @"persistent_references_are_counted_in_memory_never_exported",
            @"no_password_token_account_or_keychain_attribute_values_requested",
            @"no_deletion_network_hook_identifier_generation_or_target_app_launch",
            @"only_helper_own_documents_written_no_target_app_or_shared_directory_write"
        ]
    };
}

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <LocalAuthentication/LocalAuthentication.h>

static NSString *const TargetGroup = @"VJGTV94XY8.com.taobao.taobao4iphone";

static NSString *SafeServiceName(id value)
{
    if (![value isKindOfClass:NSString.class] || [(NSString *)value length] > 128) return @"not_exported";
    NSString *service = value;
    NSString *lower = service.lowercaseString;
    BOOL namespaceKnown = NO;
    for (NSString *prefix in @[@"com.", @"org.", @"group."]) {
        if ([lower hasPrefix:prefix]) namespaceKnown = YES;
    }
    if (!namespaceKnown) return @"not_exported";
    if ([lower hasPrefix:@"com.alipay.alisecx.localstorage."]) return @"com.alipay.alisecx.localstorage.[REDACTED]";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.- :"];
    if ([service rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) return @"not_exported";
    NSString *redacted = service;
    for (NSString *pattern in @[@"(?i)[a-f0-9]{16,}", @"[0-9]{4,}", @"[A-Za-z0-9]{24,}"]) {
        NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
        redacted = [expression stringByReplacingMatchesInString:redacted options:0
            range:NSMakeRange(0, redacted.length) withTemplate:@"[REDACTED]"];
    }
    return redacted;
}

static NSDictionary *NameStructure(id value)
{
    if (!value) return @{@"type": @"absent"};
    if ([value isKindOfClass:NSData.class]) return @{@"type": @"data", @"length": @([(NSData *)value length])};
    if (![value isKindOfClass:NSString.class]) return @{@"type": @"other"};
    NSString *text = value;
    NSString *shape = @"unclassified_text";
    if (text.length == 0) {
        shape = @"empty";
    } else if ([[NSUUID alloc] initWithUUIDString:text]) {
        shape = @"uuid_shaped";
    } else if ([text rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:
               @"0123456789abcdefABCDEF"].invertedSet].location == NSNotFound) {
        shape = @"hex_shaped";
    } else if ([text hasPrefix:@"com."] || [text hasPrefix:@"org."] || [text hasPrefix:@"group."]) {
        shape = @"namespace_shaped";
    }
    return @{@"type": @"string", @"length": @(text.length), @"shape": shape};
}

static NSArray *AccountKeySignals(id value)
{
    if (![value isKindOfClass:NSString.class]) return @[];
    NSString *lower = [(NSString *)value lowercaseString];
    if (lower.length > 128) return @[];
    NSCharacterSet *letters = [NSCharacterSet characterSetWithCharactersInString:
                               @"abcdefghijklmnopqrstuvwxyz_.- "];
    if ([lower rangeOfCharacterFromSet:letters.invertedSet].location != NSNotFound) return @[];
    NSMutableArray *signals = [NSMutableArray new];
    for (NSString *signal in @[@"login", @"history", @"remember", @"lastuser", @"last_user",
                              @"account", @"session", @"token", @"device", @"utdid", @"umid",
                              @"idfv", @"adiu", @"security", @"detect", @"jailbreak", @"risk"]) {
        if ([lower containsString:signal]) [signals addObject:signal];
    }
    return signals;
}

static NSDictionary *InspectClass(CFStringRef itemClass, NSString *className)
{
    LAContext *authentication = [LAContext new];
    authentication.interactionNotAllowed = YES;
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)itemClass,
        (__bridge id)kSecAttrAccessGroup: TargetGroup,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
        (__bridge id)kSecAttrSynchronizable: (__bridge id)kSecAttrSynchronizableAny,
        (__bridge id)kSecReturnAttributes: @YES,
        (__bridge id)kSecUseAuthenticationContext: authentication
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    NSMutableArray *records = [NSMutableArray new];
    if (status == errSecSuccess && result && CFGetTypeID(result) == CFArrayGetTypeID()) {
        for (id item in (__bridge NSArray *)result) {
            if (![item isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *attributes = item;
            NSMutableArray *signals = [NSMutableArray new];
            NSMutableDictionary *safeLoginNames = [NSMutableDictionary new];
            for (NSString *field in @[(__bridge NSString *)kSecAttrService, (__bridge NSString *)kSecAttrLabel]) {
                id value = attributes[field];
                if (![value isKindOfClass:NSString.class]) continue;
                NSString *lower = [(NSString *)value lowercaseString];
                if ([lower containsString:@"login"] && [(NSString *)value length] <= 96) {
                    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_.- "];
                    if ([(NSString *)value rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound) {
                        safeLoginNames[field] = value;
                    }
                }
                for (NSString *signal in @[@"login", @"account", @"user", @"token", @"device", @"uuid", @"utdid", @"umid",
                                           @"history", @"cache", @"session", @"risk", @"jail", @"root", @"security", @"key", @"sdk",
                                           @"detect", @"flag", @"auth", @"credential", @"last", @"remember", @"idfv", @"adiu", @"alisecx"]) {
                    if ([lower containsString:signal] && ![signals containsObject:signal]) [signals addObject:signal];
                }
            }
            [records addObject:@{@"index": @(records.count), @"name_signals": signals,
                                 @"safe_service_name": SafeServiceName(attributes[(__bridge id)kSecAttrService]),
                                 @"service_structure": NameStructure(attributes[(__bridge id)kSecAttrService]),
                                 @"label_structure": NameStructure(attributes[(__bridge id)kSecAttrLabel]),
                                 @"account_present": @([attributes objectForKey:(__bridge id)kSecAttrAccount] != nil),
                                 @"account_key_signals": AccountKeySignals(attributes[(__bridge id)kSecAttrAccount]),
                                 @"safe_login_name_only": safeLoginNames,
                                 @"purpose": @"not_confirmed_by_metadata",
                                 @"synchronizable": @([attributes[(__bridge id)kSecAttrSynchronizable] boolValue])}];
        }
    }
    if (result) CFRelease(result);
    return @{@"class": className, @"status": @(status), @"records": records,
             @"interpretation": status == errSecSuccess ? @"attribute_classification_only" : @"query_unavailable_not_evidence_of_absence"};
}

int main(int argc, char *argv[])
{
    @autoreleasepool {
        if (argc != 1) return 2;
        NSDictionary *report = @{
            @"mode": @"read_only_security_api_metadata",
            @"access_group": TargetGroup,
            @"classes": @[InspectClass(kSecClassGenericPassword, @"generic_password"),
                           InspectClass(kSecClassInternetPassword, @"internet_password")],
            @"limitations": @[@"attributes_requested_not_secret_data",
                                @"account_attributes_never_exported_only_allowlisted_vendor_namespace_or_login_names",
                                @"name_signals_do_not_prove_account_history_or_deletion_safety",
                                @"no_update_delete_identity_change_or_app_injection"]
        };
        NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL];
        if (!data) return 1;
        fwrite(data.bytes, 1, data.length, stdout);
        fputc('\n', stdout);
        return 0;
    }
}

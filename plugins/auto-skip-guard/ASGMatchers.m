#import "ASGMatchers.h"

NSString *ASGNormalizeText(NSString *text) {
    if (![text isKindOfClass:NSString.class] || text.length > 512) return @"";
    NSString *value = [[text precomposedStringWithCompatibilityMapping] lowercaseString];
    value = [value stringByReplacingOccurrencesOfString:@"跳過" withString:@"跳过"];
    value = [value stringByReplacingOccurrencesOfString:@"關閉" withString:@"关闭"];
    value = [value stringByReplacingOccurrencesOfString:@"廣告" withString:@"广告"];
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

BOOL ASGAdCountdownText(NSString *text) {
    NSString *value = ASGNormalizeText(text);
    static NSRegularExpression *pattern;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Repeated complete groups allow independently exposed label/value sources.
        // A unit is mandatory: ad budgets, years and prices are not countdown entries.
        NSString *ad = @"(?:广告|ad|advertisement)";
        NSString *separators = @"[\\s|丨:()·]*";
        NSString *counter = @"[0-9]{1,2}\\s*(?:s|秒|sec|seconds?)";
        NSString *expression = [NSString stringWithFormat:@"^(?:%@%@%@%@|%@%@%@%@)+$",
            ad, separators, counter, separators, counter, separators, ad, separators];
        pattern = [NSRegularExpression regularExpressionWithPattern:expression options:0 error:NULL];
    });
    return value.length && [pattern numberOfMatchesInString:value options:0 range:NSMakeRange(0, value.length)] == 1;
}

BOOL ASGSkipText(NSString *text) {
    NSString *value = ASGNormalizeText(text);
    return [value containsString:@"跳过"] || [value containsString:@"skip"] || [value containsString:@">>"];
}

ASGActionKind ASGActionForText(NSString *text) {
    NSString *value = ASGNormalizeText(text);
    if (ASGSkipText(value)) return ASGActionSkip;
    if ([value containsString:@"关闭"] || [value containsString:@"close"] || [value containsString:@"dismiss"])
        return ASGActionCloseAd;
    if (ASGAdCountdownText(value)) return ASGActionAdCountdown;
    return ASGActionNone;
}

ASGActionKind ASGActionForOCRText(NSString *text) {
    ASGActionKind kind = ASGActionForText(text);
    if (kind != ASGActionNone) return kind;
    NSString *value = ASGNormalizeText(text);
    // OCR may read the trailing s as 5. Discover only; the true timer is unknown.
    // Never globally replace digits or authorize ordinary number-only counters.
    if ([value hasSuffix:@"5"] && value.length > 1) {
        NSString *corrected = [[value substringToIndex:value.length - 1] stringByAppendingString:@"s"];
        if (ASGAdCountdownText(corrected)) return ASGActionAdCountdown;
    }
    return ASGActionNone;
}

NSString *ASGMeaning(ASGActionKind kind) {
    return kind == ASGActionSkip ? @"skip" : (kind == ASGActionCloseAd ? @"close_ad" : (kind == ASGActionAdCountdown ? @"ad_countdown" : nil));
}

unsigned ASGActionPriority(ASGActionKind kind) {
    if (kind == ASGActionSkip || kind == ASGActionCloseAd) return 0;
    return kind == ASGActionAdCountdown ? 1 : 2;
}

BOOL ASGUnsafeActionText(NSString *text) {
    NSString *value = ASGNormalizeText(text);
    for (NSString *word in @[@"登录", @"登入", @"注册", @"教程", @"设置", @"订单", @"账号", @"账户", @"支付",
                            @"购买", @"开通", @"会员", @"下一页", @"上一页", @"领取", @"详情", @"login", @"sign in",
                            @"tutorial", @"account", @"order", @"payment", @"purchase", @"next page", @"profile", @"skipper"])
        if ([value containsString:word]) return YES;
    return NO;
}

BOOL ASGExplicitAdText(NSString *text) {
    NSString *value = ASGNormalizeText(text);
    if (ASGActionForText(value) == ASGActionNone || ASGUnsafeActionText(value)) return NO;
    return [value containsString:@"广告"] || [value containsString:@"advert"] || [value containsString:@" ad"];
}

BOOL ASGArrowText(NSString *text) {
    NSString *value = ASGNormalizeText(text);
    return [value containsString:@">>"] && ![value containsString:@"跳过"] && ![value containsString:@"skip"];
}

NSInteger ASGCountdownSeconds(NSString *text) {
    NSString *value = ASGNormalizeText(text);
    if (ASGActionForText(value) == ASGActionNone || ASGUnsafeActionText(value)) return -1;
    static NSRegularExpression *pattern;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pattern = [NSRegularExpression regularExpressionWithPattern:@"(?<![0-9])[0-9]{1,2}(?![0-9])" options:0 error:NULL];
    });
    NSArray<NSTextCheckingResult *> *matches = [pattern matchesInString:value options:0 range:NSMakeRange(0, value.length)];
    if (!matches.count) return -1;
    NSInteger seconds = [[value substringWithRange:matches.firstObject.range] integerValue];
    for (NSTextCheckingResult *match in matches)
        if ([[value substringWithRange:match.range] integerValue] != seconds) return -1;
    // The same counter can be exposed by text, accessibilityLabel and accessibilityValue.
    return seconds;
}

BOOL ASGCountdownText(NSString *text) { return ASGCountdownSeconds(text) >= 0; }
NSString *ASGSkipMeaning(NSString *text) { return ASGSkipText(text) ? @"skip" : nil; }

BOOL ASGSkipIdentifier(NSString *identifier) {
    // Match original identifier discovery; negative evidence is checked separately before action.
    return [ASGNormalizeText(identifier) containsString:@"skip"];
}

BOOL ASGAdClass(NSString *name) {
    NSString *lower = name.lowercaseString;
    for (NSString *word in @[@"splashad", @"adsplash", @"splashadvert", @"launchad", @"appopenad"])
        if ([lower containsString:word]) return YES;
    return NO;
}

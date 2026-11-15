#import "SIConfigCodec.h"
#include <math.h>

static NSString *const SIConfigFormat = @"ayao.statusindicators.config";
static NSInteger const SIConfigVersion = 1;
static NSUInteger const SIConfigMaxBytes = 65536;

NSArray<NSString *> *SIConfigKeys(void) {
    return @[
        @"enabled", @"showVPN", @"showMute", @"showFocus", @"showSpeed", @"interval",
        @"vpnStyle", @"focusStyle", @"focusText", @"focusLabel", @"vpnX", @"vpnY", @"independentVPNSize", @"vpnSize", @"muteX", @"muteY", @"muteSize", @"focusX", @"focusY", @"focusSize",
        @"speedX", @"speedY", @"speedFont", @"speedMode", @"speedArrangement",
        @"speedPrecision", @"speedUnitStyle", @"speedShowUnit", @"speedArrows",
        @"speedUploadFirst", @"speedHideZero", @"speedZeroWhenInvalid",
        @"speedArrowGap", @"speedUnitGap", @"separateLandscape",
        @"centeredGroup", @"groupGap", @"speedGroupWidth",
        @"vpnXLandscape", @"vpnYLandscape", @"muteXLandscape", @"muteYLandscape", @"focusXLandscape", @"focusYLandscape", @"speedXLandscape", @"speedYLandscape",
        @"fontWeight", @"colorMode", @"opacity", @"customColor",
        @"separateLandscapeColor", @"colorModeLandscape", @"customColorLandscape"
    ];
}

static BOOL SIConfigKeyIsKnown(NSString *key) {
    return [SIConfigKeys() containsObject:key];
}

static BOOL SIConfigNumberInRange(NSNumber *value, double low, double high) {
    if (![value isKindOfClass:NSNumber.class]) return NO;
    if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NO;
    double number=value.doubleValue;
    return isfinite(number) && number >= low && number <= high;
}

static BOOL SIConfigBoolNumber(NSNumber *value) {
    if (![value isKindOfClass:NSNumber.class]) return NO;
    double number=value.doubleValue;
    return isfinite(number) && (number == 0.0 || number == 1.0);
}

static NSError *SIConfigError(NSString *message) {
    return [NSError errorWithDomain:@"StatusIndicators.Configuration" code:1
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

BOOL SIValidateConfigurationSettings(NSDictionary *settings, NSError **error) {
    if (error) *error = nil;
    if (![settings isKindOfClass:NSDictionary.class] || settings.count > SIConfigKeys().count) {
        if (error) *error=SIConfigError(@"配置内容不是有效的设置字典。");
        return NO;
    }
    NSSet *booleanKeys=[NSSet setWithArray:@[@"enabled", @"showVPN", @"showMute", @"showFocus", @"showSpeed", @"independentVPNSize", @"focusText", @"centeredGroup",
        @"speedShowUnit", @"speedArrows", @"speedUploadFirst", @"speedHideZero", @"speedZeroWhenInvalid",
        @"separateLandscape", @"separateLandscapeColor"]];
    NSSet *integerKeys=[NSSet setWithArray:@[@"vpnStyle", @"focusStyle", @"speedMode", @"speedArrangement", @"speedPrecision",
        @"speedUnitStyle", @"fontWeight", @"colorMode", @"colorModeLandscape"]];
    NSDictionary *ranges=@{
        @"interval": @[@1,@5], @"vpnStyle": @[@0,@3], @"focusStyle": @[@0,@5], @"vpnX": @[@0,@100], @"vpnY": @[@-25,@100],
        @"vpnSize": @[@6,@20], @"muteX": @[@0,@100], @"muteY": @[@-25,@100], @"muteSize": @[@6,@20], @"focusX": @[@0,@100], @"focusY": @[@-25,@100], @"focusSize": @[@6,@20],
        @"speedX": @[@0,@100], @"speedY": @[@-25,@100], @"speedFont": @[@6,@20],
        @"speedMode": @[@0,@2], @"speedArrangement": @[@0,@1], @"speedPrecision": @[@0,@2],
        @"speedUnitStyle": @[@0,@1], @"speedArrowGap": @[@0,@8], @"speedUnitGap": @[@0,@8],
        @"groupGap": @[@0,@30], @"speedGroupWidth": @[@12,@100],
        @"vpnXLandscape": @[@0,@100], @"vpnYLandscape": @[@-25,@100], @"muteXLandscape": @[@0,@100], @"muteYLandscape": @[@-25,@100], @"focusXLandscape": @[@0,@100], @"focusYLandscape": @[@-25,@100], @"speedXLandscape": @[@0,@100],
        @"speedYLandscape": @[@-25,@100], @"fontWeight": @[@0,@2], @"colorMode": @[@0,@3], @"colorModeLandscape": @[@0,@3], @"opacity": @[@0.2,@1]
    };
    for (NSString *key in settings) {
        if (![key isKindOfClass:NSString.class] || !SIConfigKeyIsKnown(key)) {
            if (error) *error=SIConfigError([NSString stringWithFormat:@"配置包含不支持的键：%@。",key]);
            return NO;
        }
        id value=settings[key];
        if ([booleanKeys containsObject:key]) {
            if (!SIConfigBoolNumber(value)) {
                if (error) *error=SIConfigError([NSString stringWithFormat:@"配置键 %@ 的类型无效。",key]);
                return NO;
            }
        } else if ([key isEqualToString:@"customColor"] || [key isEqualToString:@"customColorLandscape"]) {
            NSString *color=[value isKindOfClass:NSString.class] ? (NSString *)value : @"";
            NSString *hex=[color hasPrefix:@"#"] ? [color substringFromIndex:1] : color;
            NSCharacterSet *validHex=[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
            if (hex.length != 6 || [hex rangeOfCharacterFromSet:validHex.invertedSet].location != NSNotFound) {
                if (error) *error=SIConfigError(@"自定义颜色值无效，请使用六位十六进制颜色。");
                return NO;
            }
        } else if ([key isEqualToString:@"focusLabel"]) {
            if (![value isKindOfClass:NSString.class] || ((NSString *)value).length > 16) {
                if (error) *error=SIConfigError(@"专注文字最多 16 个字符。");
                return NO;
            }
        } else {
            NSArray *range=ranges[key];
            if (range.count != 2 || !SIConfigNumberInRange(value,[range[0] doubleValue],[range[1] doubleValue])) {
                if (error) *error=SIConfigError([NSString stringWithFormat:@"配置键 %@ 的类型或范围无效。",key]);
                return NO;
            }
            if ([integerKeys containsObject:key] && floor([value doubleValue]) != [value doubleValue]) {
                if (error) *error=SIConfigError([NSString stringWithFormat:@"配置键 %@ 必须是整数。",key]);
                return NO;
            }
            if ([key isEqualToString:@"vpnStyle"] && ![@[@0,@1,@2,@3] containsObject:value]) {
                if (error) *error=SIConfigError(@"VPN 样式值无效。");
                return NO;
            }
        }
    }
    return YES;
}

static NSDictionary *SIDefaultSettings(NSString *resourceDirectory, NSError **error) {
    NSMutableDictionary *defaults = [NSMutableDictionary dictionary];
    for (NSString *page in @[@"Root", @"VPN", @"Mute", @"Focus", @"Speed", @"Appearance", @"Landscape"]) {
        NSString *path = [resourceDirectory stringByAppendingPathComponent:[page stringByAppendingPathExtension:@"plist"]];
        NSData *raw = SIReadConfigurationURL([NSURL fileURLWithPath:path], error);
        id resource = raw ? [NSPropertyListSerialization propertyListWithData:raw options:NSPropertyListImmutable format:NULL error:error] : nil;
        id items = [resource isKindOfClass:NSDictionary.class] ? resource[@"items"] : nil;
        if (![items isKindOfClass:NSArray.class]) {
            if (error && !*error) *error = SIConfigError(@"设置资源不可读取，未导出。");
            return nil;
        }
        for (id item in items) {
            if (![item isKindOfClass:NSDictionary.class]) continue;
            NSString *key = item[@"key"];
            if ([key isKindOfClass:NSString.class] && SIConfigKeyIsKnown(key) && item[@"default"])
                defaults[key] = item[@"default"];
        }
    }
    // The running configuration inherits portrait positions if landscape keys are absent.
    for (NSString *key in SIConfigKeys()) {
        if ([key hasSuffix:@"Landscape"]) {
            NSString *portrait = [key substringToIndex:key.length-@"Landscape".length];
            if (defaults[portrait]) defaults[key] = defaults[portrait];
        }
    }
    if (defaults.count != SIConfigKeys().count || !SIValidateConfigurationSettings(defaults, error)) {
        if (error && !*error) *error = SIConfigError(@"设置资源缺少默认值，未导出。");
        return nil;
    }
    return defaults;
}

static NSDictionary *SINormalizedSettings(NSDictionary *settings) {
    NSMutableDictionary *result = [settings mutableCopy];
    // Historical half-shield value 2 is rendered as new shield 1; text value 3 stays 3.
    if ([result[@"vpnStyle"] isEqual:@2]) result[@"vpnStyle"] = @1;
    return result;
}

NSData *SIExportConfiguration(NSDictionary *current, NSString *resourceDirectory, NSError **error) {
    if (error) *error = nil;
    if (![current isKindOfClass:NSDictionary.class] || !resourceDirectory.length) {
        if (error) *error = SIConfigError(@"当前设置无效，未导出。");
        return nil;
    }
    NSDictionary *defaults = SIDefaultSettings(resourceDirectory, error);
    if (!defaults) return nil;
    NSMutableDictionary *settings = [defaults mutableCopy];
    for (NSString *key in SIConfigKeys()) {
        id value = current[key];
        if ([key hasSuffix:@"Landscape"] && !value) {
            NSString *portrait = [key substringToIndex:key.length-@"Landscape".length];
            value = current[portrait];
        }
        if (!value) continue;
        // Old numeric text fields can be stored as strings. Export canonical numbers,
        // but do not accept arbitrary arrays/dictionaries or silently discard bad keys.
        if ([defaults[key] isKindOfClass:NSNumber.class] && [value isKindOfClass:NSString.class]) {
            NSScanner *scanner = [NSScanner scannerWithString:value];
            double number = 0;
            if (![scanner scanDouble:&number] || !scanner.isAtEnd || !isfinite(number)) {
                if (error) *error = SIConfigError([NSString stringWithFormat:@"配置键 %@ 不是有效数字，未导出。", key]);
                return nil;
            }
            value = @(number);
        }
        settings[key] = value;
    }
    if (!SIValidateConfigurationSettings(settings, error)) return nil;
    NSDictionary *envelope = @{@"format": SIConfigFormat, @"version": @(SIConfigVersion),
        @"bundleID": @"ayao.statusindicators", @"exportedAt": NSDate.date,
        @"settings": SINormalizedSettings(settings)};
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:envelope
        format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
    if (!data || data.length > SIConfigMaxBytes) {
        if (error && !*error) *error = SIConfigError(@"配置文件过大，未导出。");
        return nil;
    }
    return data;
}

NSDictionary *SIImportConfiguration(NSData *data, NSError **error) {
    if (error) *error = nil;
    if (![data isKindOfClass:NSData.class] || !data.length || data.length > SIConfigMaxBytes) {
        if (error) *error = SIConfigError(@"无法读取配置文件或文件过大。");
        return nil;
    }
    id object = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:error];
    if (![object isKindOfClass:NSDictionary.class]
        || ![object[@"format"] isEqual:SIConfigFormat]
        || ![object[@"bundleID"] isEqual:@"ayao.statusindicators"]
        || ![object[@"version"] isKindOfClass:NSNumber.class]
        || CFGetTypeID((__bridge CFTypeRef)object[@"version"]) == CFBooleanGetTypeID()
        || [object[@"version"] doubleValue] != SIConfigVersion
        || ![object[@"settings"] isKindOfClass:NSDictionary.class]) {
        if (error) *error = SIConfigError(@"这不是兼容的 StatusIndicators 配置文件。");
        return nil;
    }
    NSDictionary *settings = object[@"settings"];
    if (!settings.count) {
        if (error) *error = SIConfigError(@"配置没有可导入的设置，当前配置未改变。");
        return nil;
    }
    if (!SIValidateConfigurationSettings(settings, error)) return nil;
    // Version 1 partial imports keep their original merge semantics: no defaults added.
    return SINormalizedSettings(settings);
}

NSData *SIReadConfigurationURL(NSURL *url, NSError **error) {
    if (error) *error = nil;
    NSNumber *regular = nil;
    if (!url.isFileURL || ![url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:error] || !regular.boolValue) {
        if (error && !*error) *error = SIConfigError(@"只能读取普通配置文件。");
        return nil;
    }
    NSInputStream *stream = [NSInputStream inputStreamWithURL:url];
    [stream open];
    NSMutableData *data = [NSMutableData data];
    uint8_t buffer[4096];
    while (data.length <= SIConfigMaxBytes) {
        NSUInteger limit = MIN(sizeof(buffer), SIConfigMaxBytes + 1 - data.length);
        NSInteger count = [stream read:buffer maxLength:limit];
        if (count < 0) {
            if (error) *error = stream.streamError ?: SIConfigError(@"无法读取配置文件。");
            [stream close]; return nil;
        }
        if (count == 0) break;
        [data appendBytes:buffer length:(NSUInteger)count];
    }
    [stream close];
    if (data.length > SIConfigMaxBytes) {
        if (error) *error = SIConfigError(@"配置文件超过 64 KiB，未读取全部内容。");
        return nil;
    }
    return data;
}

#import "SIRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CoreFoundation/CoreFoundation.h>
#import "../SISettingsStore.h"
#import "../SIConfiguration.h"

static NSString *const SIConfigFormat = @"ayao.statusindicators.config";
static NSInteger const SIConfigVersion = 1;
static NSUInteger const SIConfigMaxBytes = 65536;

static NSArray<NSString *> *SIConfigKeys(void) {
    return @[
        @"enabled", @"showVPN", @"showMute", @"showSpeed", @"interval",
        @"vpnStyle", @"vpnX", @"vpnY", @"independentVPNSize", @"vpnSize", @"speedX", @"speedY", @"speedFont", @"speedMode", @"speedArrangement",
        @"speedPrecision", @"speedUnitStyle", @"speedShowUnit", @"speedArrows",
        @"speedUploadFirst", @"speedHideZero", @"speedZeroWhenInvalid",
        @"speedArrowGap", @"speedUnitGap", @"separateLandscape",
        @"centeredGroup", @"groupGap", @"speedGroupWidth",
        @"vpnXLandscape", @"vpnYLandscape", @"muteXLandscape", @"muteYLandscape", @"speedXLandscape", @"speedYLandscape",
        @"fontWeight", @"colorMode", @"opacity", @"customColor"
    ];
}

static BOOL SIConfigKeyIsKnown(NSString *key) {
    return [SIConfigKeys() containsObject:key];
}

static BOOL SIConfigNumberInRange(NSNumber *value, double low, double high) {
    if (![value isKindOfClass:NSNumber.class]) return NO;
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

static BOOL SIValidateImportedSettings(NSDictionary *settings, NSError **error) {
    if (![settings isKindOfClass:NSDictionary.class] || settings.count > SIConfigKeys().count) {
        if (error) *error=SIConfigError(@"配置内容不是有效的设置字典。");
        return NO;
    }
    NSSet *booleanKeys=[NSSet setWithArray:@[@"enabled", @"showVPN", @"showMute", @"showSpeed", @"independentVPNSize", @"centeredGroup",
        @"speedShowUnit", @"speedArrows", @"speedUploadFirst", @"speedHideZero", @"speedZeroWhenInvalid",
        @"separateLandscape"]];
    NSSet *integerKeys=[NSSet setWithArray:@[@"vpnStyle", @"speedMode", @"speedArrangement", @"speedPrecision",
        @"speedUnitStyle", @"fontWeight", @"colorMode"]];
    NSDictionary *ranges=@{
        @"interval": @[@1,@5], @"vpnStyle": @[@0,@3], @"vpnX": @[@0,@100], @"vpnY": @[@-25,@100],
        @"vpnSize": @[@6,@20], @"muteX": @[@0,@100], @"muteY": @[@-25,@100], @"muteSize": @[@6,@20],
        @"speedX": @[@0,@100], @"speedY": @[@-25,@100], @"speedFont": @[@6,@20],
        @"speedMode": @[@0,@2], @"speedArrangement": @[@0,@1], @"speedPrecision": @[@0,@2],
        @"speedUnitStyle": @[@0,@1], @"speedArrowGap": @[@0,@8], @"speedUnitGap": @[@0,@8],
        @"groupGap": @[@0,@30], @"speedGroupWidth": @[@12,@100],
        @"vpnXLandscape": @[@0,@100], @"vpnYLandscape": @[@-25,@100], @"muteXLandscape": @[@0,@100], @"muteYLandscape": @[@-25,@100], @"speedXLandscape": @[@0,@100],
        @"speedYLandscape": @[@-25,@100], @"fontWeight": @[@0,@2], @"colorMode": @[@0,@3], @"opacity": @[@0.2,@1]
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
        } else if ([key isEqualToString:@"customColor"]) {
            NSString *color=[value isKindOfClass:NSString.class] ? (NSString *)value : @"";
            NSString *hex=[color hasPrefix:@"#"] ? [color substringFromIndex:1] : color;
            NSCharacterSet *validHex=[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
            if (hex.length != 6 || [hex rangeOfCharacterFromSet:validHex.invertedSet].location != NSNotFound) {
                if (error) *error=SIConfigError(@"自定义颜色值无效，请使用六位十六进制颜色。");
                return NO;
            }
        } else {
            NSArray *range=ranges[key];
            if ([integerKeys containsObject:key] && floor([value doubleValue]) != [value doubleValue]) {
                if (error) *error=SIConfigError([NSString stringWithFormat:@"配置键 %@ 必须是整数。",key]);
                return NO;
            }
            if (!SIConfigNumberInRange(value,[range[0] doubleValue],[range[1] doubleValue])) {
                if (error) *error=SIConfigError([NSString stringWithFormat:@"配置键 %@ 超出允许范围。",key]);
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

@implementation SISettingsListController
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    NSDictionary *settings=SIReadSettings();
    id value=settings[key];
    if (!value && [key hasSuffix:@"Landscape"]) value=settings[[key substringToIndex:key.length-@"Landscape".length]];
    value = value ?: [specifier propertyForKey:@"default"];
    if ([specifier propertyForKey:@"min"] && [specifier propertyForKey:@"max"])
        return [NSString stringWithFormat:@"%.2f",[value doubleValue]];
    return value;
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    if (!key.length || !value) return;
    id minimum=[specifier propertyForKey:@"min"], maximum=[specifier propertyForKey:@"max"];
    NSError *failure=nil;
    BOOL valid=YES;
    if (minimum && maximum) {
        NSScanner *scanner=[NSScanner scannerWithString:[value description]];
        double number=0;
        valid=[scanner scanDouble:&number] && scanner.isAtEnd && isfinite(number)
            && number >= [minimum doubleValue] && number <= [maximum doubleValue];
        value=@(number);
    }
    if (valid && SIWriteSettings(@{key:value},&failure)) return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"未保存" message:valid ? failure.localizedDescription :
        [NSString stringWithFormat:@"请输入 %@ 到 %@ 之间的数字。",minimum,maximum] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    [self reloadSpecifier:specifier];
}
@end

@implementation SIRootListController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers=[self loadSpecifiersFromPlistName:@"Root" target:self bundle:[NSBundle bundleForClass:SIRootListController.class]];
    return _specifiers;
}

- (void)showConfigurationError:(NSError *)error {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"配置操作失败"
        message:error.localizedDescription ?: @"文件无效，当前配置未改变。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)exportConfiguration {
    NSDictionary *current=SIReadSettings();
    NSMutableDictionary *settings=[NSMutableDictionary dictionary];
    for (NSString *key in SIConfigKeys()) {
        id value=current[key];
        if (value && ([value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class])) {
            // Export the old half-shield value as the new shield; preserve text value 3.
            settings[key]=[key isEqualToString:@"vpnStyle"] && [value integerValue]==2 ? @1 : value;
        }
    }
    NSDictionary *envelope=@{ @"format": SIConfigFormat, @"version": @(SIConfigVersion),
        @"bundleID": @"ayao.statusindicators", @"exportedAt": [NSDate date], @"settings": settings };
    NSError *error=nil;
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:envelope format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    if (!data || data.length > SIConfigMaxBytes) { [self showConfigurationError:error ?: SIConfigError(@"配置文件过大。")]; return; }
    NSDateFormatter *formatter=[NSDateFormatter new];
    formatter.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone=[NSTimeZone localTimeZone];
    formatter.dateFormat=@"yyyyMMdd-HHmmss";
    NSString *stamp=[formatter stringFromDate:[NSDate date]];
    NSString *unique=[NSUUID.UUID.UUIDString substringToIndex:8];
    NSString *filename=[NSString stringWithFormat:@"StatusIndicators-Configuration-%@-%@.plist",stamp,unique];
    NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:filename];
    if (![data writeToFile:path options:NSDataWritingAtomic error:&error]) { [self showConfigurationError:error]; return; }
    NSURL *url=[NSURL fileURLWithPath:path];
    UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    share.completionWithItemsHandler=^(__unused UIActivityType type, __unused BOOL completed, __unused NSArray *items, __unused NSError *activityError) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    };
    [self presentViewController:share animated:YES completion:nil];
}

- (void)importConfiguration {
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypePropertyList, UTTypeData] asCopy:YES];
    picker.delegate=self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url=urls.firstObject;
    if (!url) return;
    BOOL accessed=[url startAccessingSecurityScopedResource];
    NSData *data=[NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:NULL];
    if (accessed) [url stopAccessingSecurityScopedResource];
    if (!data || data.length > SIConfigMaxBytes) { [self showConfigurationError:SIConfigError(@"无法读取配置文件或文件过大。")]; return; }
    NSError *error=nil; NSPropertyListFormat format=NSPropertyListXMLFormat_v1_0;
    id object=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:&format error:&error];
    if (![object isKindOfClass:NSDictionary.class] || ![object[@"format"] isEqual:SIConfigFormat]
        || [object[@"version"] integerValue] != SIConfigVersion || ![object[@"bundleID"] isEqual:@"ayao.statusindicators"]
        || ![object[@"settings"] isKindOfClass:NSDictionary.class]) {
        [self showConfigurationError:SIConfigError(@"这不是兼容的 StatusIndicators 配置文件。")]; return;
    }
    NSDictionary *rawChanges=object[@"settings"];
    if (!SIValidateImportedSettings(rawChanges,&error)) { [self showConfigurationError:error]; return; }
    NSMutableDictionary *changes=[rawChanges mutableCopy];
    if ([changes[@"vpnStyle"] integerValue]==2) changes[@"vpnStyle"]=@1;
    NSString *message=[NSString stringWithFormat:@"将导入 %@ 项设置，并覆盖当前对应值。未包含的设置保持不变。",@(changes.count)];
    UIAlertController *confirm=[UIAlertController alertControllerWithTitle:@"确认导入" message:message preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"导入" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSError *failure=nil;
        if (!SIWriteSettings(changes,&failure)) [self showConfigurationError:failure];
        else [self reloadSpecifiers];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}
@end

@implementation SIOptionsListController
- (NSArray *)specifiers {
    if (!_specifiers) {
        NSString *page=[self.specifier propertyForKey:@"page"];
        if (![@[@"VPN",@"Mute",@"Speed",@"Appearance",@"Landscape"] containsObject:page]) page=@"Appearance";
        _specifiers=[self loadSpecifiersFromPlistName:page target:self bundle:[NSBundle bundleForClass:SIRootListController.class]];
    }
    return _specifiers;
}
@end

#import "SIRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CoreFoundation/CoreFoundation.h>
#import "../SISettingsStore.h"
#import "../SIConfiguration.h"
#import "SIConfigCodec.h"

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
    if (valid && SIValidateConfigurationSettings(@{key:value},&failure) && SIWriteSettings(@{key:value},&failure)) return;
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
    NSError *error=nil;
    NSString *resources=[NSBundle bundleForClass:SIRootListController.class].resourcePath;
    NSData *data=SIExportConfiguration(SIReadSettings(),resources,&error);
    if (!data) { [self showConfigurationError:error]; return; }
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
    if (share.popoverPresentationController) {
        share.popoverPresentationController.sourceView=self.view;
        share.popoverPresentationController.sourceRect=CGRectMake(CGRectGetMidX(self.view.bounds),CGRectGetMidY(self.view.bounds),1,1);
    }
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
    NSError *error=nil;
    BOOL accessed=[url startAccessingSecurityScopedResource];
    NSData *data=SIReadConfigurationURL(url,&error);
    if (accessed) [url stopAccessingSecurityScopedResource];
    if (!data) { [self showConfigurationError:error]; return; }
    NSDictionary *changes=SIImportConfiguration(data,&error);
    if (!changes) { [self showConfigurationError:error]; return; }
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
        if (![@[@"VPN",@"Mute",@"Focus",@"Speed",@"Appearance",@"Landscape"] containsObject:page]) page=@"Appearance";
        _specifiers=[self loadSpecifiersFromPlistName:page target:self bundle:[NSBundle bundleForClass:SIRootListController.class]];
    }
    return _specifiers;
}
@end

#import "../Preferences/SIConfigCodec.h"
#import "../SISettingsStore.h"
#import <notify.h>
#include <assert.h>
#include <sys/stat.h>

static NSData *Envelope(id settings, id version, NSPropertyListFormat format) {
    return [NSPropertyListSerialization dataWithPropertyList:@{
        @"format": @"ayao.statusindicators.config", @"version": version,
        @"bundleID": @"ayao.statusindicators", @"settings": settings
    } format:format options:0 error:NULL];
}
static void Reject(NSData *data) {
    NSError *error=nil;
    assert(!SIImportConfiguration(data,&error) && error);
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        assert(argc==2 && NSThread.isMainThread);
        NSString *resources=[NSString stringWithUTF8String:argv[1]];
        NSError *error=nil;
        NSDictionary *original=@{@"muteX": @73, @"muteY": @80, @"muteSize": @18,
            @"focusX": @25, @"focusY": @37, @"vpnX": @29, @"vpnXLandscape": @61,
            @"vpnStyle": @2, @"speedFont": @"12.5", @"focusLabel": @"工作",
            @"unrelated": @"must not export", @"legacyUnused": @1};
        NSData *exported=SIExportConfiguration(original,resources,&error);
        assert(exported && !error && exported.length<=65536);
        assert([[@"<?xml" dataUsingEncoding:NSUTF8StringEncoding] isEqual:[exported subdataWithRange:NSMakeRange(0,5)]]);
        NSDictionary *decoded=SIImportConfiguration(exported,&error);
        assert(decoded && !error && decoded.count==SIConfigKeys().count);
        assert([decoded[@"muteX"] isEqual:@73] && [decoded[@"muteY"] isEqual:@80] && [decoded[@"muteSize"] isEqual:@18]);
        assert([decoded[@"focusXLandscape"] isEqual:@25] && [decoded[@"focusYLandscape"] isEqual:@37]);
        assert([decoded[@"vpnXLandscape"] isEqual:@61] && [decoded[@"speedFont"] isEqual:@12.5]);
        assert([decoded[@"vpnStyle"] isEqual:@1] && [original[@"vpnStyle"] isEqual:@2]);
        assert(!decoded[@"unrelated"] && !decoded[@"legacyUnused"]);
        NSDictionary *defaults=SIImportConfiguration(SIExportConfiguration(@{},resources,&error),&error);
        assert(defaults.count==SIConfigKeys().count && [defaults[@"enabled"] isEqual:@NO]);
        assert([defaults[@"showVPN"] isEqual:@YES] && [defaults[@"focusLabel"] isEqual:@"专注"]);
        assert([defaults[@"separateLandscapeColor"] isEqual:@NO]);
        assert([defaults[@"colorModeLandscape"] isEqual:defaults[@"colorMode"]]);
        NSDictionary *landscapeColors=@{@"colorMode":@2,@"customColor":@"#123456",
            @"separateLandscapeColor":@YES,@"colorModeLandscape":@1,@"customColorLandscape":@"#ABCDEF"};
        NSDictionary *colorRoundTrip=SIImportConfiguration(SIExportConfiguration(landscapeColors,resources,&error),&error);
        for (NSString *key in landscapeColors) assert([colorRoundTrip[key] isEqual:landscapeColors[key]]);
        NSDictionary *inherited=SIImportConfiguration(SIExportConfiguration(@{@"colorMode":@3,@"customColor":@"#AABBCC"},resources,&error),&error);
        assert([inherited[@"colorModeLandscape"] isEqual:@3] && [inherited[@"customColorLandscape"] isEqual:@"#AABBCC"]);
        assert(!SIValidateConfigurationSettings(@{@"focusLabel":@"12345678901234567"},&error) && error);
        assert(!SIValidateConfigurationSettings(@{@"speedPrecision":@1.5},&error) && error);
        assert(SIValidateConfigurationSettings(@{@"muteSize":@12.5},&error) && !error);

        // Resource UI keys and export whitelist must stay in lockstep.
        for (NSString *page in @[@"Root",@"VPN",@"Mute",@"Focus",@"Speed",@"Appearance",@"Landscape"]) {
            NSData *raw=SIReadConfigurationURL([NSURL fileURLWithPath:[resources stringByAppendingPathComponent:[page stringByAppendingPathExtension:@"plist"]]],&error);
            NSDictionary *resource=[NSPropertyListSerialization propertyListWithData:raw options:0 format:NULL error:NULL];
            for (NSDictionary *item in resource[@"items"]) if (item[@"key"]) assert([SIConfigKeys() containsObject:item[@"key"]]);
            if ([page isEqual:@"Landscape"]) {
                NSMutableDictionary *groups=[NSMutableDictionary dictionary];
                NSString *group=nil;
                for (NSDictionary *item in resource[@"items"]) {
                    if ([item[@"cell"] isEqual:@"PSGroupCell"]) {
                        group=item[@"label"]; groups[group]=[NSMutableArray array];
                    } else if (item[@"key"] && group) [groups[group] addObject:item[@"key"]];
                }
                assert([groups[@"VPN 横屏位置"] isEqual:(@[@"vpnXLandscape",@"vpnYLandscape"])]);
                assert([groups[@"网速 横屏位置"] isEqual:(@[@"speedXLandscape",@"speedYLandscape"])]);
                assert([groups[@"总静音 横屏位置"] isEqual:(@[@"muteXLandscape",@"muteYLandscape"])]);
                assert([groups[@"专注模式 横屏位置"] isEqual:(@[@"focusXLandscape",@"focusYLandscape"])]);
            }
        }
        for (unsigned binary=0;binary<2;binary++) {
            NSPropertyListFormat format=binary ? NSPropertyListBinaryFormat_v1_0 : NSPropertyListXMLFormat_v1_0;
            NSDictionary *partial=SIImportConfiguration(Envelope(@{@"vpnStyle":@2,@"muteX":@91},@1,format),&error);
            assert(partial.count==2 && [partial[@"vpnStyle"] isEqual:@1] && [partial[@"muteX"] isEqual:@91]);
            assert(!partial[@"enabled"] && !partial[@"focusYLandscape"]); // Version 1 partial merge unchanged.
            assert(!partial[@"separateLandscapeColor"] && !partial[@"colorModeLandscape"]);
            NSDictionary *colorPartial=SIImportConfiguration(Envelope(@{@"separateLandscapeColor":@YES,@"colorModeLandscape":@1},@1,format),&error);
            assert(colorPartial.count==2 && !colorPartial[@"colorMode"] && !colorPartial[@"customColor"]);
            Reject(Envelope(@{@"colorModeLandscape":@4},@1,format));
            Reject(Envelope(@{@"colorModeLandscape":@1.5},@1,format));
            Reject(Envelope(@{@"customColorLandscape":@"#INVALID"},@1,format));
            Reject(Envelope(@{@"separateLandscapeColor":@2},@1,format));
            for (id version in @[@[],@{},@"1",@YES,@1.5,@2]) Reject(Envelope(@{@"enabled":@YES},version,format));
            for (id invalid in @[@[],@{},@"1",@YES]) {
                Reject(Envelope(@{@"focusStyle":invalid},@1,format));
            }
            Reject(Envelope(@{@"focusStyle":@1.5},@1,format));
            Reject(Envelope(@{@"showMute":@2},@1,format));
            Reject(Envelope(@{@"muteSize":@21},@1,format));
            Reject(Envelope(@{@"unknownKey":@1},@1,format));
            Reject(Envelope(@{@"customColor":@"#xyzxyz"},@1,format));
            Reject(Envelope(@{@"focusLabel":@"12345678901234567"},@1,format));
            Reject(Envelope(@{},@1,format));
            Reject(Envelope(@[],@1,format));
            for (NSString *key in SIConfigKeys()) {
                Reject(Envelope(@{key:@[]},@1,format));
                Reject(Envelope(@{key:@{}},@1,format));
            }
        }
        Reject(Envelope(@{@"speedFont":@(NAN)},@1,NSPropertyListXMLFormat_v1_0));
        Reject(Envelope(@{@"speedFont":@(INFINITY)},@1,NSPropertyListBinaryFormat_v1_0));
        NSMutableDictionary *wrongEnvelope=[@{@"format":@[],@"version":@1,@"bundleID":@"ayao.statusindicators",@"settings":@{@"enabled":@YES}} mutableCopy];
        Reject([NSPropertyListSerialization dataWithPropertyList:wrongEnvelope format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL]);
        wrongEnvelope[@"format"]=@"ayao.statusindicators.config";wrongEnvelope[@"bundleID"]=@"other.plugin";
        Reject([NSPropertyListSerialization dataWithPropertyList:wrongEnvelope format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL]);
        Reject([@"not a plist" dataUsingEncoding:NSUTF8StringEncoding]);
        Reject([NSMutableData dataWithLength:65537]);
        for (NSDictionary *invalid in @[@{@"speedFont":@"bad"},@{@"muteX":@[]},@{@"showMute":@2},@{@"focusStyle":@1.5}]) {
            error=nil;assert(!SIExportConfiguration(invalid,resources,&error) && error);
        }

        NSString *folder=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        assert([NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL]);
        NSString *path=[folder stringByAppendingPathComponent:@"current.plist"];
        SISetTestSettingsPath(path);
        NSData *raw=[NSPropertyListSerialization dataWithPropertyList:@{@"enabled":@NO,@"unrelated":@"preserve"}
            format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
        assert([raw writeToFile:path atomically:YES]);chmod(path.fileSystemRepresentation,0600);
        int token=-1,notified=0;assert(!notify_register_check("ayao.statusindicators/preferences.changed",&token));notify_check(token,&notified);
        // Invalid input/cancelled valid preview has no persistence or notification side effects.
        Reject(Envelope(@{@"focusStyle":@[]},@1,NSPropertyListXMLFormat_v1_0));
        assert(SIImportConfiguration(exported,&error));
        assert([[NSData dataWithContentsOfFile:path] isEqual:raw]);
        assert(!notify_check(token,&notified) && !notified);
        assert(SIWriteSettings(decoded,&error));
        NSDictionary *saved=SIReadSettings();assert([saved[@"unrelated"] isEqual:@"preserve"]);
        for (NSString *key in SIConfigKeys()) assert([saved[key] isEqual:decoded[key]]);
        NSPropertyListFormat actual=0;
        [NSPropertyListSerialization propertyListWithData:[NSData dataWithContentsOfFile:path] options:0 format:&actual error:NULL];
        assert(actual==NSPropertyListBinaryFormat_v1_0);
        assert([[NSData dataWithContentsOfFile:[path stringByAppendingString:@".si-last-good"]] isEqual:raw]);
        assert(!notify_check(token,&notified) && notified);notify_cancel(token);
        NSURL *file=[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:@"export.plist"]];
        assert([exported writeToURL:file atomically:YES]);assert([SIReadConfigurationURL(file,&error) isEqual:exported]);
        assert(!SIReadConfigurationURL([NSURL fileURLWithPath:folder],&error));
        assert(!SIReadConfigurationURL([NSURL URLWithString:@"https://example.invalid/config"],&error));
        assert([[NSMutableData dataWithLength:65537] writeToURL:file atomically:YES]);
        assert(!SIReadConfigurationURL(file,&error) && error);
        assert([[NSMutableData dataWithLength:65536] writeToURL:file atomically:YES]);
        assert(SIReadConfigurationURL(file,&error).length==65536);
        assert(!SIExportConfiguration(@{},folder,&error));
        [NSFileManager.defaultManager removeItemAtPath:folder error:NULL];
        printf("PASS config codec: %lu complete keys, resource coverage, XML/binary and partial v1, malformed types, canonical export, bounded file reads, atomic merge/backup/notify\n",(unsigned long)decoded.count);
    }
    return 0;
}

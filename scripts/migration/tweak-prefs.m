#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

@interface NSUserDefaults (MigrationContainerPreferences)
- (instancetype)_initWithSuiteName:(NSString *)suiteName container:(NSURL *)container;
@end

static BOOL appDomain(NSString *domain) {
    return [@[@"com.tencent.xin", @"com.wechat.wechattweak",
              @"com.ss.iphone.ugc.Aweme"] containsObject:domain];
}

static BOOL appKey(NSString *domain, NSString *key) {
    if ([domain isEqualToString:@"com.ss.iphone.ugc.Aweme"])
        return [key hasPrefix:@"DYYY"];
    if ([domain isEqualToString:@"com.tencent.xin"])
        return [key hasPrefix:@"DT"] || [key hasPrefix:@"DA_Voice"] ||
               [key hasPrefix:@"DumpApp"] || [key hasPrefix:@"MIs"] ||
               [key hasPrefix:@"MY"] || [@[
                   @"MAllGroupUndenoKey", @"MAutoReplyOnlineTimeKey",
                   @"MChatGPTSystemMessageKey", @"MFastJumpVideoKey",
                   @"MFriendGroupNameKey", @"MMessagePreviewKey",
                   @"MMsgDateFontSizeKey", @"MMsgDateFormatKey",
                   @"MOpenAIChatModelKey", @"MOpenRoomEnableKey",
                   @"MQuitMonitorEnableKey", @"MRedDetailEnableKey",
                   @"MRedMessageTipsKey", @"MSendToGroupDelayeKey",
                   @"MVoiceJiaYiKey", @"MVoiceTimeKey", @"MWelcomeGroupContentKey"
               ] containsObject:key];
    // The separate tweak suite contains no native WeChat preferences.
    return [domain isEqualToString:@"com.wechat.wechattweak"];
}

// Standalone preferences API client. No injection, process attachment, or
// background work. App/account domains and jailbreak policy are not allowed.
static BOOL allowed(NSString *domain) {
    return [@[
        @"ayao.aipowerbutton", @"ayao.airpodsautonoise",
        @"ayao.lockaudioprofiles", @"ayao.locklowpower",
        @"ayao.photosrecentssort", @"ch.xxtou.hudapp",
        @"com.netskao.autofaceunlock", @"com.ichitaso.primalfolder2",
        @"com.imkpatil.letmeknow", @"com.lclrc.squidgestureprefs",
        @"com.p2kdev.quitall", @"com.p2kdev.tinge", @"com.p2kdev.waqt",
        @"com.nightwind.boldersrebornprefs", @"com.ichitaso.iconorder",
        @"com.25mao.leftPanPrefs", @"com.tigisoftware.Filza"
    ] containsObject:domain];
}

static BOOL filzaKey(NSString *key) {
    return [@[@"open-behavior", @"display-permission", @"zipviewer-extractlocation",
        @"scrolling-speed", @"imageviewer-background", @"display-folder-detail",
        @"small-font-size", @"hidden-files", @"unzip-create-folder", @"font-size",
        @"theme", @"display-size", @"syntax-highlight", @"allow-cloud-viewers",
        @"show-context-menu", @"sort-buttons", @"use-trash", @"FixedLanguage",
        @"edit-font", @"folder-on-top", @"top-toolbar", @"enable-recents",
        @"icon-theme"] containsObject:key];
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc < 3) return 2;
        NSString *domain = @(argv[2]);
        if (!strcmp(argv[1], "container-read") || !strcmp(argv[1], "container-apply")) {
            if (argc < 4 || !appDomain(domain)) return 2;
            NSString *path = @(argv[3]);
            if (![path hasPrefix:@"/private/var/mobile/Containers/Data/Application/"] ||
                [path containsString:@".."] ||
                ![NSUserDefaults instancesRespondToSelector:@selector(_initWithSuiteName:container:)])
                return 2;
            NSUserDefaults *defaults = [[NSUserDefaults alloc]
                _initWithSuiteName:domain container:[NSURL fileURLWithPath:path isDirectory:YES]];
            if (!defaults) return 2;
            if (!strcmp(argv[1], "container-apply") && argc == 5) {
                NSDictionary *patch = [NSDictionary dictionaryWithContentsOfFile:@(argv[4])];
                NSDictionary *values = patch[@"set"];
                NSArray *remove = patch[@"remove"];
                if (![values isKindOfClass:NSDictionary.class] ||
                    ![remove isKindOfClass:NSArray.class]) return 2;
                for (NSString *key in values) if (!appKey(domain, key)) return 2;
                for (NSString *key in remove) if (!appKey(domain, key)) return 2;
                for (NSString *key in values) [defaults setObject:values[key] forKey:key];
                for (NSString *key in remove) [defaults removeObjectForKey:key];
                if (![defaults synchronize]) return 1;
            } else if (strcmp(argv[1], "container-read") || argc != 4) return 2;
            NSDictionary *raw = defaults.dictionaryRepresentation;
            NSMutableDictionary *selected = [NSMutableDictionary dictionary];
            for (NSString *key in raw) if (appKey(domain, key)) selected[key] = raw[key];
            NSData *output = [NSPropertyListSerialization dataWithPropertyList:selected
                format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
            return output && fwrite(output.bytes, 1, output.length, stdout) == output.length ? 0 : 1;
        }
        if (!allowed(domain)) return 2;
        if ((!strcmp(argv[1], "iconorder-disk-only") || !strcmp(argv[1], "springboard-layout-read")) && argc == 3 &&
            [domain isEqualToString:@"com.ichitaso.iconorder"]) {
            NSString *home = NSHomeDirectory();
            if (![home hasPrefix:@"/var/containers/Bundle/Application/.jbroot-"] ||
                ![home hasSuffix:@"/var/mobile"]) return 2;
            NSString *path = !strcmp(argv[1], "springboard-layout-read") ?
                @"/private/var/mobile/Library/SpringBoard/IconState.plist" :
                [home stringByAppendingPathComponent:@"Library/Preferences/com.ichitaso.iconorder.plist"];
            NSDictionary *disk = [NSDictionary dictionaryWithContentsOfFile:path];
            if (![disk isKindOfClass:NSDictionary.class]) return 1;
            NSData *data = [NSPropertyListSerialization dataWithPropertyList:disk
                format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
            return data && fwrite(data.bytes, 1, data.length, stdout) == data.length ? 0 : 1;
        }
        if (!strcmp(argv[1], "preserve-domain-xml") && argc == 3 &&
            ![domain isEqualToString:@"com.ichitaso.iconorder"] &&
            ![domain isEqualToString:@"com.tigisoftware.Filza"]) {
            NSString *home = NSHomeDirectory();
            if (![home hasPrefix:@"/var/containers/Bundle/Application/.jbroot-"] ||
                ![home hasSuffix:@"/var/mobile"]) return 2;
            NSString *path = [home stringByAppendingPathComponent:
                [@"Library/Preferences/" stringByAppendingString:[domain stringByAppendingString:@".plist"]]];
            NSDictionary *values = CFBridgingRelease(CFPreferencesCopyMultiple(NULL,
                (__bridge CFStringRef)domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
            if (![values isKindOfClass:NSDictionary.class] ||
                ![values writeToFile:path atomically:YES]) return 1;
            NSDictionary *disk = [NSDictionary dictionaryWithContentsOfFile:path];
            if (![disk isEqualToDictionary:values]) return 1;
            NSData *data = [NSPropertyListSerialization dataWithPropertyList:disk
                format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
            return data && fwrite(data.bytes, 1, data.length, stdout) == data.length ? 0 : 1;
        }
        if ((!strcmp(argv[1], "iconorder-xml") || !strcmp(argv[1], "iconorder-disk-read")) && argc == 3 &&
            [domain isEqualToString:@"com.ichitaso.iconorder"]) {
            NSString *home = NSHomeDirectory();
            if (![home hasPrefix:@"/var/containers/Bundle/Application/.jbroot-"] ||
                ![home hasSuffix:@"/var/mobile"]) return 2;
            NSString *path = [home stringByAppendingPathComponent:
                @"Library/Preferences/com.ichitaso.iconorder.plist"];
            NSDictionary *values = CFBridgingRelease(CFPreferencesCopyMultiple(NULL,
                (__bridge CFStringRef)domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
            if (![values isKindOfClass:NSDictionary.class] ||
                ![values[@"IconOrder"] isKindOfClass:NSDictionary.class]) return 2;
            // IconOrder's consumer uses dictionaryWithContentsOfFile and
            // writeToFile:atomically:. Preserve its native XML semantics,
            // including folder names not accepted by strict external parsers.
            if (!strcmp(argv[1], "iconorder-xml") &&
                ![values writeToFile:path atomically:YES]) return 1;
            NSDictionary *disk = [NSDictionary dictionaryWithContentsOfFile:path];
            if (![disk isEqualToDictionary:values]) return 1;
            NSData *data = [NSPropertyListSerialization dataWithPropertyList:disk
                format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
            return data && fwrite(data.bytes, 1, data.length, stdout) == data.length ? 0 : 1;
        }
        fprintf(stderr, "uid=%u home=%s fixed_home=%s\n", getuid(),
            NSHomeDirectory().UTF8String, getenv("CFFIXED_USER_HOME") ?: "unset");
        if (!strcmp(argv[1], "apply") && argc == 4) {
            NSDictionary *patch = [NSDictionary dictionaryWithContentsOfFile:@(argv[3])];
            if (![patch[@"set"] isKindOfClass:NSDictionary.class] ||
                ![patch[@"remove"] isKindOfClass:NSArray.class]) return 2;
            if ([domain isEqualToString:@"com.tigisoftware.Filza"]) {
                for (NSString *key in patch[@"set"]) if (!filzaKey(key)) return 2;
                for (NSString *key in patch[@"remove"]) if (!filzaKey(key)) return 2;
            }
            CFPreferencesSetMultiple((__bridge CFDictionaryRef)patch[@"set"],
                (__bridge CFArrayRef)patch[@"remove"], (__bridge CFStringRef)domain,
                kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            if (!CFPreferencesSynchronize((__bridge CFStringRef)domain,
                kCFPreferencesCurrentUser, kCFPreferencesAnyHost)) return 1;
        } else if (strcmp(argv[1], "read") || argc != 3) return 2;
        NSDictionary *values = CFBridgingRelease(CFPreferencesCopyMultiple(NULL,
            (__bridge CFStringRef)domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
        if ([domain isEqualToString:@"com.tigisoftware.Filza"]) {
            NSMutableDictionary *selected = [NSMutableDictionary dictionary];
            for (NSString *key in values) if (filzaKey(key)) selected[key] = values[key];
            values = selected;
        }
        NSData *output = [NSPropertyListSerialization dataWithPropertyList:values ?: @{}
            format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        return output && fwrite(output.bytes, 1, output.length, stdout) == output.length ? 0 : 1;
    }
}

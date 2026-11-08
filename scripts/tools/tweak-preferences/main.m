#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <notify.h>

@interface NSUserDefaults (ContainerPreferences)
- (instancetype)_initWithSuiteName:(NSString *)suiteName container:(NSURL *)container;
@end

static BOOL AllowedDomain(NSString *domain) {
    return [@[
        @"com.25mao.leftPanPrefs", @"com.p2kdev.waqt",
        @"ayao.photosrecentssort", @"com.ichitaso.primalfolder2",
        @"com.netskao.autofaceunlock", @"com.0xkuj.3dappversionspoofer",
        @"com.tencent.xin", @"com.wechat.wechattweak",
        @"com.ss.iphone.ugc.Aweme"
    ] containsObject:domain];
}

static BOOL AllowedKey(NSString *domain, NSString *key) {
    if ([domain isEqualToString:@"com.tencent.xin"]) {
        return [key hasPrefix:@"DT"] || [key hasPrefix:@"DA_Voice"] ||
            [key isEqualToString:@"DumpAppShow"] || [@[
                @"MRedMessageTipsKey", @"MYPatTipsEnabledKey", @"MYRightSearchItemKey",
                @"MOpenRoomEnableKey", @"MIsMessageTimeKey", @"MQuitMonitorEnableKey",
                @"MIsShowUserNameKey", @"MIsHideModeKey", @"MMessagePreviewKey",
                @"MMsgDateFontSizeKey", @"MMsgDateFormatKey", @"MIsOriginalImageKey",
                @"MIsOpenBrandNewEnableKey", @"MYWeAppJumpEnabledKey",
                @"MIsMsgGestureEnbaleKey", @"MIsSessionGestureKey", @"MIsSpotlightSearchKey",
                @"MIsMultiplechoiceChatKey", @"MIsAtAllUserKey", @"MIsForwardVoiceKey",
                @"MIsChatRoomAdminKey", @"MYImageCountKey", @"MIsIsLargeVideoFileKey",
                @"MRedDetailEnableKey", @"MIsVoiceToMP3FileKey", @"MIsRevokeMsgKey",
                @"MVoiceTimeKey", @"MYToOriginalMsgKey", @"MIsCallkitKey",
                @"MIsLineBottomToolKey", @"MAllGroupUndenoKey", @"MFastJumpVideoKey",
                @"MIsDoubleTapEnbaleKey", @"MIsLinkToSafariKey", @"MIsUnSendTypingKey",
                @"MIsRecentForwardKey", @"MIsMsgGestureRightEnbaleKey", @"MIsHideFriendKey",
                @"MIsTextFoldKey", @"MSendToGroupDelayeKey", @"MVoiceJiaYiKey",
                @"MIsVideoDownKey", @"MYMultiplexEnabledKey"
            ] containsObject:key];
    }
    if ([domain isEqualToString:@"com.ss.iphone.ugc.Aweme"]) {
        return [key hasPrefix:@"DYYY"];
    }
    return YES;
}

static NSDictionary *ReadDomain(NSString *domain) {
    NSDictionary *values = CFBridgingRelease(CFPreferencesCopyMultiple(
        NULL, (__bridge CFStringRef)domain,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    NSMutableDictionary *selected = [NSMutableDictionary dictionary];
    for (NSString *key in values) {
        if (AllowedKey(domain, key)) {
            selected[key] = values[key];
        }
    }
    return selected;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 3 && strcmp(argv[1], "notify") == 0) {
            NSString *name = [NSString stringWithUTF8String:argv[2]];
            if (![name containsString:@"preferences"] &&
                ![name containsString:@"settingschanged"]) {
                return 2;
            }
            return notify_post(argv[2]) == NOTIFY_STATUS_OK ? 0 : 1;
        }
        if (argc < 3) {
            return 2;
        }
        NSString *operation = [NSString stringWithUTF8String:argv[1]];
        NSString *domain = [NSString stringWithUTF8String:argv[2]];
        if (!AllowedDomain(domain)) {
            return 2;
        }
        if ([operation hasPrefix:@"container-"]) {
            if (argc < 4 || ![@[@"com.tencent.xin", @"com.wechat.wechattweak",
                @"com.ss.iphone.ugc.Aweme"] containsObject:domain]) {
                return 2;
            }
            NSURL *container = [NSURL fileURLWithPath:
                [NSString stringWithUTF8String:argv[3]] isDirectory:YES];
            if (![NSUserDefaults instancesRespondToSelector:@selector(_initWithSuiteName:container:)]) {
                return 2;
            }
            NSUserDefaults *defaults = [[NSUserDefaults alloc] _initWithSuiteName:domain container:container];
            if ([operation isEqualToString:@"container-apply"] && argc == 5) {
                NSData *data = [NSData dataWithContentsOfFile:
                    [NSString stringWithUTF8String:argv[4]]];
                if (!data) {
                    return 2;
                }
                NSDictionary *patch = [NSPropertyListSerialization propertyListWithData:data
                    options:NSPropertyListImmutable format:NULL error:NULL];
                NSDictionary *values = patch[@"set"];
                NSArray *removed = patch[@"remove"];
                if (![values isKindOfClass:[NSDictionary class]] ||
                    ![removed isKindOfClass:[NSArray class]]) {
                    return 2;
                }
                for (NSString *key in values) {
                    if (!AllowedKey(domain, key)) {
                        return 2;
                    }
                }
                for (NSString *key in removed) {
                    if (!AllowedKey(domain, key)) {
                        return 2;
                    }
                }
                for (NSString *key in values) {
                    [defaults setObject:values[key] forKey:key];
                }
                for (NSString *key in removed) {
                    [defaults removeObjectForKey:key];
                }
                if (![defaults synchronize]) {
                    return 1;
                }
            } else if (![operation isEqualToString:@"container-read"] || argc != 4) {
                return 2;
            }
            NSDictionary *values = [defaults dictionaryRepresentation];
            NSMutableDictionary *selected = [NSMutableDictionary dictionary];
            for (NSString *key in values) {
                if (AllowedKey(domain, key)) {
                    selected[key] = values[key];
                }
            }
            NSData *output = [NSPropertyListSerialization dataWithPropertyList:selected
                format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
            return output && fwrite(output.bytes, 1, output.length, stdout) == output.length ? 0 : 1;
        }
        if ([operation isEqualToString:@"apply"] && argc == 4) {
            NSString *path = [NSString stringWithUTF8String:argv[3]];
            NSData *data = [NSData dataWithContentsOfFile:path];
            if (!data) {
                return 2;
            }
            NSDictionary *patch = [NSPropertyListSerialization propertyListWithData:data
                options:NSPropertyListImmutable format:NULL error:NULL];
            if (![patch isKindOfClass:[NSDictionary class]]) {
                return 2;
            }
            NSDictionary *values = patch[@"set"];
            NSArray *removed = patch[@"remove"];
            if (![values isKindOfClass:[NSDictionary class]] ||
                ![removed isKindOfClass:[NSArray class]]) {
                return 2;
            }
            for (NSString *key in values) {
                if (!AllowedKey(domain, key)) {
                    return 2;
                }
            }
            for (NSString *key in removed) {
                if (!AllowedKey(domain, key)) {
                    return 2;
                }
            }
            CFPreferencesSetMultiple((__bridge CFDictionaryRef)values,
                (__bridge CFArrayRef)removed, (__bridge CFStringRef)domain,
                kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            if (!CFPreferencesSynchronize((__bridge CFStringRef)domain,
                kCFPreferencesCurrentUser, kCFPreferencesAnyHost)) {
                return 1;
            }
        } else if (![operation isEqualToString:@"read"] || argc != 3) {
            return 2;
        }
        NSData *output = [NSPropertyListSerialization dataWithPropertyList:ReadDomain(domain)
            format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
        if (!output) {
            return 1;
        }
        return fwrite(output.bytes, 1, output.length, stdout) == output.length ? 0 : 1;
    }
}

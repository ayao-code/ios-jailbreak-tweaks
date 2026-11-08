#import <Foundation/Foundation.h>
#ifdef FC_FIXTURE
#import "checks/FixtureUIKit.h"
#else
#import <UIKit/UIKit.h>
#endif
#import <objc/message.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <sys/utsname.h>
#import <string.h>
#import "CoverPolicy.h"

extern void MSHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original);

// Intentionally MRC: host ARC codegen introduces newer runtime imports.
// All context references borrow objects retained by the caller stack.
typedef struct FCCall {
    id view;
    id icon;
    id cache;
    id layout;
    double side;
    BOOL rendering;
    struct FCCall *previous;
} FCCall;

static __thread FCCall *activeCall;
static __thread BOOL rebuilding;
static BOOL coverEnabled;
static NSString *preferencesPath;
static double coverSide;
static Class folderViewClass, folderIconClass, rootFolderClass, gridImageClass, listModelClass;
static const void *homeFolderKey = &homeFolderKey;
static const void *failedRepairKey = &failedRepairKey;

// Exported, content-free counters for an external read-only verification.
// All increments happen on the desktop main thread; no telemetry or polling.
__attribute__((visibility("default"))) uint64_t FCCounters[8];
// installed, home assignments, generation, size, rect, cell, rebuild, failure

static id GetObjectIvar(id object, const char *name) {
    if (!object) return nil;
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    const char *encoding = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    return encoding && encoding[0] == '@' ? object_getIvar(object, ivar) : nil;
}

static id CallObject(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static BOOL IsHomeFolder(id icon, NSString *location) {
    if (![NSThread isMainThread] || !coverEnabled ||
        ![location isEqualToString:@"SBIconLocationRoot"] ||
        ![icon isKindOfClass:folderIconClass]) return NO;
    // Fail closed for App Library categories, nested folders and drag previews.
    id folder = GetObjectIvar(icon, "_folder");
    id parent = GetObjectIvar(folder, "_parent");
    return [parent isKindOfClass:listModelClass] &&
        [GetObjectIvar(parent, "_folder") isKindOfClass:rootFolderClass];
}

static BOOL PrepareCall(id view, id icon, NSString *location, FCCall *call) {
    if (![NSThread isMainThread] || ![view isKindOfClass:folderViewClass] ||
        !IsHomeFolder(icon, location)) return NO;
    id cache = CallObject(view, NSSelectorFromString(@"_folderIconImageCache"));
    // Never call listLayout getters: Bolders mutates configuration there.
    id layout = GetObjectIvar(cache, "_listLayout");
    if (!cache || !layout) return NO;
    call->view = view;
    call->icon = icon;
    call->cache = cache;
    call->layout = layout;
    call->side = coverSide;
    return YES;
}

static BOOL PrepareExistingCall(id view, FCCall *call) {
    // Location is established by setIcon:location:animated:, not guessed from
    // a generic UIImage or the fact that this process is SpringBoard.
    if (![objc_getAssociatedObject(view, homeFolderKey) boolValue]) return NO;
    id icon = CallObject(view, NSSelectorFromString(@"_folderIcon"));
    return PrepareCall(view, icon, @"SBIconLocationRoot", call);
}

static void Push(FCCall *call) {
    call->previous = activeCall;
    activeCall = call;
}

static void Pop(FCCall *call) {
    activeCall = call->previous;
}

static void (*originalSetIcon)(id, SEL, id, id, BOOL);
static void SetIcon(id self, SEL cmd, id icon, id location, BOOL animated) {
    BOOL home = IsHomeFolder(icon, location);
    if (home) FCCounters[1]++;
    objc_setAssociatedObject(self, homeFolderKey, home ? @YES : nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, failedRepairKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Original establishes the view's icon/cache, then enters nested update
    // callbacks, which get their own explicitly qualified context.
    FCCall *saved = activeCall;
    activeCall = NULL;
    @try { originalSetIcon(self, cmd, icon, location, animated); }
    @finally { activeCall = saved; }
}

static void (*originalUpdate)(id, SEL, BOOL);
static void Update(id self, SEL cmd, BOOL animated) {
    FCCall call = {0};
    if (!PrepareExistingCall(self, &call)) {
        FCCall *saved = activeCall;
        activeCall = NULL;
        @try { originalUpdate(self, cmd, animated); }
        @finally { activeCall = saved; }
        return;
    }
    Push(&call);
    @try { originalUpdate(self, cmd, animated); }
    @finally { Pop(&call); }
}

static void (*originalFulfill)(id, SEL, id);
static void Fulfill(id self, SEL cmd, id element) {
    FCCall call = {0};
    if (!PrepareExistingCall(self, &call)) {
        FCCall *saved = activeCall;
        activeCall = NULL;
        @try { originalFulfill(self, cmd, element); }
        @finally { activeCall = saved; }
        return;
    }
    Push(&call);
    @try { originalFulfill(self, cmd, element); }
    @finally { Pop(&call); }
}

static void (*originalDidUpdate)(id, SEL, id, id);
static void DidUpdate(id self, SEL cmd, id cache, id icon) {
    FCCall call = {0};
    if (!PrepareExistingCall(self, &call) || cache != call.cache || icon != call.icon) {
        FCCall *saved = activeCall;
        activeCall = NULL;
        @try { originalDidUpdate(self, cmd, cache, icon); }
        @finally { activeCall = saved; }
        return;
    }
    Push(&call);
    @try { originalDidUpdate(self, cmd, cache, icon); }
    @finally { Pop(&call); }
}

static CGSize (*originalSize)(id, SEL, id);
static CGSize CoverSize(id self, SEL cmd, id layout) {
    if (activeCall && activeCall->rendering && layout == activeCall->layout)
    {
        FCCounters[3]++;
        return CGSizeMake(activeCall->side, activeCall->side);
    }
    return originalSize(self, cmd, layout);
}

static CGRect (*originalRect)(id, SEL, NSUInteger, id, NSUInteger);
static CGRect CellRect(id self, SEL cmd, NSUInteger index, id layout, NSUInteger count) {
    if (activeCall && activeCall->rendering && layout == activeCall->layout) {
        FCCounters[4]++;
        // PrimalFolder's full-cover semantics: only its first cell is visible.
        // This does not alter SBIconListModel or its row/column capacity.
        return index == 0 ? CGRectMake(0, 0, activeCall->side, activeCall->side) : CGRectZero;
    }
    return originalRect(self, cmd, index, layout, count);
}

static id (*originalCellImage)(id, SEL, CGSize, id);
static id CellImage(id self, SEL cmd, CGSize size, id image) {
    // Matches the audited PrimalFolder2 0.1.2 rendering input, without relying
    // on its process-global App Library flag. This is not output image size.
    if (activeCall && activeCall->rendering) {
        FCCounters[5]++;
        size = CGSizeMake(138, 138);
    }
    return originalCellImage(self, cmd, size, image);
}

static id (*originalGeneratePage)(id, SEL, NSUInteger, id, id, id, id);
static id GeneratePage(id self, SEL cmd, NSUInteger page, id icon, id layout,
                       id provider, id pool) {
    FCCall *saved = activeCall;
    FCCall generation = {0};
    if (saved && saved->rendering && page == 0 && icon == saved->icon && layout) {
        FCCounters[2]++;
        // Use this invocation's layout, not a global flag or an assumed cache
        // layout identity. Other/nested factory calls must be unmodified.
        generation = *saved;
        generation.layout = layout;
        generation.previous = saved;
        activeCall = &generation;
    } else {
        activeCall = NULL;
    }
    @try { return originalGeneratePage(self, cmd, page, icon, layout, provider, pool); }
    @finally { activeCall = saved; }
}

static id (*originalPageImage)(id, SEL, NSUInteger, id);
static id PageImage(id self, SEL cmd, NSUInteger page, id icon) {
    FCCall *saved = activeCall;
    BOOL target = saved && self == saved->cache && icon == saved->icon && page == 0;
    FCCall renderingCall = {0};
    // Nested unrelated cache lookups must not inherit this cover context.
    if (target) {
        renderingCall = *saved;
        renderingCall.rendering = YES;
        renderingCall.previous = saved;
        activeCall = &renderingCall;
    } else {
        activeCall = NULL;
    }
    @try {
        UIImage *image = originalPageImage(self, cmd, page, icon);
        if (target && !rebuilding && [image isKindOfClass:gridImageClass] &&
            image != objc_getAssociatedObject(saved->view, failedRepairKey) &&
            FCNeedsRegeneration(image.size.width, image.size.height, image.scale, saved->side)) {
            SEL rebuild = NSSelectorFromString(@"rebuildImagesForFolderIcon:");
            if ([self respondsToSelector:rebuild]) {
                rebuilding = YES;
                FCCounters[6]++;
                @try {
                    ((void (*)(id, SEL, id))objc_msgSend)(self, rebuild, icon);
                    image = originalPageImage(self, cmd, page, icon);
                } @finally { rebuilding = NO; }
                if (FCNeedsRegeneration(image.size.width, image.size.height, image.scale, saved->side)) {
                    FCCounters[7]++;
                    // No global cache flush, rescale fallback or retry loop.
                    objc_setAssociatedObject(saved->view, failedRepairKey, image,
                                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    NSLog(@"[FolderCoverCompat] scoped rebuild remained non-square");
                } else {
                    objc_setAssociatedObject(saved->view, failedRepairKey, nil,
                                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            }
        }
        return image;
    } @finally { activeCall = saved; }
}

static void ReadPreferences(void) {
    NSDictionary *p = preferencesPath ? [NSDictionary dictionaryWithContentsOfFile:preferencesPath] : nil;
    if (![p isKindOfClass:[NSDictionary class]]) {
        coverEnabled = NO;
        return;
    }
    id iconFolder = p[@"iconFolder"];
    id keepFolder = p[@"keepFolder"];
    BOOL valid = (!iconFolder || [iconFolder isKindOfClass:[NSNumber class]]) &&
        (!keepFolder || [keepFolder isKindOfClass:[NSNumber class]]);
    coverEnabled = valid && (!iconFolder || [iconFolder boolValue]) && ![keepFolder boolValue];
}

static void PreferencesChanged(CFNotificationCenterRef center, void *observer,
                              CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    // Update on the same queue used by the desktop image view callbacks.
    dispatch_async(dispatch_get_main_queue(), ^{ ReadPreferences(); });
}

static BOOL HasImageUUID(const char *suffix, const unsigned char expected[16]) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *path = _dyld_get_image_name(i);
        if (!path || strlen(path) < strlen(suffix) ||
            strcmp(path + strlen(path) - strlen(suffix), suffix) != 0) continue;
        const struct mach_header_64 *h = (const struct mach_header_64 *)_dyld_get_image_header(i);
        if (h->magic != MH_MAGIC_64) continue;
        const uint8_t *cursor = (const uint8_t *)(h + 1);
        const uint8_t *end = cursor + h->sizeofcmds;
        for (uint32_t j = 0; j < h->ncmds && cursor + sizeof(struct load_command) <= end; j++) {
            const struct load_command *c = (const struct load_command *)cursor;
            if (c->cmdsize < sizeof(*c) || cursor + c->cmdsize > end) break;
            if (c->cmd == LC_UUID && c->cmdsize >= sizeof(struct uuid_command))
                return memcmp(((const struct uuid_command *)c)->uuid, expected, 16) == 0;
            cursor += c->cmdsize;
        }
    }
    return NO;
}

static BOOL CheckMethod(Class cls, NSString *name, NSString *types) {
    Method m = class_getInstanceMethod(cls, NSSelectorFromString(name));
    return m && [types isEqualToString:[NSString stringWithUTF8String:method_getTypeEncoding(m)]];
}

static NSString *ResolvePreferencesPath(void) {
    // RootHide exposes different filesystem views. Resolve the existing
    // .jbroot beside this library; never assume /var means the tweak root.
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        NSString *path = [NSString stringWithUTF8String:name];
        if (![[path lastPathComponent] isEqualToString:@"zzFolderCoverCompat.dylib"]) continue;
        NSString *candidate = [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:
            @".jbroot/var/mobile/Library/Preferences/com.ichitaso.primalfolder2.plist"];
        char resolved[PATH_MAX];
        if (realpath(candidate.fileSystemRepresentation, resolved))
            return [NSString stringWithUTF8String:resolved];
    }
    return nil;
}

#ifndef FC_FIXTURE
__attribute__((constructor))
#endif
static void Init(void) {
    @autoreleasepool {
        if (strcmp(getprogname(), "SpringBoard") != 0) return;
        struct utsname u;
        if (uname(&u) != 0 || (strcmp(u.machine, "iPhone13,1") != 0 && strcmp(u.machine, "iPhone15,3") != 0)) return;
        // Constructors run before UIKit screen creation. Do NOT call
        // UIScreen.mainScreen or UIDevice here; the former asserted on device.
        NSOperatingSystemVersion version = [NSProcessInfo processInfo].operatingSystemVersion;
        if (version.majorVersion != 16 || version.minorVersion != 3 ||
            version.patchVersion > 1) return;
        const unsigned char primal[16] = {0x25,0x22,0x12,0xe1,0x14,0x09,0x31,0xb6,0xbc,0x51,0x6d,0xfa,0x23,0x16,0x9b,0xf7};
        const unsigned char bolders[16] = {0x32,0x37,0x06,0x7d,0xb4,0x2c,0x37,0x08,0xb0,0x03,0x2b,0x2d,0xa8,0x2b,0x57,0xd2};
        if (!HasImageUUID("/PrimalFolder2.dylib", primal) || !HasImageUUID("/BoldersReborn.dylib", bolders)) {
            NSLog(@"[FolderCoverCompat] not installed: unverified addon image or load order");
            return;
        }
        coverSide = strcmp(u.machine, "iPhone13,1") == 0 ? 60.0 : 64.0;
        if (!coverSide) return;
        folderViewClass = NSClassFromString(@"SBFolderIconImageView");
        folderIconClass = NSClassFromString(@"SBFolderIcon");
        rootFolderClass = NSClassFromString(@"SBRootFolder");
        listModelClass = NSClassFromString(@"SBIconListModel");
        gridImageClass = NSClassFromString(@"SBIconGridImage");
        Class cache = NSClassFromString(@"SBFolderIconImageCache");
        Class gridMeta = object_getClass(gridImageClass);
        Class cacheMeta = object_getClass(cache);
        if (!folderIconClass || !rootFolderClass || !listModelClass || !gridImageClass ||
            !CheckMethod(folderViewClass, @"setIcon:location:animated:", @"v36@0:8@16@24B32") ||
            !CheckMethod(folderViewClass, @"updateImageAnimated:", @"v20@0:8B16") ||
            !CheckMethod(folderViewClass, @"fulfillGridImageForPageElement:", @"v24@0:8@16") ||
            !CheckMethod(folderViewClass, @"folderIconImageCache:didUpdateImagesForFolderIcon:", @"v32@0:8@16@24") ||
            !CheckMethod(cache, @"imageForPageAtIndex:inFolderIcon:", @"@32@0:8Q16@24") ||
            !CheckMethod(cache, @"rebuildImagesForFolderIcon:", @"v24@0:8@16") ||
            !CheckMethod(cacheMeta, @"imageForPageAtIndex:inFolderIcon:listLayout:gridCellImageProvider:pool:", @"@56@0:8Q16@24@32@40@48") ||
            !CheckMethod(gridMeta, @"sizeForLayout:", @"{CGSize=dd}24@0:8@16") ||
            !CheckMethod(gridMeta, @"rectAtIndex:inLayout:maxCount:", @"{CGRect={CGPoint=dd}{CGSize=dd}}40@0:8Q16@24Q32") ||
            !CheckMethod(cacheMeta, @"gridCellImageOfSize:forIconImage:", @"@40@0:8{CGSize=dd}16@32")) {
            NSLog(@"[FolderCoverCompat] not installed: private method signature mismatch");
            return;
        }
        preferencesPath = [ResolvePreferencesPath() copy];
        if (!preferencesPath) {
            NSLog(@"[FolderCoverCompat] not installed: preference root unavailable");
            return;
        }
        ReadPreferences();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            PreferencesChanged, CFSTR("com.ichitaso.primalfolder2.preferencesChanged"), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
#define INSTALL(c, s, fn, orig) MSHookMessageEx(c, NSSelectorFromString(s), (IMP)fn, (IMP *)&orig)
        INSTALL(folderViewClass, @"setIcon:location:animated:", SetIcon, originalSetIcon);
        INSTALL(folderViewClass, @"updateImageAnimated:", Update, originalUpdate);
        INSTALL(folderViewClass, @"fulfillGridImageForPageElement:", Fulfill, originalFulfill);
        INSTALL(folderViewClass, @"folderIconImageCache:didUpdateImagesForFolderIcon:", DidUpdate, originalDidUpdate);
        INSTALL(cache, @"imageForPageAtIndex:inFolderIcon:", PageImage, originalPageImage);
        INSTALL(cacheMeta, @"imageForPageAtIndex:inFolderIcon:listLayout:gridCellImageProvider:pool:", GeneratePage, originalGeneratePage);
        INSTALL(gridMeta, @"sizeForLayout:", CoverSize, originalSize);
        INSTALL(gridMeta, @"rectAtIndex:inLayout:maxCount:", CellRect, originalRect);
        INSTALL(cacheMeta, @"gridCellImageOfSize:forIconImage:", CellImage, originalCellImage);
#undef INSTALL
        FCCounters[0] = 1;
        NSLog(@"[FolderCoverCompat] scoped hooks installed; cover side=%.0f", coverSide);
    }
}

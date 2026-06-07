/**
 * TBAntiJBDetect v2 - 淘宝越狱检测绕过
 *
 * 核心改进：参照 Shadow 项目的 dylib 隐藏机制
 * 1. 全面 hook dyld API 隐藏自身注入
 * 2. hook task_info(TASK_DYLD_INFO) 从内核层面隐藏
 * 3. hook dlsym/dladdr 隐藏符号和地址归属
 * 4. isCallerTweak() 调用者判断，tweak 自身调用返回真实值
 * 5. 环境变量 unsetenv 直接删除
 * 6. 文件系统/ObjC 层越狱路径隐藏
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <sys/stat.h>
#import <unistd.h>
#import <mach-o/dyld.h>
#import <mach-o/dyld_images.h>
#import <sys/sysctl.h>
#import <dirent.h>
#import <fcntl.h>
#import <stdio.h>
#import <mach/mach.h>
#import <mach/task_info.h>
#import <crt_externs.h>

// dyld 私有符号声明
extern const char *dyld_image_path_containing_address(const void *addr);

// ============================================================
// 调试日志 - beta1 关闭日志，避免耗电和 CPU 开销
// ============================================================
#define TB_DEBUG 0

#if TB_DEBUG
static void tbdlog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void tbdlog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSLog(@"[TBAntiJBDetect] %@", msg);
}
#else
#define tbdlog(...)
#endif

// ============================================================
// 调用者判断 - 区分 tweak 自身调用和目标 app 调用
// ============================================================

static NSString *_appBundlePath = nil;

static void initAppBundlePath(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        char ***argv = _NSGetArgv();
        char *execPathC = argv ? *argv[0] : NULL;
        if (execPathC) {
            _appBundlePath = [NSString stringWithUTF8String:execPathC];
            _appBundlePath = [[_appBundlePath stringByDeletingLastPathComponent] copy];
        }
    });
}

// 判断调用地址是否来自目标 app（非 tweak 自身）
// 优化：缓存镜像路径判断结果，避免每次都调用 dyld_image_path_containing_address
static BOOL isCallerApp(uintptr_t returnAddr) {
    if (returnAddr == 0) return NO;

    initAppBundlePath();
    if (!_appBundlePath) return YES; // 无法判断时默认当作 app 调用

    // 用 dyld_image_path_containing_address 判断调用者所在镜像
    const char *imagePath = dyld_image_path_containing_address((void *)returnAddr);
    if (!imagePath) return YES;

    // 调用来自 app 自身目录 → 是 app 调用
    if (strstr(imagePath, [_appBundlePath fileSystemRepresentation]) != NULL) {
        return YES;
    }

    // 调用来自系统框架 → 通常是 app 间接触发，当作 app 调用
    if (strstr(imagePath, "/System/Library/") != NULL) {
        return YES;
    }

    // 其他（tweak 自身、越狱库）→ 不是 app 调用
    return NO;
}

#define isCallerTweak() (!isCallerApp((uintptr_t)__builtin_return_address(0)))

// ============================================================
// 越狱路径集合
// ============================================================

static NSSet<NSString *> *jbPaths;
static NSArray<NSString *> *jbPrefixes;
static NSSet<NSString *> *jbDylibKeywords;

static void initJBPaths(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        jbPaths = [NSSet setWithArray:@[
            @"/Applications/Cydia.app", @"/Applications/FakeCarrier.app",
            @"/Applications/FlyJB.app", @"/Applications/Filza.app",
            @"/Applications/FilzaFile.app", @"/Applications/Sileo.app",
            @"/Applications/Zebra.app", @"/Applications/Undecimus.app",
            @"/Applications/unc0ver.app", @"/Applications/checkra1n.app",
            @"/Applications/Taurine.app", @"/Applications/electra.app",
            @"/bin/bash", @"/bin/sh", @"/bin/ssh", @"/bin/sshd",
            @"/etc/apt", @"/etc/dpkg", @"/etc/ssh",
            @"/Library/MobileSubstrate", @"/Library/MobileSubstrate/MobileSubstrate.dylib",
            @"/private/var/lib/apt", @"/private/var/lib/cydia", @"/private/var/tmp/cydia",
            @"/usr/bin/ssh", @"/usr/bin/dpkg", @"/usr/bin/apt",
            @"/usr/libexec/cydia", @"/usr/libexec/ssh", @"/usr/libexec/ssh-keysign",
            @"/usr/sbin/frida", @"/usr/sbin/frida-server", @"/usr/sbin/sshd",
            @"/usr/lib/frida", @"/usr/lib/libfrida-gadget.dylib",
            @"/usr/lib/TweakInject",
            @"/bootstrap", @"/.installed_unc0ver", @"/.cydia_no_stash",
            @"/var/jb", @"/var/jb/.installed_dopamine", @"/var/jb/.procursus_strapped",
            @"/var/jb/usr/sbin/sshd", @"/var/jb/etc/apt", @"/var/jb/etc/dpkg",
            @"/var/jb/etc/ssh", @"/var/jb/var/lib/dpkg", @"/var/jb/var/lib/cydia",
            @"/var/jb/var/cache/apt",
            @"/var/jb/Applications/Sileo.app", @"/var/jb/Applications/Cydia.app",
            @"/var/jb/Applications/Filza.app",
            @"/var/jb/Library/MobileSubstrate/DynamicLibraries",
            @"/var/jb/usr/lib/TweakLoader.dylib", @"/var/jb/usr/lib/libsubstrate.dylib",
            @"/var/jb/usr/lib/libsubstitute.dylib", @"/var/jb/usr/lib/libhooker.dylib",
            @"/var/jb/usr/lib/libellekit.dylib", @"/var/jb/usr/lib/libellekitc.dylib",
            @"/var/jb/usr/lib/libblackjack.dylib", @"/var/jb/usr/lib/libkrw.dylib",
            @"/var/jb/usr/bin/bash", @"/var/jb/usr/bin/ssh",
            @"/var/jb/bin/bash", @"/var/jb/bin/sh",
            @"/private/var/jb", @"/private/var/jb/.installed_dopamine",
            @"/private/var/jb/Library/MobileSubstrate",
            @"/private/var/jb/Applications/Cydia.app",
            @"/private/var/jb/Applications/Sileo.app",
            @"/private/var/jb/etc/apt",
        ]];

        jbPrefixes = @[
            @"/var/jb/", @"/Library/MobileSubstrate/",
            @"/usr/lib/TweakInject/", @"/usr/lib/frida/", @"/bootstrap/",
        ];

        jbDylibKeywords = [NSSet setWithArray:@[
            @"Substrate", @"substrate", @"CydiaSubstrate",
            @"TweakInject", @"TweakLoader", @"libhooker",
            @"libsubstitute", @"libellekit", @"ElleKit",
            @"MobileSubstrate", @"Cydia", @"Sileo",
            @"Substitute", @"libfrida", @"frida-gadget",
            @"libblackjack", @"libkrw", @"TBAntiJBDetect",
            @"JDAntiJBDetect", @"Choicy", @"Crane",
        ]];
    });
}

static BOOL isJBPath(NSString *path) {
    if (!path) return NO;
    if ([jbPaths containsObject:path]) return YES;
    for (NSString *prefix in jbPrefixes) {
        if ([path hasPrefix:prefix]) return YES;
    }
    return NO;
}

static BOOL isJBPathC(const char *path) {
    if (!path) return NO;
    NSString *ns = [NSString stringWithUTF8String:path];
    if (!ns) return NO;
    return isJBPath(ns);
}

// 判断路径是否为越狱相关的 dylib（用于 dyld 隐藏）
static BOOL isJBDylibPath(NSString *path) {
    if (!path) return NO;
    NSString *lower = [path lowercaseString];
    // 隐藏所有 /var/jb/ 下的 dylib
    if ([lower hasPrefix:@"/var/jb/"]) return YES;
    if ([lower hasPrefix:@"/private/var/jb/"]) return YES;
    // 隐藏 MobileSubstrate/TweakInject 相关
    if ([lower containsString:@"substrate"] || [lower containsString:@"tweakinject"] ||
        [lower containsString:@"tweakloader"] || [lower containsString:@"libhooker"] ||
        [lower containsString:@"libsubstitute"] || [lower containsString:@"ellekit"] ||
        [lower containsString:@"cydiasubstrate"]) return YES;
    // 隐藏自身
    if ([lower containsString:@"tbantijbdetect"] || [lower containsString:@"jdantijbdetect"]) return YES;
    // 隐藏 Choicy/Crane 等注入管理工具
    if ([lower containsString:@"choicy"] || [lower containsString:@"choicysb"]) return YES;
    return NO;
}

// 判断地址是否属于越狱 dylib
static BOOL isAddrRestricted(const void *addr) {
    if (!addr) return NO;
    const char *imagePath = dyld_image_path_containing_address(addr);
    if (!imagePath) return NO;
    return isJBDylibPath([NSString stringWithUTF8String:imagePath]);
}

// ============================================================
// Layer 0: dyld API 全面替换 - 隐藏注入的 dylib
// ============================================================

// 安全 dylib 集合：只包含非越狱的镜像
static NSMutableArray<NSDictionary *> *_safeDyldCollection = nil;
static NSMutableArray<NSValue *> *_addImageCallbacks = nil;
static NSMutableArray<NSValue *> *_removeImageCallbacks = nil;

// 原函数指针
static uint32_t (*orig_dyld_image_count)();
static const struct mach_header *(*orig_dyld_get_image_header)(uint32_t);
static intptr_t (*orig_dyld_get_image_vmaddr_slide)(uint32_t);
static const char *(*orig_dyld_get_image_name)(uint32_t);
static void (*orig_dyld_register_func_for_add_image)(void (*)(const struct mach_header *, intptr_t));
static void (*orig_dyld_register_func_for_remove_image)(void (*)(const struct mach_header *, intptr_t));

// 在镜像加载时构建安全集合
static void onImageAdded(const struct mach_header *mh, intptr_t slide) {
    if (!mh) return;
    const char *imagePath = dyld_image_path_containing_address(mh);
    if (!imagePath) return;

    NSString *path = [NSString stringWithUTF8String:imagePath];

    // 只添加非越狱的镜像到安全集合
    if (!isJBDylibPath(path)) {
        [_safeDyldCollection addObject:@{
            @"name": path,
            @"mach_header": [NSValue valueWithPointer:mh],
            @"slide": [NSValue valueWithPointer:(void *)slide]
        }];
    }

    // 调用 app 注册的回调（只传安全的镜像）
    if (_addImageCallbacks) {
        if (!isJBDylibPath(path)) {
            for (NSValue *cb in [_addImageCallbacks copy]) {
                void (*func)(const struct mach_header *, intptr_t) = [cb pointerValue];
                func(mh, slide);
            }
        }
    }
}

static void onImageRemoved(const struct mach_header *mh, intptr_t slide) {
    if (!mh) return;

    NSDictionary *toRemove = nil;
    for (NSDictionary *entry in _safeDyldCollection) {
        if ([entry[@"mach_header"] pointerValue] == mh) {
            toRemove = entry;
            break;
        }
    }
    if (toRemove) {
        [_safeDyldCollection removeObject:toRemove];
    }

    if (_removeImageCallbacks) {
        for (NSValue *cb in [_removeImageCallbacks copy]) {
            void (*func)(const struct mach_header *, intptr_t) = [cb pointerValue];
            func(mh, slide);
        }
    }
}

// Hook 实现
static uint32_t hooked_dyld_image_count() {
    if (isCallerTweak()) return orig_dyld_image_count();
    return (uint32_t)[_safeDyldCollection count];
}

static const struct mach_header *hooked_dyld_get_image_header(uint32_t index) {
    if (isCallerTweak()) return orig_dyld_get_image_header(index);
    return index < [_safeDyldCollection count]
        ? (struct mach_header *)[_safeDyldCollection[index][@"mach_header"] pointerValue]
        : NULL;
}

static intptr_t hooked_dyld_get_image_vmaddr_slide(uint32_t index) {
    if (isCallerTweak()) return orig_dyld_get_image_vmaddr_slide(index);
    return index < [_safeDyldCollection count]
        ? (intptr_t)[_safeDyldCollection[index][@"slide"] pointerValue]
        : 0;
}

static const char *hooked_dyld_get_image_name(uint32_t index) {
    if (isCallerTweak()) return orig_dyld_get_image_name(index);
    return index < [_safeDyldCollection count]
        ? [_safeDyldCollection[index][@"name"] fileSystemRepresentation]
        : NULL;
}

static void hooked_dyld_register_func_for_add_image(void (*func)(const struct mach_header *, intptr_t)) {
    if (isCallerTweak() || !func) {
        orig_dyld_register_func_for_add_image(func);
        return;
    }
    // App 注册回调时，只让它看到安全的镜像
    [_addImageCallbacks addObject:[NSValue valueWithPointer:func]];
    for (NSDictionary *entry in _safeDyldCollection) {
        func((struct mach_header *)[entry[@"mach_header"] pointerValue],
             (intptr_t)[entry[@"slide"] pointerValue]);
    }
}

static void hooked_dyld_register_func_for_remove_image(void (*func)(const struct mach_header *, intptr_t)) {
    if (isCallerTweak() || !func) {
        orig_dyld_register_func_for_remove_image(func);
        return;
    }
    [_removeImageCallbacks addObject:[NSValue valueWithPointer:func]];
}

// ============================================================
// Layer 1: task_info - 从内核层面隐藏 dylib 信息
// ============================================================

static kern_return_t (*orig_task_info)(task_name_t, task_flavor_t, task_info_t, mach_msg_type_number_t *);

static kern_return_t hooked_task_info(task_name_t target_task, task_flavor_t flavor,
                                       task_info_t task_info_out, mach_msg_type_number_t *task_info_outCnt) {
    if (isCallerTweak()) return orig_task_info(target_task, flavor, task_info_out, task_info_outCnt);

    kern_return_t result = orig_task_info(target_task, flavor, task_info_out, task_info_outCnt);

    if (flavor == TASK_DYLD_INFO && result == KERN_SUCCESS) {
        struct task_dyld_info *info = (struct task_dyld_info *)task_info_out;
        // 将 all_image_info 的 count 设为 1（只有主程序）
        struct dyld_all_image_infos *dyldInfo = (struct dyld_all_image_infos *)info->all_image_info_addr;
        if (dyldInfo) {
            dyldInfo->infoArrayCount = 1;
            dyldInfo->uuidArrayCount = 1;
        }
    }

    return result;
}

// ============================================================
// Layer 2: dlsym/dladdr - 隐藏符号和地址归属
// ============================================================

static void *(*orig_dlsym)(void *, const char *);
static int (*orig_dladdr)(const void *, Dl_info *);

static void *hooked_dlsym(void *handle, const char *symbol) {
    if (isCallerTweak()) return orig_dlsym(handle, symbol);

    void *addr = orig_dlsym(handle, symbol);

    // 如果地址属于越狱 dylib，返回 NULL
    if (addr && isAddrRestricted(addr)) {
        tbdlog(@"dlsym: 隐藏符号 %s", symbol ? symbol : "(null)");
        return NULL;
    }

    return addr;
}

static int hooked_dladdr(const void *addr, Dl_info *info) {
    if (isCallerTweak()) return orig_dladdr(addr, info);

    int result = orig_dladdr(addr, info);

    // 如果地址属于越狱 dylib，伪造归属为主程序
    if (result && info && isAddrRestricted(addr)) {
        char ***argvPtr = _NSGetArgv();
        char *execPathC = argvPtr ? *argvPtr[0] : NULL;
        if (execPathC) {
            info->dli_fname = execPathC;
        }
    }

    return result;
}

// ============================================================
// Layer 3: dlopen - 阻止加载越狱路径
// ============================================================

static void *(*orig_dlopen)(const char *, int);
static char *(*orig_dlerror)(void);
static BOOL _dyldError = NO;

static void *hooked_dlopen(const char *path, int mode) {
    if (isCallerTweak() || !path) return orig_dlopen(path, mode);

    if (isJBPathC(path)) {
        tbdlog(@"dlopen: 阻止加载 %s", path);
        _dyldError = YES;
        return NULL;
    }
    return orig_dlopen(path, mode);
}

static char *hooked_dlerror(void) {
    if (isCallerTweak() || !_dyldError) return orig_dlerror();
    _dyldError = NO;
    return "library not found";
}

// ============================================================
// Layer 4: ObjC 层 - 越狱检测方法
// ============================================================

%hook NSObject

- (BOOL)isJailBreak { tbdlog(@"OBJC: isJailBreak -[%@]", NSStringFromClass([self class])); return NO; }
- (BOOL)isJailbreak { return NO; }
- (BOOL)isJailBroken { tbdlog(@"OBJC: isJailBroken -[%@]", NSStringFromClass([self class])); return NO; }
- (BOOL)isJailbroken { return NO; }
- (BOOL)isjailbreak { return NO; }
- (BOOL)currentDeviceIsJailbroken { tbdlog(@"OBJC: currentDeviceIsJailbroken -[%@]", NSStringFromClass([self class])); return NO; }
- (BOOL)checkJailbroken { return NO; }
- (BOOL)TBIsJailBreak { tbdlog(@"OBJC: TBIsJailBreak -[%@]", NSStringFromClass([self class])); return NO; }
- (BOOL)isDeviceJailBreak { return NO; }
- (BOOL)elmp_isJailBroken { return NO; }
- (BOOL)judgeJailbrokenCanPay { tbdlog(@"OBJC: judgeJailbrokenCanPay -[%@] → NO", NSStringFromClass([self class])); return NO; }
- (BOOL)shouldJailbrokenPay { tbdlog(@"OBJC: shouldJailbrokenPay -[%@] → YES", NSStringFromClass([self class])); return YES; }
- (BOOL)detectCurrentDeviceIsJailbroken { return NO; }
- (BOOL)detectJailBreakByAppPathExisted { return NO; }
- (BOOL)detectJailBreakByCydiaPathExisted { return NO; }
- (BOOL)detectJailBreakByEnvironmentExisted { return NO; }
- (BOOL)detectJailBreakByJailBreakFileExisted { return NO; }
- (BOOL)detectJailBreakByStat { return NO; }

+ (BOOL)TBIsJailBreak { return NO; }
+ (BOOL)isJailBreak { return NO; }
+ (BOOL)isJailBroken { return NO; }
+ (BOOL)currentDeviceIsJailbroken { return NO; }

%end

// ============================================================
// Layer 5: NSFileManager
// ============================================================

%hook NSFileManager

- (BOOL)fileExistsAtPath:(NSString *)path {
    if (isJBPath(path)) { tbdlog(@"FM: fileExistsAtPath → %@", path); return NO; }
    return %orig;
}

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    if (isJBPath(path)) {
        if (isDirectory) *isDirectory = NO;
        return NO;
    }
    return %orig;
}

- (BOOL)isReadableFileAtPath:(NSString *)path {
    if (isJBPath(path)) return NO;
    return %orig;
}

- (BOOL)isWritableFileAtPath:(NSString *)path {
    if (isJBPath(path)) return NO;
    return %orig;
}

- (BOOL)isDeletableFileAtPath:(NSString *)path {
    if (isJBPath(path)) return NO;
    return %orig;
}

- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
    NSArray *result = %orig;
    if (!result) return result;
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSString *item in result) {
        NSString *full = [path stringByAppendingPathComponent:item];
        if (!isJBPath(full) && !isJBPath(item)) {
            [filtered addObject:item];
        }
    }
    return filtered;
}

- (NSDirectoryEnumerator *)enumeratorAtPath:(NSString *)path {
    if (isJBPath(path)) return (NSDirectoryEnumerator *)[[NSArray array] objectEnumerator];
    return %orig;
}

- (NSDictionary *)attributesOfItemAtPath:(NSString *)path error:(NSError **)error {
    if (isJBPath(path)) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError userInfo:nil];
        return nil;
    }
    return %orig;
}

%end

// ============================================================
// Layer 6: NSURL / UIApplication
// ============================================================

%hook NSURL

- (BOOL)checkResourceIsReachableAndReturnError:(NSError *__autoreleasing *)error {
    NSString *path = [self path];
    if (path && isJBPath(path)) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError userInfo:nil];
        return NO;
    }
    return %orig;
}

%end

%hook UIApplication

- (BOOL)canOpenURL:(NSURL *)url {
    NSString *scheme = [url scheme];
    if (scheme) {
        NSString *lower = [scheme lowercaseString];
        if ([lower isEqualToString:@"cydia"] || [lower isEqualToString:@"sileo"] ||
            [lower isEqualToString:@"zbra"] || [lower isEqualToString:@"undecimus"]) {
            return NO;
        }
    }
    return %orig;
}

%end

// ============================================================
// Layer 7: C 层 - fishhook (stat/access/fopen 等)
// ============================================================

#include <string.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>

#ifdef __LP64__
typedef struct mach_header_64 mach_header_t;
typedef struct segment_command_64 segment_command_t;
typedef struct nlist_64 nlist_t;
#define LC_SEGMENT_ARCH_DEPENDENT LC_SEGMENT_64
#else
typedef struct mach_header mach_header_t;
typedef struct segment_command_64 segment_command_t;
typedef struct nlist nlist_t;
#define LC_SEGMENT_ARCH_DEPENDENT LC_SEGMENT
#endif

struct rebind_entry { const char *name; void *replacement; void **replaced; };

static void rebind_for_image(struct rebind_entry rebindings[], size_t count,
                              const mach_header_t *header, intptr_t slide) {
    segment_command_t *cur_seg_cmd;
    segment_command_t *linkedit_segment = NULL;
    struct symtab_command *symtab_cmd = NULL;

    uintptr_t cur = (uintptr_t)header + sizeof(mach_header_t);
    for (uint32_t i = 0; i < header->ncmds; i++, cur += cur_seg_cmd->cmdsize) {
        cur_seg_cmd = (segment_command_t *)cur;
        if (cur_seg_cmd->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
            if (strcmp(cur_seg_cmd->segname, SEG_LINKEDIT) == 0) linkedit_segment = cur_seg_cmd;
        } else if (cur_seg_cmd->cmd == LC_SYMTAB) {
            symtab_cmd = (struct symtab_command *)cur_seg_cmd;
        }
    }
    if (!symtab_cmd || !linkedit_segment) return;

    uintptr_t linkedit_base = slide + linkedit_segment->vmaddr - linkedit_segment->fileoff;
    nlist_t *symtab = (nlist_t *)(linkedit_base + symtab_cmd->symoff);
    char *strtab = (char *)(linkedit_base + symtab_cmd->stroff);

    for (uint32_t i = 0; i < symtab_cmd->nsyms; i++) {
        if (symtab[i].n_type & N_STAB) continue;
        char *sym_name = strtab + symtab[i].n_un.n_strx;
        for (size_t j = 0; j < count; j++) {
            if (strcmp(sym_name, rebindings[j].name) == 0) {
                void **got = (void **)(slide + symtab[i].n_value);
                if (*got != rebindings[j].replacement) {
                    if (rebindings[j].replaced) *rebindings[j].replaced = *got;
                    *got = rebindings[j].replacement;
                }
            }
        }
    }
}

static void do_rebind(struct rebind_entry rebindings[], size_t count) {
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const mach_header_t *header = (const mach_header_t *)_dyld_get_image_header(i);
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        rebind_for_image(rebindings, count, header, slide);
    }
}

static int (*orig_stat)(const char *, struct stat *);
static int (*orig_lstat)(const char *, struct stat *);
static int (*orig_access)(const char *, int);
static FILE *(*orig_fopen)(const char *, const char *);
static int (*orig_open)(const char *, int, ...);
static int (*orig_openat)(int, const char *, int, ...);
static DIR *(*orig_opendir)(const char *);
static struct dirent *(*orig_readdir)(DIR *);
static char *(*orig_getenv)(const char *);
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t);

static int h_stat(const char *p, struct stat *b) {
    if (isJBPathC(p)) { errno = ENOENT; return -1; }
    return orig_stat(p, b);
}
static int h_lstat(const char *p, struct stat *b) {
    if (isJBPathC(p)) { errno = ENOENT; return -1; }
    return orig_lstat(p, b);
}
static int h_access(const char *p, int m) {
    if (isJBPathC(p)) { errno = ENOENT; return -1; }
    return orig_access(p, m);
}
static FILE *h_fopen(const char *p, const char *m) {
    if (isJBPathC(p)) return NULL;
    return orig_fopen(p, m);
}
static int h_open(const char *p, int f, ...) {
    if (isJBPathC(p)) { errno = ENOENT; return -1; }
    va_list a; va_start(a, f); mode_t m = va_arg(a, int); va_end(a);
    return orig_open(p, f, m);
}
static int h_openat(int fd, const char *p, int f, ...) {
    if (isJBPathC(p)) { errno = ENOENT; return -1; }
    va_list a; va_start(a, f); mode_t m = va_arg(a, int); va_end(a);
    return orig_openat(fd, p, f, m);
}
static DIR *h_opendir(const char *p) {
    if (isJBPathC(p)) return NULL;
    return orig_opendir(p);
}
static struct dirent *h_readdir(DIR *d) {
    struct dirent *e = orig_readdir(d);
    while (e && e->d_name[0]) {
        NSString *n = [NSString stringWithUTF8String:e->d_name];
        if (n && [jbPaths containsObject:n]) { e = orig_readdir(d); continue; }
        break;
    }
    return e;
}
static char *h_getenv(const char *n) {
    char *r = orig_getenv(n);
    if (n && r) {
        const char *jbEnv[] = {"DYLD_INSERT_LIBRARIES", "_MSSafeMode", "_SafeMode", "_SubstituteSafeMode",
                                "SubstrateLock", "CYDIA_", "JB_", NULL};
        for (int i = 0; jbEnv[i]; i++) {
            if (strcmp(n, jbEnv[i]) == 0) return NULL;
        }
    }
    return r;
}
static int h_sysctlbyname(const char *n, void *o, size_t *ol, void *ne, size_t nl) {
    int r = orig_sysctlbyname(n, o, ol, ne, nl);
    if (n && strstr(n, "jailbreak")) {
        if (o && ol && *ol > 0) memset(o, 0, *ol);
    }
    return r;
}

// ============================================================
// 入口
// ============================================================

%ctor {
    initJBPaths();
    initAppBundlePath();

    // === 第一步：最优先 hook dyld API（隐藏自身注入）===
    _safeDyldCollection = [NSMutableArray new];
    _addImageCallbacks = [NSMutableArray new];
    _removeImageCallbacks = [NSMutableArray new];

    // 注册镜像加载回调，构建安全 dylib 集合
    _dyld_register_func_for_add_image(onImageAdded);
    _dyld_register_func_for_remove_image(onImageRemoved);

    // 用 MSHookFunction 级别的 hook 替换 dyld API
    // 先用 fishhook 做 GOT 级别替换
    struct rebind_entry dyld_rebindings[] = {
        {"_dyld_image_count",                  (void *)hooked_dyld_image_count,                  (void **)&orig_dyld_image_count},
        {"_dyld_get_image_header",             (void *)hooked_dyld_get_image_header,             (void **)&orig_dyld_get_image_header},
        {"_dyld_get_image_vmaddr_slide",        (void *)hooked_dyld_get_image_vmaddr_slide,        (void **)&orig_dyld_get_image_vmaddr_slide},
        {"_dyld_get_image_name",               (void *)hooked_dyld_get_image_name,               (void **)&orig_dyld_get_image_name},
        {"_dyld_register_func_for_add_image",   (void *)hooked_dyld_register_func_for_add_image,   (void **)&orig_dyld_register_func_for_add_image},
        {"_dyld_register_func_for_remove_image",(void *)hooked_dyld_register_func_for_remove_image,(void **)&orig_dyld_register_func_for_remove_image},
        {"task_info",                          (void *)hooked_task_info,                          (void **)&orig_task_info},
        {"dlsym",                              (void *)hooked_dlsym,                              (void **)&orig_dlsym},
        {"dladdr",                             (void *)hooked_dladdr,                             (void **)&orig_dladdr},
        {"dlopen",                             (void *)hooked_dlopen,                             (void **)&orig_dlopen},
        {"dlerror",                            (void *)hooked_dlerror,                            (void **)&orig_dlerror},
    };
    do_rebind(dyld_rebindings, sizeof(dyld_rebindings) / sizeof(dyld_rebindings[0]));

    tbdlog(@"dyld API hooks installed, safe images: %lu", (unsigned long)_safeDyldCollection.count);

    // === 第二步：清理越狱相关环境变量（只删关键项，不遍历全部）===
    {
        const char *jbEnvVars[] = {
            "DYLD_INSERT_LIBRARIES", "_MSSafeMode", "_SafeMode",
            "_SubstituteSafeMode", "SubstrateLock", "CYDIA_", "JB_",
            "FRIDA", "_FRIDA", NULL
        };
        for (int i = 0; jbEnvVars[i]; i++) {
            unsetenv(jbEnvVars[i]);
        }
    }

    // === 第三步：C 层文件系统 hook ===
    struct rebind_entry fs_rebindings[] = {
        {"stat",         (void *)h_stat,         (void **)&orig_stat},
        {"lstat",        (void *)h_lstat,        (void **)&orig_lstat},
        {"access",       (void *)h_access,       (void **)&orig_access},
        {"fopen",        (void *)h_fopen,        (void **)&orig_fopen},
        {"open",         (void *)h_open,         (void **)&orig_open},
        {"openat",       (void *)h_openat,       (void **)&orig_openat},
        {"opendir",      (void *)h_opendir,      (void **)&orig_opendir},
        {"readdir",      (void *)h_readdir,      (void **)&orig_readdir},
        {"getenv",       (void *)h_getenv,       (void **)&orig_getenv},
        {"sysctlbyname", (void *)h_sysctlbyname, (void **)&orig_sysctlbyname},
    };
    do_rebind(fs_rebindings, sizeof(fs_rebindings) / sizeof(fs_rebindings[0]));

    tbdlog(@"filesystem hooks installed");

    tbdlog(@"TBAntiJBDetect v2 初始化完成，%lu 条越狱路径", (unsigned long)jbPaths.count);
}

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <unistd.h>

extern kern_return_t mach_vm_read_overwrite(vm_map_t, mach_vm_address_t,
    mach_vm_size_t, mach_vm_address_t, mach_vm_size_t *);

static NSMutableArray *records;
static NSUInteger visited;

static NSString *Address(id object) {
    return [NSString stringWithFormat:@"%p", (__bridge void *)object];
}

static NSDictionary *RectInfo(CGRect r) {
    return @{@"x": @(r.origin.x), @"y": @(r.origin.y),
             @"width": @(r.size.width), @"height": @(r.size.height)};
}

static NSDictionary *Matrix(CGAffineTransform t) {
    return @{@"a": @(t.a), @"b": @(t.b), @"c": @(t.c),
             @"d": @(t.d), @"tx": @(t.tx), @"ty": @(t.ty)};
}

static BOOL Interesting(NSString *name) {
    return [name containsString:@"Icon"] || [name containsString:@"Folder"];
}

// Read existing storage, never call listLayout or layoutConfiguration getters:
// Bolders hooks those getters and changes configuration as a side effect.
static NSDictionary *StoredState(id object, NSUInteger depth) {
    if (!object || depth > 4) return @{};
    NSMutableDictionary *result = [@{@"class": NSStringFromClass([object class]),
                                    @"address": Address(object)} mutableCopy];
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    for (Class c = object_getClass(object); c && c != [NSObject class]; c = class_getSuperclass(c)) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(c, &count);
        for (unsigned int i = 0; i < count; i++) {
            Ivar ivar = ivars[i];
            const char *rawName = ivar_getName(ivar), *type = ivar_getTypeEncoding(ivar);
            if (!rawName || !type) continue;
            NSString *name = @(rawName);
            ptrdiff_t offset = ivar_getOffset(ivar);
            if (offset < 0) continue;
            const uint8_t *storage = (const uint8_t *)(__bridge void *)object + offset;
            @try {
                if (type[0] == '@') {
                    if (![name containsString:@"layout"] && ![name containsString:@"Layout"] &&
                        ![name containsString:@"Configuration"] && ![name isEqualToString:@"_icon"] &&
                        ![name isEqualToString:@"_folder"] && ![name isEqualToString:@"_image"]) continue;
                    id value = object_getIvar(object, ivar);
                    if (value) fields[name] = StoredState(value, depth + 1);
                } else if (strchr("BCcSsIiQqfd", type[0])) {
                    NSNumber *value = nil;
                    switch (type[0]) {
                        case 'B': case 'C': value = @(*(const uint8_t *)storage); break;
                        case 'c': value = @(*(const int8_t *)storage); break;
                        case 'S': value = @(*(const uint16_t *)storage); break;
                        case 's': value = @(*(const int16_t *)storage); break;
                        case 'I': value = @(*(const uint32_t *)storage); break;
                        case 'i': value = @(*(const int32_t *)storage); break;
                        case 'Q': value = @(*(const uint64_t *)storage); break;
                        case 'q': value = @(*(const int64_t *)storage); break;
                        case 'f': value = @(*(const float *)storage); break;
                        case 'd': value = @(*(const double *)storage); break;
                    }
                    if (value && isfinite(value.doubleValue)) fields[name] = value;
                }
            } @catch (NSException *exception) {
                fields[name] = @{@"exception": exception.name};
            }
        }
        free(ivars);
    }
    result[@"ivars"] = fields;
    return result;
}

static void Walk(UIView *view, NSUInteger depth) {
    if (!view || depth > 60 || ++visited > 12000) return;
    NSString *name = NSStringFromClass([view class]);
    @try {
        NSMutableDictionary *record = [@{@"class": name, @"address": Address(view),
            @"parent": Address(view.superview), @"depth": @(depth),
            @"frame": RectInfo(view.frame), @"bounds": RectInfo(view.bounds),
            @"transform": Matrix(view.transform), @"hidden": @(view.hidden),
            @"alpha": @(view.alpha), @"clipsToBounds": @(view.clipsToBounds)} mutableCopy];
        if (Interesting(name) || [view isKindOfClass:[UIImageView class]]) {
            CALayer *layer = view.layer;
            record[@"layer"] = @{@"bounds": RectInfo(layer.bounds), @"positionX": @(layer.position.x),
                @"positionY": @(layer.position.y), @"anchorX": @(layer.anchorPoint.x),
                @"anchorY": @(layer.anchorPoint.y), @"masksToBounds": @(layer.masksToBounds),
                @"contentsRect": RectInfo(layer.contentsRect), @"contentsScale": @(layer.contentsScale),
                @"maskClass": layer.mask ? NSStringFromClass([layer.mask class]) : @"none",
                @"maskBounds": layer.mask ? RectInfo(layer.mask.bounds) : @{}};
            record[@"stored"] = StoredState(view, 0);
            if ([view isKindOfClass:[UIImageView class]]) {
                UIImage *image = ((UIImageView *)view).image;
                if (image) {
                    record[@"image"] = @{@"class": NSStringFromClass([image class]), @"address": Address(image),
                        @"width": @(image.size.width), @"height": @(image.size.height), @"scale": @(image.scale),
                        @"stored": StoredState(image, 0)};
                }
            }
        }
        [records addObject:record];
        for (UIView *child in view.subviews) Walk(child, depth + 1);
    } @catch (NSException *exception) {
        [records addObject:@{@"class": name, @"address": Address(view), @"exception": exception.name}];
    }
}

__attribute__((constructor)) static void CaptureOnce(void) {
    // Guard before touching UIKit: no observer code is allowed in other apps.
    if (strcmp(getprogname(), "SpringBoard") != 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            records = [NSMutableArray array];
            visited = 0;
            NSMutableDictionary *output = [@{@"pid": @(getpid()),
                @"timestamp": @([[NSDate date] timeIntervalSince1970]),
                @"observer": @"one-shot, no hooks, no layout refresh"} mutableCopy];
            NSMutableArray *windows = [NSMutableArray array];
            for (UIWindow *window in [UIApplication sharedApplication].windows) {
                [windows addObject:@{@"class": NSStringFromClass([window class]), @"address": Address(window),
                    @"hidden": @(window.hidden), @"level": @(window.windowLevel)}];
                Walk(window, 0);
            }
            output[@"windows"] = windows;
            output[@"views"] = records;
            output[@"visited"] = @(visited);
            // Read the verified static global-byte offset only from the
            // inspected PrimalFolder image that is already loaded.
            NSMutableArray *modules = [NSMutableArray array];
            for (uint32_t i = 0; i < _dyld_image_count(); i++) {
                const char *path = _dyld_get_image_name(i);
                if (!path || !strstr(path, "/PrimalFolder2.dylib")) continue;
                mach_vm_address_t address = (mach_vm_address_t)_dyld_get_image_header(i) + 0x102d0;
                uint8_t bytes[5] = {0};
                mach_vm_size_t size = 0;
                kern_return_t status = mach_vm_read_overwrite(mach_task_self(), address, sizeof(bytes),
                    (mach_vm_address_t)bytes, &size);
                [modules addObject:@{@"path": @(path), @"base": [NSString stringWithFormat:@"%p", _dyld_get_image_header(i)],
                    @"readStatus": @(status), @"readSize": @(size),
                    @"libraryClassification": @(bytes[0]), @"disableAL": @(bytes[1]),
                    @"iconFolder": @(bytes[2]), @"keepFolder": @(bytes[3]), @"folderIcon": @(bytes[4])}];
            }
            output[@"primalGlobals"] = modules;
            NSError *error = nil;
            NSData *json = [NSJSONSerialization dataWithJSONObject:output options:NSJSONWritingPrettyPrinted error:&error];
            NSString *path = [NSString stringWithFormat:@"/tmp/folder-cover-snapshot-%d.json", getpid()];
            BOOL success = json && [json writeToFile:path options:NSDataWritingAtomic error:&error];
            NSLog(@"[FolderCoverSnapshot] pid=%d visited=%lu output=%@ success=%d error=%@",
                  getpid(), (unsigned long)visited, path, success, error);
            records = nil;
        }
    });
}

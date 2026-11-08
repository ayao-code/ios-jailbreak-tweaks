#import <UIKit/UIKit.h>
#import <IOSurface/IOSurfaceRef.h>
#import <mach/mach.h>
#import <dlfcn.h>
#import <stdio.h>
#import <string.h>

static int SDPObserveLockState(void) {
    mach_port_t (*serverPort)(void) = dlsym(RTLD_DEFAULT, "SBSSpringBoardServerPort");
    void (*queryLockState)(mach_port_t, BOOL *, BOOL *) = dlsym(RTLD_DEFAULT, "SBGetScreenLockStatus");
    if (!serverPort || !queryLockState) {
        fprintf(stderr, "lock_state_symbols_unavailable\n");
        return 7;
    }
    mach_port_t port = serverPort();
    if (port == MACH_PORT_NULL) {
        fprintf(stderr, "lock_state_server_port_unavailable\n");
        return 8;
    }
    BOOL locked = (BOOL)-1;
    BOOL passcodeEnabled = (BOOL)-1;
    queryLockState(port, &locked, &passcodeEnabled);
    if ((locked != NO && locked != YES) || (passcodeEnabled != NO && passcodeEnabled != YES)) {
        fprintf(stderr, "lock_state_query_not_observed\n");
        return 9;
    }
    NSDictionary *state = @{@"screen_locked": @(locked), @"passcode_enabled": @(passcodeEnabled),
                            @"operation": @"read_only_no_unlock_or_undim"};
    NSData *data = [NSJSONSerialization dataWithJSONObject:state options:NSJSONWritingSortedKeys error:nil];
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    return 0;
}

static int SDPWakeDisplay(void) {
    void (*undimScreen)(void) = dlsym(RTLD_DEFAULT, "SBSUndimScreen");
    if (!undimScreen) {
        fprintf(stderr, "display_wake_symbol_unavailable\n");
        return 10;
    }
    undimScreen();
    fprintf(stdout, "display_wake_requested_no_unlock\n");
    return 0;
}

static UIImage *SDPCaptureDisplay(void) {
    void (*renderDisplay)(mach_port_t, CFStringRef, IOSurfaceRef, int, int) =
        dlsym(RTLD_DEFAULT, "CARenderServerRenderDisplay");
    if (!renderDisplay) {
        fprintf(stderr, "display_render_symbol_unavailable\n");
        return nil;
    }
    CGRect bounds = UIScreen.mainScreen.nativeBounds;
    size_t width = (size_t)bounds.size.width;
    size_t height = (size_t)bounds.size.height;
    if (width == 0 || height == 0 || width > 4096 || height > 4096) {
        fprintf(stderr, "display_dimensions_invalid\n");
        return nil;
    }
    size_t rowBytes = (width * 4 + 63) & ~((size_t)63);
    NSDictionary *properties = @{(__bridge NSString *)kIOSurfaceWidth: @(width),
        (__bridge NSString *)kIOSurfaceHeight: @(height),
        (__bridge NSString *)kIOSurfaceBytesPerElement: @4,
        (__bridge NSString *)kIOSurfaceBytesPerRow: @(rowBytes),
        (__bridge NSString *)kIOSurfaceAllocSize: @(rowBytes * height),
        (__bridge NSString *)kIOSurfacePixelFormat: @((uint32_t)0x42475241)};
    IOSurfaceRef surface = IOSurfaceCreate((__bridge CFDictionaryRef)properties);
    if (!surface) {
        fprintf(stderr, "display_surface_unavailable\n");
        return nil;
    }
    if (IOSurfaceLock(surface, 0, NULL) != KERN_SUCCESS) {
        CFRelease(surface);
        fprintf(stderr, "display_surface_lock_failed\n");
        return nil;
    }
    renderDisplay(MACH_PORT_NULL, CFSTR("LCD"), surface, 0, 0);
    NSData *pixels = [NSData dataWithBytes:IOSurfaceGetBaseAddress(surface) length:rowBytes * height];
    IOSurfaceUnlock(surface, 0, NULL);
    CFRelease(surface);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
    CGColorSpaceRef colors = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate(width, height, 8, 32, rowBytes, colors,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little, provider, NULL, NO,
        kCGRenderingIntentDefault);
    UIImage *result = image ? [UIImage imageWithCGImage:image] : nil;
    if (image) {
        CGImageRelease(image);
    }
    CGColorSpaceRelease(colors);
    CGDataProviderRelease(provider);
    fprintf(stderr, "display_render_attempted_verify_screen_content\n");
    return result;
}

int main(int argumentCount, char *arguments[]) {
    @autoreleasepool {
        if (argumentCount == 2 && !strcmp(arguments[1], "--state")) {
            return SDPObserveLockState();
        }
        if (argumentCount == 2 && !strcmp(arguments[1], "--wake")) {
            return SDPWakeDisplay();
        }
        BOOL forceRender = argumentCount == 2 && !strcmp(arguments[1], "--render");
        if (argumentCount != 1 && !forceRender) {
            fprintf(stderr, "usage: screen-observe [--state|--wake|--render]\n");
            return 1;
        }
        UIImage *(*createScreenImage)(void) = dlsym(RTLD_DEFAULT, "_UICreateScreenUIImage");
        UIImage *image = !forceRender && createScreenImage ? createScreenImage() : nil;
        if (!image) {
            image = SDPCaptureDisplay();
        }
        if (!image || image.size.width <= 0 || image.size.height <= 0) {
            fprintf(stderr, "screen_capture_returned_no_image\n");
            return 3;
        }
        NSData *data = UIImagePNGRepresentation(image);
        if (!data) {
            fprintf(stderr, "screen_capture_encoding_failed\n");
            return 4;
        }
        if (fwrite(data.bytes, 1, data.length, stdout) != data.length) {
            fprintf(stderr, "screen_capture_output_failed\n");
            return 5;
        }
        return 0;
    }
}

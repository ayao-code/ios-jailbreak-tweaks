#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <dlfcn.h>

@interface NSObject (CCModuleTest)
- (BOOL)isSelected;
- (void)setSelected:(BOOL)selected;
- (BOOL)failed;
- (UIImage *)iconGlyph;
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 2;
        NSString *path = @(argv[1]);
        if (![path hasSuffix:@"/FeilianControlCenter.bundle"]) return 2;
        dlopen("/System/Library/PrivateFrameworks/ControlCenterUIKit.framework/ControlCenterUIKit", RTLD_NOW);
        NSBundle *bundle = [NSBundle bundleWithPath:path];
        NSError *error = nil;
        if (![bundle loadAndReturnError:&error]) { NSLog(@"module load failed: %@", error); return 3; }
        id module = [bundle.principalClass new];
        if (!module) return 4;
        CFAbsoluteTime begin = CFAbsoluteTimeGetCurrent();
        NSDate *warmup = [NSDate dateWithTimeIntervalSinceNow:0.5];
        while (warmup.timeIntervalSinceNow > 0)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        CFAbsoluteTime callBegin = CFAbsoluteTimeGetCurrent();
        [module setSelected:YES];
        printf("module_callback_return_ms=%.3f\n", (CFAbsoluteTimeGetCurrent() - callBegin) * 1000);
        fflush(stdout);
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:17];
        while (deadline.timeIntervalSinceNow > 0)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        printf("elapsed=%.3f selected=%d failed=%d glyph_present=%d\n",
            CFAbsoluteTimeGetCurrent() - begin, [module isSelected], [module failed], [module iconGlyph] != nil);
        // Standalone callback verification is not a real Control Center tap.
        return 0;
    }
}

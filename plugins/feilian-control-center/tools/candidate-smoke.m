// Standalone construction/state checks only; never invokes a VPN command.
#import <UIKit/UIKit.h>
#import <dlfcn.h>

@interface NSObject (VPNCandidateSmoke)
- (id)contentViewController;
- (id)vpn;
- (BOOL)ready;
- (BOOL)busy;
- (BOOL)connected;
- (NSString *)preferredProvider;
- (NSString *)activeProvider;
- (CGFloat)preferredExpandedContentHeight;
- (BOOL)shouldBeginTransitionToExpandedContentModule;
- (void)willTransitionToExpandedContentMode:(BOOL)expanded;
- (void)didTransitionToExpandedContentMode:(BOOL)expanded;
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 2;
        dlopen("/System/Library/PrivateFrameworks/ControlCenterUIKit.framework/ControlCenterUIKit", RTLD_NOW);
        NSBundle *bundle = [NSBundle bundleWithPath:@(argv[1])];
        NSError *error = nil;
        if (!bundle || ![bundle loadAndReturnError:&error]) {
            printf("bundle_present=%d bundle_load_error=%ld domain=%s\n", bundle != nil,
                (long)error.code, error.domain.UTF8String);
            NSLog(@"candidate bundle error: %@", error.localizedDescription);
            NSLog(@"candidate failure reason: %@", error.localizedFailureReason);
            return 3;
        }
        id module = [bundle.principalClass new];
        UIViewController *viewController = [module contentViewController];
        [viewController loadViewIfNeeded];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:5]];
        id vpn = [(id)viewController vpn];
        printf("ready=%d busy=%d connected=%d preferred=%s active=%s\n", [vpn ready], [vpn busy], [vpn connected],
            [[vpn preferredProvider] UTF8String], [[vpn activeProvider] UTF8String]);
        BOOL expandable = [(id)viewController shouldBeginTransitionToExpandedContentModule];
        [(id)viewController willTransitionToExpandedContentMode:YES];
        [(id)viewController didTransitionToExpandedContentMode:YES];
        [viewController.view layoutIfNeeded];
        printf("expandable=%d expanded_height=%.1f view_loaded=%d\n", expandable,
            [(id)viewController preferredExpandedContentHeight], viewController.isViewLoaded);
        [(id)viewController willTransitionToExpandedContentMode:NO];
        [(id)viewController didTransitionToExpandedContentMode:NO];
        return [vpn ready] && expandable ? 0 : 1;
    }
}

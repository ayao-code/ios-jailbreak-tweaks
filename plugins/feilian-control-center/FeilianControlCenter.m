#import <ControlCenterUIKit/CCUIContentModule-Protocol.h>
#import "VPNModuleViewController.h"

@interface FeilianControlCenter : NSObject <CCUIContentModule>
@property (nonatomic, strong) VPNModuleViewController *controller;
@end

@implementation FeilianControlCenter
- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _controller = [VPNModuleViewController new];
    _controller.vpn = [AYAVPNController new];
    return self;
}
- (UIViewController<CCUIContentModuleContentViewController> *)contentViewController { return self.controller; }
- (UIViewController *)backgroundViewController { return nil; }
@end

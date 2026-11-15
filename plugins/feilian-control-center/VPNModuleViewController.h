#import <UIKit/UIKit.h>
#import <ControlCenterUIKit/CCUIContentModuleContentViewController-Protocol.h>
#import "VPNController.h"
#import "CCUIMenuModuleViewController.h"

@interface VPNModuleViewController : CCUIMenuModuleViewController
@property (nonatomic, strong) AYAVPNController *vpn;
@end

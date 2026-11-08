#import <ControlCenterUIKit/CCUIToggleModule.h>
#import <UIKit/UIKit.h>
#import "FeilianVPNController.h"

@interface FeilianControlCenter : CCUIToggleModule
@property (nonatomic, strong) FeilianVPNController *vpn;
@property (nonatomic) BOOL failed;
@end

@implementation FeilianControlCenter
- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _vpn = [FeilianVPNController new];
    __weak typeof(self) weakSelf = self;
    _vpn.stateChanged = ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf.vpn.connected) strongSelf.failed = NO;
        [strongSelf refreshState];
    };
    _vpn.operationFailed = ^(NSString *message) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.failed = YES;
        NSLog(@"[FeilianCC] %@", message);
        [strongSelf refreshState];
    };
    return self;
}
- (BOOL)isSelected { return self.vpn.selected; }
- (void)setSelected:(BOOL)selected {
    if (!self.vpn.busy) {
        self.failed = NO;
        [self refreshState];
        [self.vpn requestSelected:selected];
    }
}
- (UIImage *)iconGlyph {
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:27 weight:UIImageSymbolWeightSemibold];
    return [UIImage systemImageNamed:self.failed ? @"exclamationmark.shield" : @"shield.lefthalf.filled" withConfiguration:configuration];
}
- (UIImage *)selectedIconGlyph { return self.iconGlyph; }
- (UIColor *)selectedColor { return UIColor.systemBlueColor; }
@end

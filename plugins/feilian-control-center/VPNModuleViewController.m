#import "VPNModuleViewController.h"
#import "Shared/VPNIPC.h"

@implementation VPNModuleViewController {
    UIActivityIndicatorView *_connectionIndicator;
    BOOL _expanded;
}
- (BOOL)shouldBeginTransitionToExpandedContentModule { return YES; }
- (BOOL)shouldFinishTransitionToExpandedContentModule { return YES; }
- (BOOL)_canShowWhileLocked { return NO; }
- (void)viewDidLoad {
    [super viewDidLoad];
    _connectionIndicator=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _connectionIndicator.color=UIColor.whiteColor;
    _connectionIndicator.hidesWhenStopped=YES;
    _connectionIndicator.userInteractionEnabled=NO;
    _connectionIndicator.isAccessibilityElement=NO;
    [self.buttonView addSubview:_connectionIndicator];
    __weak typeof(self) weakSelf = self;
    self.vpn.stateChanged = ^{ [weakSelf refresh]; };
    [self refresh];
}
- (void)refresh {
    if (!self.isViewLoaded) return;
    self.glyphImage = (self.vpn.busy && !_expanded) ? nil : [UIImage systemImageNamed:
        (self.vpn.failed ? @"exclamationmark.shield" : @"shield.lefthalf.filled")
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:27 weight:UIImageSymbolWeightSemibold]];
    self.selected = self.vpn.connected;
    self.selectedGlyphColor = UIColor.systemBlueColor;
    // Avoid the stock off-center menu busy glyph. Our compact progress view is
    // centered in the actual button and never intercepts a menu or tap gesture.
    self.busy = NO;
    if(self.vpn.busy && !_expanded)[_connectionIndicator startAnimating];
    else [_connectionIndicator stopAnimating];
    self.title = @"VPN 控制中心";
    self.subtitle = [NSString stringWithFormat:@"下次：%@ · 当前：%@\n%@", VPNProviderName(self.vpn.preferredProvider),
            VPNProviderName(self.vpn.activeProvider), self.vpn.message];
    self.view.accessibilityLabel = @"VPN 控制中心";
    self.view.accessibilityValue = self.subtitle;
    [self removeAllActions]; [self removeFooterButton];
    __weak typeof(self) weakSelf = self;
    for (NSString *provider in VPNProviders()) {
        NSString *title = [NSString stringWithFormat:@"%@%@%@", [self.vpn.preferredProvider isEqual:provider] ? @"✓ " : @"", VPNProviderName(provider),
            [@[@"jump",@"gofast"] containsObject:provider]?@" · Beta":@""];
        [self addActionWithTitle:title subtitle:[self.vpn statusForProvider:provider]
            glyph:[UIImage systemImageNamed:@"shield.lefthalf.filled"] handler:^{ [weakSelf select:provider]; }];
    }
    [self setFooterButtonTitle:[NSString stringWithFormat:@"打开 %@", VPNProviderName(self.vpn.preferredProvider)] handler:^{ [weakSelf.vpn openPreferredApp]; }];
    [self.view setNeedsLayout];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *button=self.buttonView;
    if(_connectionIndicator.superview!=button)[button addSubview:_connectionIndicator];
    _connectionIndicator.center=CGPointMake(CGRectGetMidX(button.bounds),CGRectGetMidY(button.bounds));
    [button bringSubviewToFront:_connectionIndicator];
}
- (void)buttonTapped:(id)sender forEvent:(UIEvent *)event {
    (void)sender; (void)event;
    // Never call the stock toggle implementation: the controller owns real state.
    [self.vpn toggle];
}
- (void)select:(NSString *)provider {
    NSDictionary *intent = [self.vpn selectionIntent:provider]; if (!intent) return;
    [self.vpn applySelection:intent];
    [self refresh];
}
- (void)willTransitionToExpandedContentMode:(BOOL)expanded {
    _expanded=expanded;
    [super willTransitionToExpandedContentMode:expanded];
    [self refresh];
}
- (void)didTransitionToExpandedContentMode:(BOOL)expanded {
    [super didTransitionToExpandedContentMode:expanded]; [self refresh];
}
- (void)controlCenterWillPresent { [self.vpn reload]; }
- (void)controlCenterDidDismiss { }
@end

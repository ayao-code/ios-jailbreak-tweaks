#import "ASGTip.h"

static __weak UILabel *ASGCurrentTip;

void ASGRemoveSuccessTip(void) {
    if (!NSThread.isMainThread) return;
    [ASGCurrentTip removeFromSuperview];
    ASGCurrentTip = nil;
}

void ASGShowSuccessTip(UIWindow *window) {
    if (!NSThread.isMainThread || !window || window.hidden || window.bounds.size.width <= 48
        || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    ASGRemoveSuccessTip();
    UILabel *tip = [UILabel new];
    tip.text = @"AutoSkipGuard · 已关闭广告";
    tip.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    tip.textAlignment = NSTextAlignmentCenter;
    tip.textColor = UIColor.whiteColor;
    tip.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.72];
    tip.userInteractionEnabled = NO;
    tip.isAccessibilityElement = NO;
    tip.accessibilityIdentifier = @"ayao.AutoSkipGuard.successTip";
    tip.layer.cornerRadius = 11;
    tip.layer.masksToBounds = YES;
    CGSize size = [tip sizeThatFits:CGSizeMake(MAX(1, window.bounds.size.width - 32), 22)];
    CGFloat width = MIN(size.width + 20, window.bounds.size.width - 32);
    tip.frame = CGRectMake(CGRectGetMidX(window.bounds) - width / 2,
                           window.bounds.origin.y + window.safeAreaInsets.top + 4, width, 22);
    [window addSubview:tip];
    ASGCurrentTip = tip;
    // Capture weakly; no timer, background task, layout hook or window retained.
    __weak UILabel *weakTip = tip;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        UILabel *label = weakTip;
        [label removeFromSuperview];
        if (ASGCurrentTip == label) ASGCurrentTip = nil;
    });
}

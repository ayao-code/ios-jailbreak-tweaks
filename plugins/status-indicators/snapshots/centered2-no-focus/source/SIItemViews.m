#import "SIItemViews.h"
#import "Shared/SIPresentation.h"

static NSAttributedString *SIAttributedSpeed(NSString *text, SISpeedStyle style, UIFont *font, UIColor *color) {
    if (!text.length) return [[NSAttributedString alloc] initWithString:@""];
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] initWithString:text];
    [result addAttributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: color} range:NSMakeRange(0, text.length)];
    NSString *arrows = @"↓↑";
    // Only the first unit letter follows the numeric part. In the full form
    // "KB/s" this avoids inserting a second gap between K and B.
    NSString *units = @"KMG";
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        if ([arrows containsString:substring] && style.arrowGap > 0 && NSMaxRange(substringRange) < text.length) {
            [result addAttribute:NSKernAttributeName value:@(style.arrowGap) range:substringRange];
        }
    }];
    for (NSUInteger index = 0; index < text.length; index++) {
        unichar character = [text characterAtIndex:index];
        if ([units rangeOfString:[NSString stringWithFormat:@"%C", character]].location != NSNotFound && style.unitGap > 0 && index > 0) {
            [result addAttribute:NSKernAttributeName value:@(style.unitGap) range:NSMakeRange(index - 1, 1)];
        }
    }
    return result;
}
static void SISetFrame(UIView *view, CGRect bounds, double x, double y, double size, double height) {
    SIItemFrame f = SIPlaceItem(bounds.size.width, bounds.size.height, size, height, x, y);
    CGRect frame = CGRectMake(bounds.origin.x + f.x, bounds.origin.y + f.y, f.width, f.height);
    if (!CGRectEqualToRect(view.frame, frame)) view.frame = frame;
}
static void SISetCenteredFrame(UIView *view, CGRect bounds, CGFloat x, CGFloat width, CGFloat height, CGFloat offsetY) {
    if (!view || width <= 0 || height <= 0) return;
    SIItemFrame placement=SIPlaceItem(bounds.size.width,bounds.size.height,width,height,50,offsetY);
    CGRect frame=CGRectMake(bounds.origin.x+x, bounds.origin.y+placement.y, width, height);
    if (!CGRectEqualToRect(view.frame,frame)) view.frame=frame;
}
@implementation SIItemViews {
    UIImageView *_vpn;
    UIImageView *_mute;
    UILabel *_vpnText;
    UILabel *_speed;
    CGSize _speedSize;
    NSAttributedString *_speedAttributedText;
    BOOL _detached;
    unsigned _vpnStyle, _weight;
}
- (instancetype)initWithHost:(UIView *)host {
    if ((self = [super init])) {
        // SF Symbols are cached by UIKit; no drawing, OCR, bitmap generation or downloading.
        _vpn = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.shield.fill"]];
        _mute = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"bell.slash.fill"]];
        _speed = [UILabel new]; _speed.numberOfLines = 2; _speed.textAlignment = NSTextAlignmentCenter;
        _vpnText = [UILabel new]; _vpnText.text = @"VPN"; _vpnText.textAlignment = NSTextAlignmentCenter;
        _vpnStyle = _weight = UINT_MAX;
        for (UIView *view in @[_vpn, _mute, _vpnText, _speed]) {
            view.userInteractionEnabled = NO; view.isAccessibilityElement = NO;
            view.backgroundColor = UIColor.clearColor; view.hidden = YES;
            view.layer.shadowOpacity=0; view.layer.shouldRasterize=NO; view.layer.masksToBounds=YES;
            [host addSubview:view];
        }
        _vpn.contentMode = UIViewContentModeScaleAspectFit;
        _mute.contentMode = UIViewContentModeScaleAspectFit;
    }
    return self;
}
- (void)moveToContainer:(UIView *)container {
    if (_detached || !container) return;
        for (UIView *view in @[_vpn, _mute, _vpnText, _speed]) {
        if (view.superview != container) {
            [view removeFromSuperview];
            [container addSubview:view];
        }
    }
}
- (void)renderVPN:(BOOL)vpn mute:(BOOL)mute speed:(NSString *)speed
       speedStyle:(SISpeedStyle)speedStyle
           color:(UIColor *)color bounds:(CGRect)bounds layout:(SIItemLayout)layout style:(SIItemStyle)style {
    if (_detached) return;
    [UIView performWithoutAnimation:^{
    // Avoid changing hidden on every layout when it is already correct.
    BOOL vpnImage = vpn && style.vpnStyle != 3, vpnText = vpn && style.vpnStyle == 3;
    BOOL muteImage = mute;
    if (_vpn.hidden == vpnImage) _vpn.hidden = !vpnImage;
    if (_vpnText.hidden == vpnText) _vpnText.hidden = !vpnText;
    if (_mute.hidden == muteImage) _mute.hidden = !muteImage;
    BOOL hasSpeed = speed.length > 0;
    if (_speed.hidden == hasSpeed) _speed.hidden = !hasSpeed;
    if (![_vpn.tintColor isEqual:color]) _vpn.tintColor = color;
    if (![_mute.tintColor isEqual:color]) _mute.tintColor = color;
    if (![_speed.textColor isEqual:color]) _speed.textColor = color;
    if (![_vpnText.textColor isEqual:color]) _vpnText.textColor = color;
    UIFontWeight weight = style.weight == 0 ? UIFontWeightRegular : (style.weight == 2 ? UIFontWeightBold : UIFontWeightMedium);
    if (_vpnStyle != style.vpnStyle || _weight != style.weight) {
        NSArray *names=@[@"lock.shield.fill", @"checkmark.shield.fill"];
        UIImageSymbolWeight symbolWeight=style.weight==2 ? UIImageSymbolWeightBold : (style.weight==1 ? UIImageSymbolWeightMedium : UIImageSymbolWeightRegular);
        UIImageSymbolConfiguration *configuration=[UIImageSymbolConfiguration configurationWithWeight:symbolWeight];
        _vpn.image=[UIImage systemImageNamed:names[MIN(style.vpnStyle,1u)] withConfiguration:configuration];
        _vpnStyle=style.vpnStyle;
    }
    for (UIView *view in @[_vpn,_mute,_vpnText,_speed]) if (view.alpha!=style.opacity) view.alpha=style.opacity;
    BOOL fontChanged = _speed.font.pointSize != layout.speedFont || _weight != style.weight;
    if (fontChanged)
        _speed.font = [UIFont monospacedDigitSystemFontOfSize:layout.speedFont weight:weight];
    if (_vpnText.font.pointSize!=layout.vpnSize || _weight!=style.weight) _vpnText.font=[UIFont systemFontOfSize:layout.vpnSize weight:weight];
    _weight=style.weight;
    NSAttributedString *attributedSpeed = SIAttributedSpeed(speed, speedStyle, _speed.font, color);
    BOOL textChanged = ![_speedAttributedText isEqualToAttributedString:attributedSpeed];
    BOOL changed = textChanged || fontChanged;
    if (textChanged) {
        _speedAttributedText = attributedSpeed;
        _speed.attributedText = attributedSpeed;
    }
    if (changed && hasSpeed) {
        _speed.numberOfLines=[speed containsString:@"\n"] ? 2 : 1;
        _speedSize = [_speed sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
    }
    if (vpnImage) SISetFrame(_vpn, bounds, layout.vpnX, layout.vpnY, layout.vpnSize, layout.vpnSize);
    if (vpnText) {
        CGSize size=[_vpnText sizeThatFits:CGSizeMake(60,30)];
        SISetFrame(_vpnText,bounds,layout.vpnX,layout.vpnY,MIN(60,size.width+2),size.height);
    }
    if (muteImage) SISetFrame(_mute, bounds, layout.muteX, layout.muteY, layout.muteSize, layout.muteSize);
    if (hasSpeed) {
        CGSize size = _speedSize;
        SISetFrame(_speed, bounds, layout.speedX, layout.speedY, MAX(12, size.width + 2), size.height);
    }
    if (layout.centeredGroup) {
        BOOL showVPNItem=vpnImage || vpnText;
        BOOL showMuteItem=muteImage;
        BOOL showSpeedItem=hasSpeed;
        CGSize vpnTextSize=showVPNItem && vpnText ? [_vpnText sizeThatFits:CGSizeMake(60,30)] : CGSizeZero;
        CGFloat vpnWidth=vpnText ? MIN(60, vpnTextSize.width+2) : layout.vpnSize;
        CGFloat muteWidth=layout.muteSize;
        CGFloat speedWidth=MAX(12, layout.speedGroupWidth);
        NSUInteger count=(showVPNItem?1:0)+(showMuteItem?1:0)+(showSpeedItem?1:0);
        CGFloat totalWidth=(showVPNItem?vpnWidth:0)+(showMuteItem?muteWidth:0)+(showSpeedItem?speedWidth:0)
            + (count>1 ? layout.groupGap*(count-1) : 0);
        CGFloat cursor=(bounds.size.width-totalWidth)/2.0;
        if (showVPNItem) {
            CGFloat height=vpnText ? vpnTextSize.height : layout.vpnSize;
            SISetCenteredFrame(vpnText ? _vpnText : _vpn,bounds,cursor,vpnWidth,height,vpnText ? layout.vpnY : layout.vpnY);
            cursor+=vpnWidth+layout.groupGap;
        }
        if (showMuteItem) {
            SISetCenteredFrame(_mute,bounds,cursor,muteWidth,muteWidth,layout.muteY);
            cursor+=muteWidth+layout.groupGap;
        }
        if (showSpeedItem) SISetCenteredFrame(_speed,bounds,cursor,speedWidth,_speedSize.height,layout.speedY);
    }
    }];
}
- (void)hide {
    if (!_vpn.hidden) _vpn.hidden = YES;
    if (!_mute.hidden) _mute.hidden = YES;
    if (!_vpnText.hidden) _vpnText.hidden = YES;
    if (!_speed.hidden) _speed.hidden = YES;
}
- (void)detach {
    [UIView performWithoutAnimation:^{
        [self hide];
        [self->_vpn.layer removeAllAnimations]; [self->_mute.layer removeAllAnimations]; [self->_vpnText.layer removeAllAnimations]; [self->_speed.layer removeAllAnimations];
        [self->_vpn removeFromSuperview]; [self->_mute removeFromSuperview]; [self->_vpnText removeFromSuperview]; [self->_speed removeFromSuperview];
    }];
    _detached = YES;
}
- (CGRect)frameForItem:(NSString *)item {
    if ([item isEqualToString:@"vpn"]) return _vpnStyle==3 ? _vpnText.frame : _vpn.frame;
    if ([item isEqualToString:@"mute"]) return _mute.frame;
    return _speed.frame;
}
@end

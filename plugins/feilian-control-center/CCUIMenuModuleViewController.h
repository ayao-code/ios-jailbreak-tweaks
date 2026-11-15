// Narrow declarations verified read-only on iOS 16.3.1, 2026-11-14.
#import <UIKit/UIKit.h>
#import <ControlCenterUIKit/CCUIContentModuleContentViewController-Protocol.h>

@interface CCUIButtonModuleViewController : UIViewController
@property (nonatomic, strong) UIImage *glyphImage;
@property (nonatomic, strong) UIColor *glyphColor;
@property (nonatomic, strong) UIColor *selectedGlyphColor;
@property (nonatomic, getter=isSelected) BOOL selected;
- (UIView *)buttonView;
- (void)buttonTapped:(id)sender forEvent:(UIEvent *)event;
- (void)willTransitionToExpandedContentMode:(BOOL)expanded;
- (void)didTransitionToExpandedContentMode:(BOOL)expanded;
@end
@interface CCUIMenuModuleViewController : CCUIButtonModuleViewController <CCUIContentModuleContentViewController>
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, getter=isBusy) BOOL busy;
- (void)removeAllActions;
- (void)addActionWithTitle:(NSString *)title subtitle:(NSString *)subtitle glyph:(UIImage *)glyph handler:(void (^)(void))handler;
- (void)setFooterButtonTitle:(NSString *)title handler:(void (^)(void))handler;
- (void)removeFooterButton;
@end

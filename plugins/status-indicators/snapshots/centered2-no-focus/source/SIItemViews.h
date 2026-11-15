#import "SIConfiguration.h"
// Lightweight labels hosted by a dedicated overlay container.
@interface SIItemViews : NSObject
- (instancetype)initWithHost:(UIView *)host;
- (void)moveToContainer:(UIView *)container;
- (void)renderVPN:(BOOL)vpn mute:(BOOL)mute
             speed:(NSString *)speed
       speedStyle:(SISpeedStyle)speedStyle
           color:(UIColor *)color bounds:(CGRect)bounds layout:(SIItemLayout)layout style:(SIItemStyle)style;
- (CGRect)frameForItem:(NSString *)item;
- (void)hide;
- (void)detach;
@end

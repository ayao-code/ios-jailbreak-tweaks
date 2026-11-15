#import <UIKit/UIKit.h>
@interface SIController : NSObject
+ (instancetype)shared;
- (void)start;
- (void)reloadPreferences;
- (void)refreshVisibility;
- (void)requestLayout;
- (void)hostDidChange:(UIView *)host readCurrentData:(BOOL)readData;
- (void)rememberHost:(UIView *)host;
- (void)writeDiagnosticSnapshot;
@end

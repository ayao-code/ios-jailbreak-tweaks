from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parents[1];out=Path(sys.argv[1]);source=(root/'SIController.m').read_text()
def extract(name):
 start=source.index(name);brace=source.index('{',start);end=brace+1;depth=1
 while depth:depth+=(source[end]=='{')-(source[end]=='}');end+=1
 return source[start:end]
functions='\n'.join(extract(name) for name in ['static UIWindow *SIStatusWindowForHost','static BOOL SIWindowVisible','static BOOL SIReadManagerFlag','static BOOL SILandscapeSystemAllowsOverlay','static UIView *SILandscapeContainerForHost'])
harness=r'''
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>
#include <assert.h>
#include <string.h>
typedef NSInteger UISceneActivationState;
enum { UISceneActivationStateUnattached=-1,UISceneActivationStateForegroundActive=0,UISceneActivationStateForegroundInactive=1,UISceneActivationStateBackground=2 };
@interface UIScreen:NSObject
+ (id)mainScreen;
@end
@implementation UIScreen
+ (id)mainScreen { static id s; if(!s)s=[self new]; return s; }
@end
@class UIWindow;
@interface UIWindowScene:NSObject
@property NSInteger activationState;
@property(strong) NSArray *windows;
@end
@implementation UIWindowScene
@end
@interface UIView:NSObject
@property BOOL hidden;
@property double alpha;
@property CGRect bounds,projection;
@property(weak) UIView *superview;
@property(weak) UIWindow *window;
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;
@end
@implementation UIView
- (instancetype)init { if((self=[super init]))_alpha=1;return self; }
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view { (void)view;return CGRectIsEmpty(_projection)?rect:_projection; }
@end
@interface UIWindow:UIView
@property(strong) UIScreen *screen;
@property(strong) UIWindowScene *windowScene;
@end
@implementation UIWindow
@end
@interface SBMainSwitcherWindow:UIWindow @end
@implementation SBMainSwitcherWindow @end
@interface SBFTouchPassThroughView:UIView @end
@implementation SBFTouchPassThroughView @end
@interface UIStatusBar_Modern:UIView @end
@implementation UIStatusBar_Modern @end
@interface SBHomeScreenWindow:UIWindow @end
@implementation SBHomeScreenWindow @end
@interface SBCoverSheetWindow:UIWindow @end
@implementation SBCoverSheetWindow @end
@interface SBControlCenterWindow:UIWindow @end
@implementation SBControlCenterWindow @end
static BOOL locked,switcher,cc;
static unsigned gateReads;
@interface SBLockScreenManager:NSObject
+ (id)sharedInstance;
- (BOOL)isUILocked;
@end
@implementation SBLockScreenManager
+ (id)sharedInstance { static id s;if(!s)s=[self new];return s; }
- (BOOL)isUILocked { gateReads++;return locked; }
@end
@interface SBMainSwitcherControllerCoordinator:NSObject
+ (id)sharedInstanceIfExists;
- (BOOL)isAnySwitcherVisible;
@end
@implementation SBMainSwitcherControllerCoordinator
+ (id)sharedInstanceIfExists { static id s;if(!s)s=[self new];return s; }
- (BOOL)isAnySwitcherVisible { gateReads++;return switcher; }
@end
@interface SBControlCenterController:NSObject
+ (id)sharedInstanceIfExists;
- (BOOL)isPresentedOrDismissing;
@end
@implementation SBControlCenterController
+ (id)sharedInstanceIfExists { static id s;if(!s)s=[self new];return s; }
- (BOOL)isPresentedOrDismissing { gateReads++;return cc; }
@end
FUNCTIONS
int main(void) { @autoreleasepool {
 SBMainSwitcherWindow *w=[SBMainSwitcherWindow new];w.bounds=CGRectMake(0,0,375,812);w.screen=UIScreen.mainScreen;
 w.windowScene=[UIWindowScene new];w.windowScene.activationState=UISceneActivationStateForegroundInactive;w.windowScene.windows=@[w];
 SBFTouchPassThroughView *container=[SBFTouchPassThroughView new];container.bounds=CGRectMake(0,0,812,375);container.projection=w.bounds;container.superview=w;container.window=w;
 UIStatusBar_Modern *wrapper=[UIStatusBar_Modern new];wrapper.bounds=CGRectMake(0,0,812,0);wrapper.hidden=YES;wrapper.alpha=0;wrapper.superview=container;wrapper.window=w;
 UIView *host=[UIView new];host.bounds=wrapper.bounds;host.superview=wrapper;host.window=w;
 assert(SILandscapeContainerForHost(host)==container); // Hidden zero-height native bar.
 locked=YES;assert(!SILandscapeContainerForHost(host));locked=NO;
 switcher=YES;assert(!SILandscapeContainerForHost(host));switcher=NO;
 cc=YES;assert(!SILandscapeContainerForHost(host));cc=NO;
 container.hidden=YES;assert(!SILandscapeContainerForHost(host));container.hidden=NO;
 container.alpha=.5;assert(!SILandscapeContainerForHost(host));container.alpha=1;
 container.projection=CGRectMake(0,100,375,812);assert(!SILandscapeContainerForHost(host));container.projection=w.bounds;
 container.bounds=CGRectMake(0,0,375,812);gateReads=0;assert(!SILandscapeContainerForHost(host));assert(!gateReads);container.bounds=CGRectMake(0,0,812,375);
 SBControlCenterWindow *ccWindow=[SBControlCenterWindow new];w.windowScene.windows=@[w,ccWindow];assert(!SILandscapeContainerForHost(host));ccWindow.hidden=YES;assert(SILandscapeContainerForHost(host)==container);
 w.windowScene.activationState=UISceneActivationStateBackground;assert(!SILandscapeContainerForHost(host));w.windowScene.activationState=UISceneActivationStateForegroundInactive;
 SBCoverSheetWindow *cover=[SBCoverSheetWindow new];w.windowScene.windows=@[w,cover];assert(!SILandscapeContainerForHost(host));
 SBHomeScreenWindow *home=[SBHomeScreenWindow new];w.windowScene.windows=@[w,cover,home];assert(SILandscapeContainerForHost(host)==container);
 BOOL unknown=YES;assert(!SIReadManagerFlag(@"NoSuchManager",@"sharedInstance",@"isVisible",&unknown));assert(unknown);
 assert(!SIReadManagerFlag(@"SBLockScreenManager",@"sharedInstance",@"noSuchFlag",&unknown));assert(unknown);
 puts("PASS actual landscape eligibility: hidden native bar allowed; lock/CC/switcher/background/partial projection rejected; portrait avoids gate queries; unknown selectors fail closed");
 }return 0; }
'''.replace('FUNCTIONS',functions)
path=out/'visibility_harness.m';path.write_text(harness);subprocess.run(['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-framework','Foundation','-framework','CoreGraphics',str(path),'-o',str(out/'visibility-harness')],check=True);subprocess.run([str(out/'visibility-harness')],check=True)

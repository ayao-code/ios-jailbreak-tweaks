#import <UIKit/UIKit.h>
#import <dlfcn.h>

#if ASG_ORIGINAL_FIXTURE
static void ASGFixtureStart(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillEnterForegroundNotification object:UIApplication.sharedApplication];
}
#elif ASG_PAYLOAD_FIXTURE
static void ASGFixtureStart(void) {
    // Independent fixture scenes must not inherit an earlier active probe cycle or Tip.
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:UIApplication.sharedApplication];
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:UIApplication.sharedApplication];
}
#else
extern void ASGFixtureStart(void);
#endif

@interface ASGFixtureSplashAdView : UIView
@end
@implementation ASGFixtureSplashAdView
@end

@interface ASGFixtureController : UIViewController
@property(nonatomic, strong) UIView *overlay;
@property(nonatomic, strong) UILabel *status;
@property(nonatomic, copy) NSString *scenario;
@property(nonatomic) BOOL delayed;
@property(nonatomic) unsigned actions;
@property(nonatomic) unsigned touchChecks;
@property(nonatomic, copy) NSString *runID;
@end

@implementation ASGFixtureController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
    self.status = [[UILabel alloc] initWithFrame:CGRectMake(20, 70, self.view.bounds.size.width - 40, 40)];
    self.status.text = @"Fixture home / no ad action"; self.status.font = [UIFont systemFontOfSize:14];
    [self.view addSubview:self.status];
    UIButton *touchCheck = [UIButton buttonWithType:UIButtonTypeSystem];
    touchCheck.frame = CGRectMake(90, self.view.safeAreaInsets.top + 4, self.view.bounds.size.width - 180, 22);
    touchCheck.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [touchCheck setTitle:@"Touch check" forState:UIControlStateNormal];
    touchCheck.accessibilityIdentifier = @"fixture.tipUnderlyingButton";
    [touchCheck addTarget:self action:@selector(touchCheck:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:touchCheck];
    NSArray *scenes = @[@"native", @"label-gesture", @"disabled-countdown", @"close-countdown", @"arrow-overlay",
                       @"slow-exit", @"image-ocr", @"root-native", @"duplicate-ambiguous", @"normal-login", @"late-ad"];
    for (NSUInteger i = 0; i < scenes.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.frame = CGRectMake(20, 120 + i * 38, self.view.bounds.size.width - 40, 32);
        [button setTitle:scenes[i] forState:UIControlStateNormal]; button.tag = i;
        [button addTarget:self action:@selector(selectScene:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:button];
    }
}
- (void)selectScene:(UIButton *)sender {
    NSArray *scenes = @[@"native", @"label-gesture", @"disabled-countdown", @"close-countdown", @"arrow-overlay",
                       @"slow-exit", @"image-ocr", @"root-native", @"duplicate-ambiguous", @"normal-login", @"late-ad"];
    [self start:scenes[sender.tag]];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    for (UIView *view in self.view.subviews) if ([view.accessibilityIdentifier isEqual:@"fixture.tipUnderlyingButton"]) {
        view.frame = CGRectMake(90, self.view.safeAreaInsets.top + 4, self.view.bounds.size.width - 180, 22);
    }
}
- (void)start:(NSString *)name {
    [self.overlay removeFromSuperview]; self.overlay = nil;
    self.scenario = name; self.actions = 0; self.delayed = [name isEqual:@"slow-exit"];
    self.runID = NSUUID.UUID.UUIDString;
    [self writeActionRecord]; // Current run baseline: never infer zero from a stale prior file.
    if ([name isEqual:@"empty-window"]) {
        ASGFixtureStart();
    } else if ([name isEqual:@"late-ad"] || [name isEqual:@"late-image-6"]) {
        ASGFixtureStart();
        double delay = [name isEqual:@"late-image-6"] ? 6 : 8;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSURL *docs = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
            [@{@"scenario": self.scenario ?: @"", @"runID": self.runID ?: @"", @"uptime": @(NSProcessInfo.processInfo.systemUptime)}
                writeToURL:[docs URLByAppendingPathComponent:@"scene-presented.plist"] atomically:YES];
            [self presentScene:[name isEqual:@"late-image-6"] ? @"image-ocr" : @"native"];
        });
    } else { [self presentScene:name]; ASGFixtureStart(); }
}
- (void)presentScene:(NSString *)name {
    BOOL ordinary = [name isEqual:@"ordinary-overlay"] || [name isEqual:@"source-sibling"];
    UIView *overlay = [[(ordinary ? UIView.class : ASGFixtureSplashAdView.class) alloc] initWithFrame:self.view.bounds];
    overlay.backgroundColor = [UIColor colorWithRed:.10 green:.24 blue:.58 alpha:1];
    [self.view addSubview:overlay]; self.overlay = overlay;
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 230, overlay.bounds.size.width - 40, 70)];
    title.text = @"CONTROLLED AD FIXTURE"; title.textColor = UIColor.whiteColor; title.textAlignment = NSTextAlignmentCenter;
    [overlay addSubview:title];
    CGRect entry = CGRectMake(overlay.bounds.size.width - 115, 90, 100, 30);
    if ([name isEqual:@"image-middle"]) entry.origin.y = overlay.bounds.size.height * .60;
    NSString *text = [name isEqual:@"close-countdown"] ? @"关闭｜4s" : ([name isEqual:@"arrow-overlay"] ? @">>" : @"跳过广告 4s");
    if ([name isEqual:@"normal-login"]) text = @"关闭登录";
    if ([name isEqual:@"natural-expiry"]) text = @"跳过广告 1s";
    if ([name hasPrefix:@"ad-countdown"] || [name isEqual:@"promotion-navigation"]) text = @"广告 4s";
    if ([name isEqual:@"ordinary-timer"]) text = @"比赛 4s";
    if ([name isEqual:@"ordinary-overlay"]) text = @"关闭图片";
    if ([name isEqual:@"label-gesture"]) {
        UILabel *label = [[UILabel alloc] initWithFrame:entry]; label.text = text; label.textColor = UIColor.whiteColor;
        label.userInteractionEnabled = YES;
        [label addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(close:)]];
        [overlay addSubview:label];
    } else if ([name isEqual:@"image-ocr"] || [name isEqual:@"image-middle"] || [name isEqual:@"ad-countdown-ocr"]
               || [name isEqual:@"canvas-change"] || [name isEqual:@"ocr-conflict"]) {
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:overlay.bounds.size];
        UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *r) {
            [overlay.backgroundColor setFill]; UIRectFill(overlay.bounds);
            [@"CONTROLLED AD FIXTURE" drawAtPoint:CGPointMake(25, 230) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:22], NSForegroundColorAttributeName:UIColor.whiteColor}];
            [([name isEqual:@"ad-countdown-ocr"] ? @"广告 4s" : @"关闭｜4s") drawInRect:entry withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:17], NSForegroundColorAttributeName:UIColor.whiteColor}];
        }];
        UIImageView *canvas = [[UIImageView alloc] initWithImage:image]; canvas.frame = overlay.bounds;
        canvas.userInteractionEnabled = YES; [overlay addSubview:canvas];
        [canvas addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(closeCanvas:)]];
        if ([name isEqual:@"canvas-change"]) {
            __weak UIImageView *weakCanvas = canvas;
            // Replace only image pixels while retaining the same view, controller, gesture and bounds.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 750 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                weakCanvas.image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *r) {
                    [UIColor.systemOrangeColor setFill]; UIRectFill(overlay.bounds);
                    [@"PROMOTION CONTENT" drawAtPoint:CGPointMake(40, 230) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:24]}];
                    [@"VIEW DETAILS" drawInRect:entry withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:17]}];
                }];
            });
        }
        if ([name isEqual:@"ocr-conflict"]) {
            // Deliberate same-region conflicting OCR lines; neither may be clicked.
            canvas.image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *r) {
                [overlay.backgroundColor setFill]; UIRectFill(overlay.bounds);
                [@"跳过广告" drawAtPoint:CGPointMake(entry.origin.x, entry.origin.y) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:16], NSForegroundColorAttributeName:UIColor.whiteColor}];
                [@"关闭广告" drawAtPoint:CGPointMake(entry.origin.x - 100, entry.origin.y) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:16], NSForegroundColorAttributeName:UIColor.whiteColor}];
                [@"CONTROLLED AD FIXTURE" drawAtPoint:CGPointMake(20, 230) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:20]}];
            }];
        }
    } else {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; button.frame = entry;
        [button setTitle:text forState:UIControlStateNormal]; [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [button addTarget:self action:@selector(close:) forControlEvents:UIControlEventTouchUpInside];
        if ([name isEqual:@"source-sibling"]) {
            [button setTitle:@"查看详情" forState:UIControlStateNormal];
            UILabel *label = [[UILabel alloc] initWithFrame:entry]; label.text = @"跳过广告 4s";
            label.userInteractionEnabled = NO; label.textColor = UIColor.whiteColor;
            // Add label later below, making it a visually overlapping sibling, not button content.
            [overlay addSubview:button]; [overlay addSubview:label];
            button = nil;
        }
        if ([name isEqual:@"disabled-countdown"]) button.enabled = NO;
        if ([name isEqual:@"ad-countdown-split"]) {
            [button setTitle:@"" forState:UIControlStateNormal];
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 50, 30)]; label.text = @"广告"; label.textColor = UIColor.whiteColor;
            UILabel *digits = [[UILabel alloc] initWithFrame:CGRectMake(50, 0, 40, 30)]; digits.text = @"4s"; digits.textColor = UIColor.whiteColor;
            [button addSubview:label]; [button addSubview:digits];
        }
        if ([name isEqual:@"root-native"]) { [self.view addSubview:button]; [overlay removeFromSuperview]; self.overlay = button; }
        else if (button) [overlay addSubview:button];
        if ([name isEqual:@"duplicate-ambiguous"] || [name isEqual:@"different-actions"] || [name isEqual:@"different-tags"]) {
            UIButton *second = [UIButton buttonWithType:UIButtonTypeSystem]; second.frame = CGRectMake(15, 90, 100, 30);
            [button setTitle:@"跳过 4s" forState:UIControlStateNormal];
            [second setTitle:@"跳过 4s" forState:UIControlStateNormal];
            if ([name isEqual:@"different-tags"]) second.tag = 1;
            [second addTarget:self action:[name isEqual:@"different-actions"] ? @selector(otherAction:) : @selector(close:) forControlEvents:UIControlEventTouchUpInside]; [overlay addSubview:second];
        }
    }
    if ([name isEqual:@"natural-expiry"]) {
        __weak UIView *weakOverlay = overlay;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 900 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [weakOverlay removeFromSuperview]; });
    }
}
- (void)touchCheck:(id)sender {
    self.touchChecks++;
    self.status.text = [NSString stringWithFormat:@"tip touch check %u", self.touchChecks];
    NSURL *docs = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    [@{@"touchChecks": @(self.touchChecks)} writeToURL:[docs URLByAppendingPathComponent:@"tip-touch.plist"] atomically:YES];
}
- (void)closeCanvas:(UITapGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:gesture.view];
    CGFloat y = [self.scenario isEqual:@"image-middle"] ? gesture.view.bounds.size.height * .60 : 90;
    if (point.x >= gesture.view.bounds.size.width - 130 && point.y >= y - 10 && point.y <= y + 40) [self close:gesture];
}
- (void)otherAction:(id)sender {
    self.actions++; self.status.text = @"Unexpected other callback"; [self writeActionRecord];
}
- (void)writeActionRecord {
    NSDictionary *record = @{@"scenario": self.scenario ?: @"", @"runID": self.runID ?: @"", @"actions": @(self.actions), @"uptime": @(NSProcessInfo.processInfo.systemUptime)};
    NSURL *docs = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    [record writeToURL:[docs URLByAppendingPathComponent:@"fixture-action.plist"] atomically:YES];
}
- (void)close:(id)sender {
    self.actions++;
    self.status.text = [NSString stringWithFormat:@"%@ / action %u", self.scenario, self.actions];
    // The fixture records its callback, never claims that AutoSkipGuard has verified exit.
    [self writeActionRecord];
    if ([self.scenario isEqual:@"promotion-navigation"]) {
        UIViewController *promotion = [UIViewController new];
        promotion.view.backgroundColor = UIColor.systemYellowColor;
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 200, 300, 40)]; label.text = @"PROMOTION PAGE NOT AD EXIT";
        [promotion.view addSubview:label];
        promotion.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:promotion animated:NO completion:nil];
        return;
    }
    if ([self.scenario isEqual:@"normal-login"] || [self.scenario isEqual:@"no-effect"] || [self.scenario isEqual:@"natural-expiry"] || [self.scenario isEqual:@"ad-countdown-noeffect"]) return;
    if (self.delayed) {
        self.delayed = NO;
        __weak UIView *overlay = self.overlay;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 600 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [overlay removeFromSuperview]; });
    } else [self.overlay removeFromSuperview];
}
@end

@interface ASGFixtureDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation ASGFixtureDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
#if ASG_ORIGINAL_FIXTURE
    dlopen([[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/AutoSkipOriginal.dylib"] fileSystemRepresentation], RTLD_NOW | RTLD_LOCAL);
#elif ASG_PAYLOAD_FIXTURE
    dlopen([[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/AutoSkipGuard.dylib"] fileSystemRepresentation], RTLD_NOW | RTLD_LOCAL);
#endif
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [ASGFixtureController new]; [self.window makeKeyAndVisible]; return YES;
}
- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary *)options {
    NSArray *allowed = @[@"native", @"label-gesture", @"disabled-countdown", @"close-countdown", @"arrow-overlay", @"slow-exit", @"image-ocr",
                         @"root-native", @"duplicate-ambiguous", @"normal-login", @"late-ad", @"no-effect", @"natural-expiry", @"different-actions", @"different-tags", @"image-middle", @"ad-countdown", @"ad-countdown-split", @"ad-countdown-ocr", @"ad-countdown-noeffect", @"ordinary-timer", @"promotion-navigation", @"empty-window", @"late-image-6", @"ordinary-overlay", @"source-sibling", @"canvas-change", @"ocr-conflict"];
    if (![allowed containsObject:url.host]) return NO;
    if (self.window.rootViewController.presentedViewController)
        [self.window.rootViewController dismissViewControllerAnimated:NO completion:nil];
    [(ASGFixtureController *)self.window.rootViewController start:url.host];
    return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(ASGFixtureDelegate.class)); }
}

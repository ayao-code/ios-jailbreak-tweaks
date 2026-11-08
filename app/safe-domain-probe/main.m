#import <UIKit/UIKit.h>
#import "ProbeReport.h"

@interface SDPViewController : UIViewController
@property(nonatomic, strong) UITextView *output;
@property(nonatomic, strong) UIButton *runButton;
@property(nonatomic, strong) UIButton *exportButton;
@property(nonatomic, strong) NSURL *reportURL;
@end

@implementation SDPViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"安全域验证";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.output = [UITextView new];
    self.output.editable = NO;
    self.output.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.output.text = @"只检查本测试 App，不是隔离系统。\n不会读取账号或沙盒外写入。\n正在收集一次启动报告…";
    self.runButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.runButton setTitle:@"重新检查自身" forState:UIControlStateNormal];
    [self.runButton addTarget:self action:@selector(collect) forControlEvents:UIControlEventTouchUpInside];
    self.exportButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.exportButton setTitle:@"导出本次报告" forState:UIControlStateNormal];
    [self.exportButton addTarget:self action:@selector(exportReport) forControlEvents:UIControlEventTouchUpInside];
    self.exportButton.enabled = NO;
    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[self.runButton, self.exportButton]];
    buttons.distribution = UIStackViewDistributionFillEqually;
    buttons.translatesAutoresizingMaskIntoConstraints = NO;
    self.output.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.output];
    [self.view addSubview:buttons];
    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [buttons.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor constant:12],
        [buttons.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor constant:-12],
        [buttons.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor constant:-12],
        [buttons.heightAnchor constraintEqualToConstant:48],
        [self.output.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor constant:12],
        [self.output.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor constant:-12],
        [self.output.topAnchor constraintEqualToAnchor:safeArea.topAnchor constant:12],
        [self.output.bottomAnchor constraintEqualToAnchor:buttons.topAnchor constant:-8]]];
    [self collect];
}
- (void)collect {
    self.runButton.enabled = NO;
    self.exportButton.enabled = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *report = SDPCollectReport(@"main_app");
        NSError *error = nil;
        NSURL *reportURL = SDPSaveReport(report, &error);
        NSData *data = [NSJSONSerialization dataWithJSONObject:report
            options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.reportURL = reportURL;
            self.output.text = reportURL ? text : [NSString stringWithFormat:@"%@\n保存失败：%@", text, error.localizedDescription];
            self.runButton.enabled = YES;
            self.exportButton.enabled = reportURL != nil;
        });
    });
}
- (void)exportReport {
    if (!self.reportURL) {
        return;
    }
    UIActivityViewController *activity = [[UIActivityViewController alloc]
        initWithActivityItems:@[self.reportURL] applicationActivities:nil];
    activity.popoverPresentationController.sourceView = self.exportButton;
    [self presentViewController:activity animated:YES completion:nil];
}
@end

@interface SDPAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation SDPAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:[SDPViewController new]];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argumentCount, char *arguments[]) {
    @autoreleasepool {
        return UIApplicationMain(argumentCount, arguments, nil, NSStringFromClass(SDPAppDelegate.class));
    }
}

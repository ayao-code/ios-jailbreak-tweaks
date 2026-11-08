#import <UIKit/UIKit.h>
#import "StateReport.h"

@interface TSIViewController : UIViewController
@property(nonatomic, strong) UITextView *textView;
@property(nonatomic, strong) UIButton *runButton;
@property(nonatomic, strong) UIButton *shareButton;
@property(nonatomic, strong) NSURL *reportURL;
@end

@implementation TSIViewController
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"淘宝状态只读诊断";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.runButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.runButton setTitle:@"开始只读检查" forState:UIControlStateNormal];
    [self.runButton addTarget:self action:@selector(runInspection) forControlEvents:UIControlEventTouchUpInside];
    self.shareButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.shareButton setTitle:@"导出诊断报告" forState:UIControlStateNormal];
    self.shareButton.enabled = NO;
    [self.shareButton addTarget:self action:@selector(shareReport) forControlEvents:UIControlEventTouchUpInside];
    self.textView = [UITextView new];
    self.textView.editable = NO;
    self.textView.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.textView.text = @"仅统计淘宝专属钥匙串的可访问记录数量，并枚举共享目录名称。\n\n不读取密码、令牌或账号字段；不删除记录、不修改设备标识、不向淘宝注入。\n\n查询失败不代表记录不存在；数量也不能证明登录历史或领券异常的来源。\n\n报告仅保存到本助手的 Documents，可自行导出。";
    for (UIView *child in @[self.runButton, self.shareButton, self.textView]) {
        child.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:child];
    }
    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.runButton.topAnchor constraintEqualToAnchor:safeArea.topAnchor constant:8],
        [self.runButton.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor constant:16],
        [self.runButton.heightAnchor constraintEqualToConstant:44],
        [self.shareButton.centerYAnchor constraintEqualToAnchor:self.runButton.centerYAnchor],
        [self.shareButton.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor constant:-16],
        [self.textView.topAnchor constraintEqualToAnchor:self.runButton.bottomAnchor constant:8],
        [self.textView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor constant:8],
        [self.textView.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor constant:-8],
        [self.textView.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor]
    ]];
}

- (void)runInspection
{
    self.runButton.enabled = NO;
    self.shareButton.enabled = NO;
    self.textView.text = @"正在只读检查，不会修改淘宝数据……";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *report = TSICollectReport();
        NSError *error = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
        NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        NSURL *reportURL = [documents URLByAppendingPathComponent:@"readonly-report.json"];
        BOOL saved = data && reportURL && [data writeToURL:reportURL options:NSDataWritingAtomic error:&error];
        NSString *display = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"报告序列化失败";
        if (!saved) display = [display stringByAppendingFormat:@"\n报告未保存（错误代码 %ld）。", (long)error.code];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.textView.text = display;
            self.runButton.enabled = YES;
            self.shareButton.enabled = saved;
            self.reportURL = saved ? reportURL : nil;
        });
    });
}

- (void)shareReport
{
    if (!self.reportURL) return;
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[self.reportURL] applicationActivities:nil];
    activity.popoverPresentationController.sourceView = self.shareButton;
    activity.popoverPresentationController.sourceRect = self.shareButton.bounds;
    [self presentViewController:activity animated:YES completion:nil];
}
@end

@interface TSIAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation TSIAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:[TSIViewController new]];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[])
{
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(TSIAppDelegate.class));
    }
}

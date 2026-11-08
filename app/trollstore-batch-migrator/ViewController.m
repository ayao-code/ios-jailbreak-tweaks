#import "ViewController.h"
#import "BatchInstaller.h"

@interface ViewController () <BatchInstallerDelegate>
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UITextView *resultsView;
@property(nonatomic, strong) UIProgressView *progressView;
@property(nonatomic, strong) BatchInstaller *installer;
@property(nonatomic) BOOL started;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"巨魔工具迁移";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    UILabel *boundaryLabel = [UILabel new];
    boundaryLabel.numberOfLines = 0;
    boundaryLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    boundaryLabel.text = @"一次性前台安装“巨魔应用文件夹”中的 31 个已校验应用。不会安装 Dopamine、创建 /var/jb、开启 SSH、联网、常驻后台，也不会注入或修改淘宝。";

    self.statusLabel = [UILabel new];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.statusLabel.text = @"准备开始…";

    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];

    self.resultsView = [UITextView new];
    self.resultsView.editable = NO;
    self.resultsView.scrollEnabled = YES;
    self.resultsView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.resultsView.layer.cornerRadius = 12;
    self.resultsView.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.resultsView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    self.resultsView.text = @"请保持 App 在前台，安装完成前不要锁屏。";

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        boundaryLabel,
        self.statusLabel,
        self.progressView,
        self.resultsView,
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 18;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],
        [stack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20],
        [self.resultsView.heightAnchor constraintGreaterThanOrEqualToConstant:260],
    ]];

    self.installer = [BatchInstaller new];
    self.installer.delegate = self;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.started) {
        return;
    }
    self.started = YES;

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"BatchMigration31V2Completed"]) {
        self.progressView.progress = 1.0;
        self.statusLabel.text = @"此前已完成安装。";
        self.resultsView.text = @"为避免重复操作，本次没有再次安装。可直接退出并从 TrollStore 删除本迁移器。";
        return;
    }
    UIApplication.sharedApplication.idleTimerDisabled = YES;
    [self.installer start];
}

- (void)batchInstaller:(BatchInstaller *)installer didUpdateProgress:(double)progress status:(NSString *)status {
    [self.progressView setProgress:(float)progress animated:YES];
    self.statusLabel.text = status;
}

- (void)batchInstaller:(BatchInstaller *)installer didFinishWithResults:(NSArray<NSString *> *)results success:(BOOL)success requiresRestart:(BOOL)requiresRestart {
    UIApplication.sharedApplication.idleTimerDisabled = NO;
    self.progressView.progress = success ? 1.0 : self.progressView.progress;
    self.statusLabel.text = success ? @"安装完成" : (requiresRestart ? @"等待重启确认" : @"安装停止");
    NSString *footer = success
        ? @"\n\n安装器没有启用任何工具功能，也没有配置 TrollFools 注入目标。请等待 Mac 端核验后清理迁移器和 IPA。"
        : (requiresRestart
            ? @"\n\n请手动重启手机。重启解锁后，在系统弹窗点“打开”并输入锁屏密码；然后再次打开本迁移器执行安装。"
            : @"\n\n未继续执行后续项目。请保留此页面，按返回码排查后再重试。");
    self.resultsView.text = [[results componentsJoinedByString:@"\n"] stringByAppendingString:footer];
}

@end

#import "ViewController.h"
#import "CR3Processor.h"

@interface ViewController () <CR3ProcessorDelegate>
@property(nonatomic, strong) UILabel *summaryLabel;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIProgressView *progressView;
@property(nonatomic, strong) UIButton *scanButton;
@property(nonatomic, strong) UIButton *startButton;
@property(nonatomic, strong) UIButton *verifyButton;
@property(nonatomic, strong) CR3Processor *processor;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"CR3 伴生图";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.processor = [CR3Processor new];
    self.processor.delegate = self;

    UILabel *descriptionLabel = [UILabel new];
    descriptionLabel.numberOfLines = 0;
    descriptionLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    descriptionLabel.text = @"在本机前台将新的佳能 CR3 真正解码为 6000×4000 sRGB Q100 JPEG。保留原 CR3，并继承拍摄时间、位置、方向、收藏、隐藏和用户相册。";

    self.summaryLabel = [UILabel new];
    self.summaryLabel.numberOfLines = 0;
    self.summaryLabel.font = [UIFont monospacedSystemFontOfSize:16 weight:UIFontWeightSemibold];
    self.summaryLabel.text = @"尚未扫描";

    self.statusLabel = [UILabel new];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.text = @"仅在 App 打开时工作，不会后台常驻。";

    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.progress = 0;

    self.scanButton = [self buttonWithTitle:@"扫描新 CR3" action:@selector(scanTapped) color:UIColor.systemBlueColor];
    self.startButton = [self buttonWithTitle:@"生成 Q100 伴生图" action:@selector(startTapped) color:UIColor.systemGreenColor];
    self.startButton.enabled = NO;
    self.verifyButton = [self buttonWithTitle:@"验证本机解码器" action:@selector(verifyTapped) color:UIColor.systemOrangeColor];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        descriptionLabel,
        self.summaryLabel,
        self.progressView,
        self.statusLabel,
        self.scanButton,
        self.startButton,
        self.verifyButton,
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 18;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:24],
        [self.scanButton.heightAnchor constraintEqualToConstant:50],
        [self.startButton.heightAnchor constraintEqualToConstant:50],
        [self.verifyButton.heightAnchor constraintEqualToConstant:50],
    ]];

    [self.processor scan];
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(SEL)action color:(UIColor *)color {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    button.backgroundColor = color;
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.layer.cornerRadius = 12;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)scanTapped {
    [self.processor scan];
}

- (void)startTapped {
    if (self.processor.isRunning) {
        [self.processor pause];
        [self.startButton setTitle:@"正在暂停…" forState:UIControlStateNormal];
        self.startButton.enabled = NO;
    } else {
        [self.processor start];
        [self.startButton setTitle:@"处理完当前照片后暂停" forState:UIControlStateNormal];
        self.scanButton.enabled = NO;
        self.verifyButton.enabled = NO;
    }
}

- (void)verifyTapped {
    self.scanButton.enabled = NO;
    self.startButton.enabled = NO;
    self.verifyButton.enabled = NO;
    [self.processor verifyDecoder];
}

- (void)processor:(CR3Processor *)processor didUpdateSummary:(NSString *)summary canStart:(BOOL)canStart {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.summaryLabel.text = summary;
        self.startButton.enabled = canStart && !processor.isRunning;
    });
}

- (void)processor:(CR3Processor *)processor didUpdateProgress:(double)progress status:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.progressView setProgress:progress animated:YES];
        self.statusLabel.text = status;
    });
}

- (void)processor:(CR3Processor *)processor didFinishWithMessage:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplication.sharedApplication.idleTimerDisabled = NO;
        self.statusLabel.text = message;
        self.scanButton.enabled = YES;
        self.verifyButton.enabled = YES;
        [self.startButton setTitle:@"生成 Q100 伴生图" forState:UIControlStateNormal];
        [self.processor scan];
    });
}

@end

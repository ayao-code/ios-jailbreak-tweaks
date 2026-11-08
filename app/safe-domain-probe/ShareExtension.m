#import <UIKit/UIKit.h>
#import "ProbeReport.h"

extern int NSExtensionMain(int argumentCount, char *arguments[]);

@interface SDPShareViewController : UIViewController
@property(nonatomic, strong) UITextView *output;
@property(nonatomic, strong) UIButton *exportButton;
@property(nonatomic, strong) NSURL *reportURL;
@end

@implementation SDPShareViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.output = [UITextView new];
    self.output.editable = NO;
    self.output.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.output.text = @"只检查扩展自身；不读取传入的分享内容。";
    self.exportButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.exportButton setTitle:@"导出扩展报告" forState:UIControlStateNormal];
    [self.exportButton addTarget:self action:@selector(exportReport) forControlEvents:UIControlEventTouchUpInside];
    self.exportButton.enabled = NO;
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [closeButton setTitle:@"关闭" forState:UIControlStateNormal];
    [closeButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[self.exportButton, closeButton]];
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
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *report = SDPCollectReport(@"share_extension");
        NSError *error = nil;
        NSURL *reportURL = SDPSaveReport(report, &error);
        NSData *data = [NSJSONSerialization dataWithJSONObject:report
            options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.reportURL = reportURL;
            self.output.text = reportURL ? text : [NSString stringWithFormat:@"%@\n保存失败：%@", text, error.localizedDescription];
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
- (void)close {
    [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
}
@end

int main(int argumentCount, char *arguments[]) {
    @autoreleasepool {
        return NSExtensionMain(argumentCount, arguments);
    }
}

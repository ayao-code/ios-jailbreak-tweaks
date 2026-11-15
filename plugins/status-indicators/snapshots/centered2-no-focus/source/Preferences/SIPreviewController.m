#import "SIPreviewController.h"
#import <Preferences/PSSpecifier.h>
#import "../SIItemViews.h"
#import <roothide.h>
#import "../SISettingsStore.h"

@implementation SIPreviewController {
    UIView *_bar;
    UIScrollView *_scroll;
    SIItemViews *_items;
    UISegmentedControl *_selected, *_orientation, *_background;
    UILabel *_hint, *_coordinates;
    NSMutableDictionary *_settings;
    BOOL _rendering;
    CGPoint _origin;
    id _observer;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"位置与样式预览";
    self.view.backgroundColor=UIColor.systemGroupedBackgroundColor;
    _scroll=[[UIScrollView alloc] initWithFrame:self.view.bounds]; [self.view addSubview:_scroll];
    _selected=[[UISegmentedControl alloc] initWithItems:@[@"VPN",@"总静音",@"专注",@"网速"]]; _selected.selectedSegmentIndex=0;
    _orientation=[[UISegmentedControl alloc] initWithItems:@[@"竖屏布局",@"横屏布局"]]; _orientation.selectedSegmentIndex=0;
    _background=[[UISegmentedControl alloc] initWithItems:@[@"浅色背景",@"深色背景"]]; _background.selectedSegmentIndex=0;
    for (UISegmentedControl *control in @[_selected,_orientation,_background]) {
        [control addTarget:self action:@selector(redraw) forControlEvents:UIControlEventValueChanged];
        [_scroll addSubview:control];
    }
    _hint=[UILabel new]; _hint.numberOfLines=0; _hint.font=[UIFont systemFontOfSize:14]; _hint.textColor=UIColor.secondaryLabelColor;
    _hint.text=@"这里是样式示例：VPN、总静音模拟开启，网速使用示例值，不代表真实连接。开启动态居中时，当前显示项目会组成整体并以中心对齐，网速使用固定预留宽度；关闭时可分别拖动项目。刘海、其他插件占位不模拟，仍需看实际状态栏。";
    [_scroll addSubview:_hint];
    _bar=[UIView new]; _bar.clipsToBounds=YES; [_scroll addSubview:_bar];
    _items=[[SIItemViews alloc] initWithHost:_bar];
    [_bar addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
    _coordinates=[UILabel new]; _coordinates.numberOfLines=0; _coordinates.font=[UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    [_scroll addSubview:_coordinates];
    __weak SIPreviewController *weakSelf=self;
    _observer=[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        [weakSelf readSettings]; [weakSelf redraw];
    }];
    [self readSettings];
}
- (void)dealloc { if (_observer) [NSNotificationCenter.defaultCenter removeObserver:_observer]; }
- (void)readSettings {
    NSDictionary *saved=SIReadSettings();
    _settings=saved ? [saved mutableCopy] : [NSMutableDictionary dictionary];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self readSettings]; [self redraw]; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _scroll.frame=self.view.bounds;
    CGFloat width=MAX(1,self.view.bounds.size.width-32), y=16;
    CGFloat hintHeight=[_hint sizeThatFits:CGSizeMake(width,CGFLOAT_MAX)].height;
    _hint.frame=CGRectMake(16,y,width,hintHeight); y+=hintHeight+12;
    for (UISegmentedControl *control in @[_selected,_orientation,_background]) {
        control.frame=CGRectMake(16,y,width,32); y+=44;
    }
    _bar.frame=CGRectMake(16,y+8,width,50); _coordinates.frame=CGRectMake(16,y+78,width,100);
    _scroll.contentSize=CGSizeMake(self.view.bounds.size.width,y+194);
    [self redraw];
}
- (NSString *)selectedItem { return @[@"vpn",@"mute",@"speed"][MAX(0,MIN(2,_selected.selectedSegmentIndex))]; }
- (void)redraw {
    if (!_items || _rendering) return;
    _rendering=YES;
    BOOL landscape=_orientation.selectedSegmentIndex==1, dark=_background.selectedSegmentIndex==1;
    CGRect frame=_bar.frame; frame.size.height=landscape ? 20 : 50;
    if (!CGRectEqualToRect(frame,_bar.frame)) _bar.frame=frame;
    _bar.backgroundColor=dark ? UIColor.blackColor : UIColor.whiteColor;
    SIItemLayout layout=SILayoutFromSettings(_settings,landscape);
    [_items renderVPN:SIConfigBool(_settings,@"showVPN",YES) mute:YES
        speed:SIConfigBool(_settings,@"showSpeed",YES) ? SISpeedText(4096,1024,YES,SISpeedStyleFromSettings(_settings)) : @""
        speedStyle:SISpeedStyleFromSettings(_settings)
        color:SIColorFromSettings(_settings,dark ? UIColor.whiteColor : UIColor.blackColor)
        bounds:_bar.bounds layout:layout style:SIStyleFromSettings(_settings)];
    NSString *item=[self selectedItem];
    double x=[item isEqual:@"vpn"] ? layout.vpnX : ([item isEqual:@"mute"] ? layout.muteX : layout.speedX);
    double y=[item isEqual:@"vpn"] ? layout.vpnY : ([item isEqual:@"mute"] ? layout.muteY : layout.speedY);
    BOOL separate=SIConfigBool(_settings,@"separateLandscape",NO);
    BOOL centered=layout.centeredGroup;
    NSString *positionText=centered
        ? [NSString stringWithFormat:@"动态居中：开启\n项目间距：%.1f 点｜网速预留：%.1f 点",layout.groupGap,layout.speedGroupWidth]
        : [NSString stringWithFormat:@"中心位置：%.1f%%\n纵向偏移：%.1f 点",x,y];
    NSString *hint=landscape && !separate ? @"横屏独立布局未开启，拖动会修改共用竖屏位置。" : @"拖动只改所选项目，不改其他项目或样式。";
    _coordinates.text=[NSString stringWithFormat:@"%@\n%@",positionText,centered ? @"动态居中时横向位置由整体中心接管。" : hint];
    _rendering=NO;
}
- (void)drag:(UIPanGestureRecognizer *)gesture {
    NSString *item=[self selectedItem];
    if (SIConfigBool(_settings,@"centeredGroup",NO)) return;
    BOOL landscape=_orientation.selectedSegmentIndex==1 && SIConfigBool(_settings,@"separateLandscape",NO);
    NSString *xKey=SIPositionKey(item,@"X",landscape), *yKey=SIPositionKey(item,@"Y",landscape);
    if (gesture.state==UIGestureRecognizerStateBegan) {
        SIItemLayout layout=SILayoutFromSettings(_settings,landscape);
        _origin=CGPointMake([item isEqual:@"vpn"] ? layout.vpnX : ([item isEqual:@"mute"] ? layout.muteX : layout.speedX),
            [item isEqual:@"vpn"] ? layout.vpnY : ([item isEqual:@"mute"] ? layout.muteY : layout.speedY));
    }
    if (gesture.state==UIGestureRecognizerStateChanged || gesture.state==UIGestureRecognizerStateEnded) {
        CGPoint delta=[gesture translationInView:_bar];
        _settings[xKey]=@(MIN(100,MAX(0,_origin.x+delta.x/MAX(1,_bar.bounds.size.width)*100)));
        _settings[yKey]=@(MIN(100,MAX(-25,_origin.y+delta.y)));
        [self redraw];
        if (gesture.state==UIGestureRecognizerStateEnded) {
            NSError *error=nil;
            if (!SIWriteSettings(@{xKey:_settings[xKey],yKey:_settings[yKey]},&error)) {
                [self readSettings]; [self redraw];
                UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"未保存" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        }
    } else if (gesture.state==UIGestureRecognizerStateCancelled || gesture.state==UIGestureRecognizerStateFailed) {
        [self readSettings]; [self redraw];
    }
}
@end

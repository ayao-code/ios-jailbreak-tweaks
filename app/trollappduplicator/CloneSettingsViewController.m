#import "CloneSettingsViewController.h"

#if CLONE_UPSTREAM_EXPERIMENT
static NSString *const ProtectionKey=@"clone.upstream.disableCallbacks";
#else
static NSString *const ProtectionKey=@"clone.protectOriginal";
#endif
BOOL cloneProtectionEnabled(void) {
    id value=[NSUserDefaults.standardUserDefaults objectForKey:ProtectionKey];
    return value ? [value boolValue] : YES;
}
BOOL cloneSharedGroupIsolationEnabled(void) {
#if CLONE_UPSTREAM_EXPERIMENT
    id value=[NSUserDefaults.standardUserDefaults objectForKey:@"clone.upstream.isolateSharedGroup"];
    return value?[value boolValue]:YES;
#else
    return NO;
#endif
}
@implementation CloneSettingsViewController
- (void)viewDidLoad { [super viewDidLoad]; self.title=@"分身设置"; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
#if CLONE_UPSTREAM_EXPERIMENT
    return 2;
#else
    return 1;
#endif
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
#if CLONE_UPSTREAM_EXPERIMENT
    return @"避免回调冲突：开启时移除主 App 的 URL 回调注册。\n共享组隔离（实验）：仅支持原始大麦解密 IPA，同步组名和权限，保留其他签名身份、钥匙串及扩展。不保证登录或通知正常。\n两个开关默认开启，只影响新生成的 IPA。每次新建使用新的应用 ID，不沿用以前分身的身份。重复安装同一个 IPA 仍会更新它对应的分身。";
#else
    return @"开启：移除原版回调、关联域、共享组、推送和内嵌扩展，优先保护原版；分身相关功能可能失效。\n关闭：保留共享配置，可能干扰原版。\n两种模式都有独立身份和钥匙串，不添加 dylib，不自动砸壳或安装。开关只影响以后生成的包，不修改已经安装的 App。";
#endif
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
#if CLONE_UPSTREAM_EXPERIMENT
    if(indexPath.row==1) {
        cell.textLabel.text=@"共享组隔离（实验）";
        UISwitch *group=[UISwitch new];group.on=cloneSharedGroupIsolationEnabled();
        [group addTarget:self action:@selector(changeSharedGroup:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView=group;cell.selectionStyle=UITableViewCellSelectionStyleNone;return cell;
    }
    cell.textLabel.text=@"避免回调冲突";
#else
    cell.textLabel.text=@"保护原版（隔离共享）";
#endif
    UISwitch *toggle=[UISwitch new]; toggle.on=cloneProtectionEnabled();
    [toggle addTarget:self action:@selector(changeProtection:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView=toggle; cell.selectionStyle=UITableViewCellSelectionStyleNone; return cell;
}
- (void)changeSharedGroup:(UISwitch *)toggle {
    if(toggle.on) { [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"clone.upstream.isolateSharedGroup"];return; }
    toggle.on=YES;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"保留原共享组？" message:@"关闭后不迁移共享组，可能与原版共用配置。仅影响新生成的包。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"保持开启" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭，接受共享" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"clone.upstream.isolateSharedGroup"];toggle.on=NO;
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)changeProtection:(UISwitch *)toggle {
    if(toggle.on) { [NSUserDefaults.standardUserDefaults setBool:YES forKey:ProtectionKey]; return; }
    toggle.on=YES;
#if CLONE_UPSTREAM_EXPERIMENT
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"确认关闭？" message:@"关闭后保留原回调注册，可能影响原版跳转。共享组开关独立控制，钥匙串身份仍保留，不保证完整隔离。" preferredStyle:UIAlertControllerStyleAlert];
#else
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"关闭原版保护？" message:@"兼容模式可能复用原版共享数据、抢占登录或支付回调。这不是隔离保证。只有接受风险才关闭。" preferredStyle:UIAlertControllerStyleAlert];
#endif
    [alert addAction:[UIAlertAction actionWithTitle:@"保持开启" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭，接受风险" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){ [NSUserDefaults.standardUserDefaults setBool:NO forKey:ProtectionKey]; toggle.on=NO; }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end

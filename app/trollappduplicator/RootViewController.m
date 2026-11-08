#import "RootViewController.h"
#import "AppList.h"
#import "CloneSettingsViewController.h"
#import "IPAImport.h"
#import "AppInputStatus.h"
#import "thirdparty/TDFileManagerViewController.h"
#import "thirdparty/TDUtils.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface RootViewController () <UIDocumentPickerDelegate>
@property(nonatomic) BOOL busy;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *pendingImports;
@property(nonatomic) BOOL importOverflow;
@end
@implementation RootViewController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"分身工坊"; self.apps=@[]; self.duplicator=[AppDuplicator new];
#if CLONE_UPSTREAM_EXPERIMENT
    self.title=@"分身工坊·原版实验";
#endif
    self.navigationController.navigationBar.prefersLargeTitles=YES;
    self.navigationItem.leftBarButtonItems=@[
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"folder"] style:UIBarButtonItemStylePlain target:self action:@selector(openDocs:)],
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"] style:UIBarButtonItemStylePlain target:self action:@selector(openSettings:)]];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"plus"] style:UIBarButtonItemStylePlain target:self action:@selector(importIPA:)];
    UIRefreshControl *refresh=[UIRefreshControl new]; [refresh addTarget:self action:@selector(refreshApps:) forControlEvents:UIControlEventValueChanged]; self.refreshControl=refresh;
    [self refreshApps:refresh];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; [self resumePendingImports];
}
- (void)receiveIPAURL:(NSURL *)url {
    if(!self.pendingImports) self.pendingImports=[NSMutableArray array];
    if(self.pendingImports.count>=8) { self.importOverflow=YES; [self resumePendingImports]; return; }
    NSMutableDictionary *item=[NSMutableDictionary dictionaryWithObject:@NO forKey:@"ready"];
    [self.pendingImports addObject:item];
    cloneStageImport(url,^(NSURL *staged,NSError *error){
        if(staged) item[@"url"]=staged;
        if(error) item[@"error"]=error;
        item[@"ready"]=@YES;
        [self resumePendingImports];
    });
}
- (void)removeStagedImport:(NSURL *)url {
    if(!url) return;
    // Staging cleanup applies only to UUID directories created by IPAImport.
    NSString *root=cloneImportRoot().path;
    NSURL *parent=url.URLByDeletingLastPathComponent;
    if([parent.URLByDeletingLastPathComponent.path isEqual:root])
        [NSFileManager.defaultManager removeItemAtURL:parent error:nil];
}
- (void)resumePendingImports {
    if(self.busy || !self.isViewLoaded || !self.view.window ||
       self.navigationController.topViewController!=self || self.presentedViewController ||
       self.navigationController.presentedViewController) return;
    if(self.importOverflow) {
        self.importOverflow=NO;
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"导入队列已满" message:@"最多等待 8 个文件。超出的文件未导入，请处理已有文件后重新分享。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){dispatch_async(dispatch_get_main_queue(),^{[self resumePendingImports];});}]];
        [self presentViewController:alert animated:YES completion:nil]; return;
    }
    NSDictionary *item=self.pendingImports.firstObject;
    if(![item[@"ready"] boolValue]) return;
    [self.pendingImports removeObjectAtIndex:0];
    if(item[@"error"]) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"无法导入" message:[item[@"error"] localizedDescription] preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){dispatch_async(dispatch_get_main_queue(),^{[self resumePendingImports];});}]];
        [self presentViewController:alert animated:YES completion:nil];
    } else [self confirmInput:item[@"url"] suggestedName:@"应用分身"];
}
- (void)openSettings:(id)sender {
    if(!self.busy) [self.navigationController pushViewController:[[CloneSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
}
- (void)openDocs:(id)sender {
    if(!self.busy) [self presentViewController:[[UINavigationController alloc] initWithRootViewController:[TDFileManagerViewController new]] animated:YES completion:nil];
}
- (void)importIPA:(id)sender {
    if(self.busy) return;
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];
    picker.delegate=self; picker.allowsMultipleSelection=NO; [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url=urls.firstObject;
    if(url) [self receiveIPAURL:url];
    [controller dismissViewControllerAnimated:YES completion:^{[self resumePendingImports];}];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [controller dismissViewControllerAnimated:YES completion:^{[self resumePendingImports];}];
}
- (void)refreshApps:(UIRefreshControl *)control {
    if(self.busy) { [control endRefreshing]; return; }
    self.busy=YES; dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSArray *apps=appList(); dispatch_async(dispatch_get_main_queue(),^{self.apps=apps;self.busy=NO;[self.tableView reloadData];[control endRefreshing];[self resumePendingImports];});
    });
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.apps.count; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return nil;
}
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"AppCell"];
    if(!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"AppCell"];
    NSDictionary *app=self.apps[indexPath.row];cell.textLabel.text=app[@"name"];
    cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@",app[@"version"],app[@"bundleID"]];
    cell.imageView.image=[UIImage _applicationIconImageForBundleIdentifier:app[@"bundleID"] format:iconFormat() scale:UIScreen.mainScreen.scale];
    UILabel *label=[UILabel new]; label.font=[UIFont systemFontOfSize:11];
    NSString *status=app[@"encryptionStatus"];
    label.text=[status isEqual:@"encrypted"]?@"主程序加密":([status isEqual:@"unencrypted"]?@"主程序未加密":@"无法读取");
    BOOL selectable=cloneStatusAllowsSelection(status);
    label.textColor=selectable?UIColor.systemBlueColor:UIColor.systemRedColor;
    cell.selectionStyle=selectable?UITableViewCellSelectionStyleDefault:UITableViewCellSelectionStyleNone;
    cell.accessibilityHint=selectable?@"可制作分身":@"不可制作分身";
    [label sizeToFit];cell.accessoryView=label;return cell;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { return 80; }
- (void)showUnavailableStatus:(NSString *)status {
    NSString *message=[status isEqual:@"encrypted"]?@"主程序仍加密，不能制作分身。请先导入已解密的 IPA。":@"无法读取主程序，不能制作分身。请刷新列表或导入完整的已解密 IPA。";
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"不能制作分身" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){dispatch_async(dispatch_get_main_queue(),^{[self resumePendingImports];});}]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if(self.busy || self.presentedViewController) return nil;
    NSString *status=self.apps[indexPath.row][@"encryptionStatus"];
    if(!cloneStatusAllowsSelection(status)) { [self showUnavailableStatus:status]; return nil; }
    return indexPath;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES]; if(self.busy) return;
    NSDictionary *app=self.apps[indexPath.row];
    // A source can be updated after the list was loaded. Re-read its header.
    NSString *status=cloneInstalledAppStatus(app[@"path"]);
    if(!cloneStatusAllowsSelection(status)) {
        NSMutableArray *apps=[self.apps mutableCopy]; NSMutableDictionary *updated=[app mutableCopy];
        updated[@"encryptionStatus"]=status; apps[indexPath.row]=updated; self.apps=apps;
        [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        [self showUnavailableStatus:status]; return;
    }
    [self confirmInput:[NSURL fileURLWithPath:app[@"path"]] suggestedName:[app[@"name"] stringByAppendingString:@"分身"]];
}
- (void)confirmInput:(NSURL *)url suggestedName:(NSString *)name {
    BOOL protect=cloneProtectionEnabled();
    BOOL isolate=cloneSharedGroupIsolationEnabled();
#if CLONE_UPSTREAM_EXPERIMENT
    NSString *message=[NSString stringWithFormat:@"回调注册：%@。共享组：%@。\n保留应用签名身份、钥匙串及扩展。隔离组会重签组权限并修改组名常量，新组不复制旧数据。不能保证登录、通知或完整数据隔离。\n每次新建生成新的应用 ID，不沿用旧分身 ID。只生成 IPA，不安装。",protect?@"移除":@"保留",isolate?@"独立组（仅原始大麦）":@"沿用原组"];
#else
    NSString *message=protect?@"保护原版：移除共享组、回调、关联域、推送及全部内嵌App/扩展。相应功能会失效，主程序也可能不接受降级。仍可能主动跳转外部App。只生成候选，原版不改。":@"兼容模式：保留共享组、回调和服务配置，可能影响原版登录、支付、数据或通知。不是隔离分身。只生成候选，原版不改。";
#endif
#if CLONE_UPSTREAM_EXPERIMENT
    NSString *title=@"新建分身";
#else
    NSString *title=@"制作分身候选";
#endif
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field){field.text=name;field.placeholder=@"分身名称";}];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){
        [self removeStagedImport:url];
        dispatch_async(dispatch_get_main_queue(),^{[self resumePendingImports];});
    }]];
#if CLONE_UPSTREAM_EXPERIMENT
    NSString *actionTitle=@"接受限制，生成";
#else
    NSString *actionTitle=protect?@"接受功能限制，生成":@"接受共享风险，生成";
#endif
    [alert addAction:[UIAlertAction actionWithTitle:actionTitle style:protect?UIAlertActionStyleDefault:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){
        NSString *chosen=[alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        [self generate:url name:chosen protect:protect group:isolate];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)generate:(NSURL *)url name:(NSString *)name protect:(BOOL)protect group:(BOOL)isolate {
    if(self.busy) return; self.busy=YES;
#if CLONE_UPSTREAM_EXPERIMENT
    NSString *progressMessage=isolate?@"检查共享组常量和权限，修改工作副本并重签核对。不读取账号、不安装，请保持前台。":@"复制包、修改主应用信息，不重签、不读取账号数据、不安装。请保持工具在前台。";
#else
    NSString *progressMessage=@"检查全包、重签工作副本。不会安装或读取账号数据，请保持本工具在前台。";
#endif
    UIAlertController *progress=[UIAlertController alertControllerWithTitle:@"检查和制作中" message:progressMessage preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progress animated:YES completion:^{
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
            BOOL scoped=[url startAccessingSecurityScopedResource]; NSError *error=nil;
#if CLONE_UPSTREAM_EXPERIMENT
            NSDictionary *result=[self.duplicator createUpstreamCloneFromURL:url name:name disableCallbacks:protect isolateSharedGroup:isolate error:&error];
#else
            NSDictionary *result=[self.duplicator createCloneFromURL:url name:name protectOriginal:protect error:&error];
#endif
            if(scoped) [url stopAccessingSecurityScopedResource];
            [self removeStagedImport:url];
            dispatch_async(dispatch_get_main_queue(),^{[progress dismissViewControllerAnimated:YES completion:^{
                self.busy=NO;
#if CLONE_UPSTREAM_EXPERIMENT
                NSString *message=result?[NSString stringWithFormat:@"IPA：%@\n\n回调注册：%@。共享组：%@。只完成静态生成，未安装或实测；钥匙串身份仍保留，登录和通知未保证。",[result[@"ipa"] lastPathComponent],protect?@"已移除":@"保留原注册",isolate?result[@"new_group"]:@"原共享组"]:error.localizedDescription?:@"未生成文件。";
#else
                NSString *message=result?[NSString stringWithFormat:@"IPA：%@\n报告：%@\n\n只通过静态检查；未安装、未实测。请先核对报告，不能保证不影响原版或登录/支付正常。",[result[@"ipa"] lastPathComponent],[result[@"report"] lastPathComponent]]:error.localizedDescription?:@"未生成文件，请检查输入包。";
#endif
                UIAlertController *done=[UIAlertController alertControllerWithTitle:result?@"候选包已生成":@"无法生成" message:message preferredStyle:UIAlertControllerStyleAlert];
                [done addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){dispatch_async(dispatch_get_main_queue(),^{[self resumePendingImports];});}]];
#if CLONE_UPSTREAM_EXPERIMENT
                NSString *filesTitle=@"查看文件";
#else
                NSString *filesTitle=@"查看文件与报告";
#endif
                if(result) [done addAction:[UIAlertAction actionWithTitle:filesTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){[self openDocs:nil];}]];
                [self presentViewController:done animated:YES completion:nil];
            }];});
        });
    }];
}
@end

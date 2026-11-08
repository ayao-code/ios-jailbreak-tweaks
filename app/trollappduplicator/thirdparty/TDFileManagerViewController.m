#import "TDFileManagerViewController.h"
#import "TDUtils.h"

@implementation TDFileManagerViewController

- (void)loadView {
    [super loadView];

    self.title = @"候选包与检查报告";
    self.fileList = duplicatedFileList();

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"关闭"
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(done)];
}

- (void)refresh {
    self.fileList = duplicatedFileList();
    [self.tableView reloadData];
}

- (void)done {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSelectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.fileList.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"FileCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];

    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:cellIdentifier];
    }

    NSString *path = [docPath() stringByAppendingPathComponent:self.fileList[indexPath.row]];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path
                                                                                error:nil];
    NSDate *date = attributes[NSFileModificationDate];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"MMM d, yyyy h:mm a"];

    NSNumber *fileSize = attributes[NSFileSize];

    cell.textLabel.text = self.fileList[indexPath.row];
    cell.detailTextLabel.text = [dateFormatter stringFromDate:date];
    cell.detailTextLabel.textColor = [UIColor systemGray2Color];
    cell.imageView.image = [UIImage systemImageNamed:@"doc.fill"];

    UILabel *label = [[UILabel alloc] init];
    label.text = [NSString stringWithFormat:@"%.2f MB", [fileSize doubleValue] / 1000000.0f];
    label.textColor = [UIColor systemGray2Color];
    label.font = [UIFont systemFontOfSize:12.0f];
    [label sizeToFit];
    label.textAlignment = NSTextAlignmentCenter;
    cell.accessoryView = label;

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 65.0f;
}

- (bool)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    UIContextualAction *deleteAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:@"删除文件"
                          handler:^(UIContextualAction *action, UIView *sourceView,
                                    void (^completionHandler)(BOOL)) {
                            NSString *file = self.fileList[indexPath.row];
                            NSString *path = [docPath() stringByAppendingPathComponent:file];
                            UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"删除导出文件？" message:@"仅删除所选导出文件，不卸载任何 App，不清理账号或共享目录。" preferredStyle:UIAlertControllerStyleAlert];
                            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){completionHandler(NO);}]];
                            [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){
                                NSError *error=nil;
                                BOOL ok=[file.lastPathComponent isEqual:file] && [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
                                [self refresh];completionHandler(ok);
                            }]];
                            [self presentViewController:alert animated:YES completion:nil];
                          }];

    UISwipeActionsConfiguration *swipeActions =
        [UISwipeActionsConfiguration configurationWithActions:@[ deleteAction ]];
    return swipeActions;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *file = self.fileList[indexPath.row];
    NSString *path = [docPath() stringByAppendingPathComponent:file];
    NSURL *url = [NSURL fileURLWithPath:path];

    UIActivityViewController *activityViewController =
        [[UIActivityViewController alloc] initWithActivityItems:@[ url ] applicationActivities:nil];
    if(activityViewController.popoverPresentationController) {
        activityViewController.popoverPresentationController.sourceView=tableView;
        activityViewController.popoverPresentationController.sourceRect=[tableView rectForRowAtIndexPath:indexPath];
    }
    [self presentViewController:activityViewController animated:YES completion:nil];

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end

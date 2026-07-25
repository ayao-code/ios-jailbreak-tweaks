// Reconstructed from strings in PhotosRecentsSortPrefs.
// This is a practical skeleton for the prefs controller.

#import <Preferences/PSListController.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <stdlib.h>

@interface PhotosRecentsSortRootListController : PSListController
@end

@implementation PhotosRecentsSortRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:@"Root" target:self] retain];
    }
    return _specifiers;
}

- (void)respringTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重启桌面"
                                                                   message:@"修改 Photos 增强设置后需要重启桌面。"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    __weak typeof(self) weakSelf = self;
    UIAlertAction *confirm = [UIAlertAction actionWithTitle:@"继续"
                                                      style:UIAlertActionStyleDestructive
                                                    handler:^(__unused UIAlertAction *action) {
        [weakSelf runRespringCommand];
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消"
                                                     style:UIAlertActionStyleCancel
                                                   handler:nil];
    [alert addAction:cancel];
    [alert addAction:confirm];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)runRespringCommand {
    NSArray<NSString *> *candidates = @[
        @"/var/jb/usr/bin/sbreload",
        @"/usr/bin/sbreload",
        @"/var/jb/usr/bin/killall",
        @"/usr/bin/killall",
    ];

    for (NSString *path in candidates) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            if ([path hasSuffix:@"killall"]) {
                system([[NSString stringWithFormat:@"%@ SpringBoard", path] UTF8String]);
            } else {
                system([path UTF8String]);
            }
            return;
        }
    }
}

@end

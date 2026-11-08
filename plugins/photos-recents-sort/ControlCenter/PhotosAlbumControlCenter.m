#import <ControlCenterUIKit/CCUIToggleModule.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

static NSString * const PhotosApplicationIdentifier = @"com.apple.mobileslideshow";

static void PhotosOpenApplication(void) {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultWorkspaceSelector = NSSelectorFromString(@"defaultWorkspace");
    SEL openApplicationSelector = NSSelectorFromString(@"openApplicationWithBundleID:");

    if (!workspaceClass || ![workspaceClass respondsToSelector:defaultWorkspaceSelector]) {
        return;
    }

    id (*sendClassMessage)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    id workspace = sendClassMessage(workspaceClass, defaultWorkspaceSelector);
    if (!workspace || ![workspace respondsToSelector:openApplicationSelector]) {
        return;
    }

    void (*sendOpenMessage)(id, SEL, NSString *) = (void (*)(id, SEL, NSString *))objc_msgSend;
    sendOpenMessage(workspace, openApplicationSelector, PhotosApplicationIdentifier);
}

@interface PhotosAlbumControlCenter : CCUIToggleModule
@end

@implementation PhotosAlbumControlCenter

- (BOOL)isSelected {
    return NO;
}

- (void)setSelected:(BOOL)selected {
    if (selected) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            PhotosOpenApplication();
        });
    }
    [self refreshState];
}

- (UIImage *)photosGlyph {
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:27.0 weight:UIImageSymbolWeightSemibold scale:UIImageSymbolScaleMedium];
    UIImage *image = [UIImage systemImageNamed:@"photo.on.rectangle" withConfiguration:configuration];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

- (UIImage *)iconGlyph {
    return [self photosGlyph];
}

- (UIImage *)selectedIconGlyph {
    return [self photosGlyph];
}

@end

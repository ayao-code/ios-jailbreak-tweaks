#import "AppDelegate.h"
#import "RootViewController.h"
#import "IPAImport.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    _window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _rootViewController = [[UINavigationController alloc]
        initWithRootViewController:[[RootViewController alloc] init]];
    _window.rootViewController = _rootViewController;
    [_window makeKeyAndVisible];
    return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    if(!cloneCanImportURL(url)) return NO;
    RootViewController *root=(RootViewController *)self.rootViewController.viewControllers.firstObject;
    [root receiveIPAURL:url];
    return YES;
}
- (void)applicationDidBecomeActive:(UIApplication *)application {
    RootViewController *root=(RootViewController *)self.rootViewController.viewControllers.firstObject;
    [root resumePendingImports];
}

@end

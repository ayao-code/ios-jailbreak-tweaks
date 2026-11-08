#import "AppList.h"
#import "thirdparty/LSApplicationProxy+AltList.h"
#import "thirdparty/TDUtils.h"
#import "AppInputStatus.h"

NSArray *appList(void) {
    NSMutableArray *apps = [NSMutableArray array];

    NSArray<LSApplicationProxy *> *installedApplications =
        [[LSApplicationWorkspace defaultWorkspace] atl_allInstalledApplications];
    [installedApplications
        enumerateObjectsUsingBlock:^(LSApplicationProxy *proxy, NSUInteger idx, BOOL *stop) {
          if ([proxy atl_isHidden]) return;

          NSString *bundleID = [proxy atl_bundleIdentifier];
          if ([bundleID isEqualToString:@"com.ayao.clonestudio"] ||
              [bundleID isEqualToString:@"com.ayao.clonestudio.upstream"]) return;

          if (![proxy.applicationType isEqualToString:@"User"]) {
              if ([bundleID hasPrefix:@"com.apple."]) return;
              if ([bundleID hasPrefix:@"com.opa334."]) return;
              if ([bundleID isEqualToString:@"com.zznq.trollappduplicator"]) return;
          }

          NSURL *appURL = [proxy performSelector:@selector(bundleURL)];
          if (![appURL.path hasPrefix:@"/private/var/containers/Bundle/Application/"]) return;

          NSString *path = appURL.path;
          NSString *name = [proxy atl_nameToDisplay];
          NSString *version = [proxy atl_shortVersionString];

          if (!bundleID || !name || !version || !path) return;

          NSString *status=cloneInstalledAppStatus(path);

          NSDictionary *item =
              @{@"bundleID" : bundleID, @"name" : name, @"path" : path,
                @"version" : version, @"encryptionStatus" : status};

          [apps addObject:item];
        }];

    NSSortDescriptor *descriptor =
        [[NSSortDescriptor alloc] initWithKey:@"name"
                                    ascending:YES
                                     selector:@selector(localizedCaseInsensitiveCompare:)];
    [apps sortUsingDescriptors:@[ descriptor ]];

    return [apps copy];
}

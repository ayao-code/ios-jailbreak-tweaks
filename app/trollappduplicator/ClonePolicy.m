#import "ClonePolicy.h"

NSDictionary *cloneInfoDictionary(NSDictionary *original, NSString *cloneID, NSString *name, BOOL protect) {
    NSMutableDictionary *info=[original mutableCopy];
    info[@"CFBundleIdentifier"]=cloneID;
    if(name) { info[@"CFBundleDisplayName"]=name; info[@"CFBundleName"]=name; }
    if(protect) {
        [info removeObjectForKey:@"CFBundleURLTypes"];
        [info removeObjectForKey:@"CFBundleDocumentTypes"];
        [info removeObjectForKey:@"UTExportedTypeDeclarations"];
        [info removeObjectForKey:@"UTImportedTypeDeclarations"];
        [info removeObjectForKey:@"NSUbiquitousContainers"];
        [info removeObjectForKey:@"UIBackgroundModes"];
        [info removeObjectForKey:@"BGTaskSchedulerPermittedIdentifiers"];
    }
    return info;
}
NSDictionary *cloneEntitlements(NSDictionary *original, NSString *cloneID, BOOL protect) {
    // Nonempty, exact identity prevents TrollStore's broad fallback entitlements.
    NSMutableDictionary *result=[NSMutableDictionary dictionary];
    NSString *prefix=@"AYAOCLONE"; // Local TrollStore identity, NOT an Apple-provisioned Team ID.
    result[@"application-identifier"]=[NSString stringWithFormat:@"%@.%@",prefix,cloneID];
    result[@"com.apple.developer.team-identifier"]=prefix;
    result[@"keychain-access-groups"]=@[[NSString stringWithFormat:@"%@.%@",prefix,cloneID]];
    result[@"com.apple.private.security.container-required"]=cloneID;
    if(!protect) {
        // Never carry arbitrary private/system/debug entitlements into a clone.
        for(NSString *key in @[@"com.apple.security.application-groups",@"com.apple.developer.associated-domains",
                             @"aps-environment",@"com.apple.developer.applesignin",@"com.apple.developer.usernotifications.time-sensitive",
                             @"com.apple.developer.nfc.readersession.formats"]) {
            if(original[key]) result[key]=original[key];
        }
    }
    return result;
}

#import "AppInputStatus.h"
#import "MachOInspector.h"

NSString *cloneInstalledAppStatus(NSString *bundlePath) {
    NSDictionary *info=[NSDictionary dictionaryWithContentsOfFile:
        [bundlePath stringByAppendingPathComponent:@"Info.plist"]];
    NSString *executable=info[@"CFBundleExecutable"];
    if(![executable isKindOfClass:NSString.class] || !executable.length ||
       [executable containsString:@"/"] || [@[@".", @".."] containsObject:executable]) return @"unreadable";
    CloneMachOInfo binary=cloneInspectMachO(
        [bundlePath stringByAppendingPathComponent:executable].fileSystemRepresentation);
    if(!binary.is_macho || binary.malformed) return @"unreadable";
    return binary.encrypted?@"encrypted":@"unencrypted";
}

BOOL cloneStatusAllowsSelection(NSString *status) {
    return [status isEqualToString:@"unencrypted"];
}

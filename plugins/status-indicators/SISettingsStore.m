#import "SISettingsStore.h"
#if !SI_SETTINGS_TEST
#import <roothide.h>
#endif
#import <notify.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>

#if SI_SETTINGS_TEST
static NSString *SITestPath;
void SISetTestSettingsPath(NSString *path) { SITestPath = [path copy]; }
#endif
static NSString *SISettingsPath(void) {
#if SI_SETTINGS_TEST
    return SITestPath;
#else
    return jbroot(@"/var/mobile/Library/Preferences/ayao.statusindicators.plist");
#endif
}
static NSData *SISettingsData(NSString *path) {
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL];
    if ([attributes[NSFileSize] unsignedLongLongValue]>65536) return nil;
    return [NSData dataWithContentsOfFile:path];
}
NSDictionary *SIReadSettings(void) {
    NSData *data=SISettingsData(SISettingsPath());
    id value=data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}
BOOL SIWriteSettings(NSDictionary *changes, NSError **error) {
    if (!NSThread.isMainThread || !changes.count) return NO;
    for (id key in changes) {
        id value=changes[key];
        if (![key isKindOfClass:NSString.class] || ![key length] ||
            (![value isKindOfClass:NSNumber.class] && ![value isKindOfClass:NSString.class])) {
            if (error) *error=[NSError errorWithDomain:@"StatusIndicators" code:3 userInfo:@{NSLocalizedDescriptionKey:@"无效的配置值，未保存。"}];
            return NO;
        }
    }
    NSString *path=SISettingsPath(), *lockPath=[path stringByAppendingString:@".si-lock"];
    int lock=open(lockPath.fileSystemRepresentation,O_CREAT|O_WRONLY|O_NOFOLLOW,0600);
    if (lock<0 || flock(lock,LOCK_EX|LOCK_NB)) {
        if (lock>=0) close(lock);
        if (error) *error=[NSError errorWithDomain:@"StatusIndicators" code:1 userInfo:@{NSLocalizedDescriptionKey:@"配置正被修改，未保存。请稍后再试。"}];
        return NO;
    }
    BOOL success=NO;
    NSData *old=SISettingsData(path);
    NSPropertyListFormat format=NSPropertyListXMLFormat_v1_0;
    NSError *failure=nil;
    NSDictionary *previous=old ? [NSPropertyListSerialization propertyListWithData:old options:NSPropertyListImmutable format:&format error:&failure] : @{};
    if ((!old && [NSFileManager.defaultManager fileExistsAtPath:path]) || ![previous isKindOfClass:NSDictionary.class]) goto done;
    {
        NSMutableDictionary *updated=[previous mutableCopy];
        [updated addEntriesFromDictionary:changes];
        NSData *data=[NSPropertyListSerialization dataWithPropertyList:updated format:format options:0 error:&failure];
        if (!data || data.length>65536) goto done;
        NSString *temporary=[path stringByAppendingFormat:@".si-%@",NSUUID.UUID.UUIDString];
        NSString *backup=[path stringByAppendingString:@".si-last-good"];
        struct stat metadata;
        BOOL exists=lstat(path.fileSystemRepresentation,&metadata)==0;
        if (exists && !S_ISREG(metadata.st_mode)) goto done;
        // A single bounded last-good copy; no ever-growing history.
        if (old && ![old writeToFile:backup options:NSDataWritingAtomic error:&failure]) goto done;
        if (old && chmod(backup.fileSystemRepresentation,0600)) goto done;
        if (![data writeToFile:temporary options:NSDataWritingAtomic error:&failure]) goto done;
        mode_t mode=exists ? (metadata.st_mode & 0777) : 0600;
        if (chmod(temporary.fileSystemRepresentation,mode) ||
            (exists && chown(temporary.fileSystemRepresentation,metadata.st_uid,metadata.st_gid))) {
            unlink(temporary.fileSystemRepresentation); goto done;
        }
        if (![SISettingsData(temporary) isEqualToData:data] || rename(temporary.fileSystemRepresentation,path.fileSystemRepresentation)) {
            unlink(temporary.fileSystemRepresentation); goto done;
        }
        if (![SIReadSettings() isEqual:updated]) {
            if (old) {
                [old writeToFile:temporary options:NSDataWritingAtomic error:NULL];
                chmod(temporary.fileSystemRepresentation,mode);
                chown(temporary.fileSystemRepresentation,metadata.st_uid,metadata.st_gid);
                rename(temporary.fileSystemRepresentation,path.fileSystemRepresentation);
            } else unlink(path.fileSystemRepresentation);
            goto done;
        }
        // All project-owned setters use this store; no CFPreferences write races.
        // Notify only AFTER atomic replacement and semantic readback succeed.
        notify_post("ayao.statusindicators/preferences.changed");
        success=YES;
    }
done:
    flock(lock,LOCK_UN);close(lock);
    if (!success && error) *error=failure ?: [NSError errorWithDomain:@"StatusIndicators" code:2 userInfo:@{NSLocalizedDescriptionKey:@"配置保存失败，未通知插件生效。原设置保留。"}];
    return success;
}

#import "../SISettingsStore.h"
#import <notify.h>
#include <assert.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
int main(void) {
    @autoreleasepool {
        NSString *folder=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
        NSString *path=[folder stringByAppendingPathComponent:@"settings.plist"];
        SISetTestSettingsPath(path);
        int token=-1, notified=0;
        assert(!notify_register_check("ayao.statusindicators/preferences.changed",&token));
        notify_check(token,&notified);
        for (unsigned binary=0;binary<2;binary++) {
            NSPropertyListFormat format=binary ? NSPropertyListBinaryFormat_v1_0 : NSPropertyListXMLFormat_v1_0;
            NSDictionary *original=@{@"enabled":@YES,@"unrelated":@"preserved",@"speedArrangement":@0,@"speedFont":@7};
            NSData *raw=[NSPropertyListSerialization dataWithPropertyList:original format:format options:0 error:NULL];
            assert([raw writeToFile:path atomically:YES]);chmod(path.fileSystemRepresentation,0600);
            NSError *error=nil;
            assert(SIWriteSettings(@{@"speedArrangement":@1,@"speedFont":@12},&error));
            assert(!error);
            NSDictionary *updated=SIReadSettings();
            assert([updated[@"unrelated"] isEqual:@"preserved"] && [updated[@"enabled"] boolValue]);
            assert([updated[@"speedArrangement"] intValue]==1 && [updated[@"speedFont"] intValue]==12);
            NSPropertyListFormat actual=0;
            [NSPropertyListSerialization propertyListWithData:[NSData dataWithContentsOfFile:path] options:0 format:&actual error:NULL];
            assert(actual==format);
            assert([[NSData dataWithContentsOfFile:[path stringByAppendingString:@".si-last-good"]] isEqual:raw]);
            struct stat st;assert(!stat(path.fileSystemRepresentation,&st) && (st.st_mode & 0777)==0600);
            usleep(20000);assert(!notify_check(token,&notified) && notified);
            // The notification can only be observed after the disk snapshot contains new values.
            assert([SIReadSettings()[@"speedArrangement"] intValue]==1);
            NSData *before=[NSData dataWithContentsOfFile:path];
            int lock=open([path stringByAppendingString:@".si-lock"].fileSystemRepresentation,O_WRONLY);assert(lock>=0);
            assert(!flock(lock,LOCK_EX|LOCK_NB));
            assert(!SIWriteSettings(@{@"speedFont":@15},&error));
            assert([[NSData dataWithContentsOfFile:path] isEqual:before]);
            assert(!notify_check(token,&notified) && !notified);
            flock(lock,LOCK_UN);close(lock);
            assert(!SIWriteSettings(@{@"speedFont":NSNull.null},&error));
            assert([[NSData dataWithContentsOfFile:path] isEqual:before]);
            NSData *invalid=[@"invalid plist" dataUsingEncoding:NSUTF8StringEncoding];
            [invalid writeToFile:path atomically:YES];
            assert(!SIWriteSettings(@{@"speedFont":@10},&error));
            assert([[NSData dataWithContentsOfFile:path] isEqual:invalid]);
        }
        notify_cancel(token);
        [NSFileManager.defaultManager removeItemAtPath:folder error:NULL];
        puts("PASS settings store: XML/binary, synchronous readback before notify, non-target keys, backup, permissions, busy/invalid input refusal");
    }
    return 0;
}

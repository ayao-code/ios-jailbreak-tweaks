#import "device_import_probe.h"
#import "IPAImport.h"
#import "AppDuplicator.h"
#include <stdlib.h>
#include <CommonCrypto/CommonDigest.h>

static NSString *hashFile(NSString *path) {
    FILE *file=fopen(path.fileSystemRepresentation,"rb");
    if(!file) return @"";
    CC_SHA256_CTX context; CC_SHA256_Init(&context);
    unsigned char buffer[65536],digest[CC_SHA256_DIGEST_LENGTH]; size_t count;
    while((count=fread(buffer,1,sizeof(buffer),file))) CC_SHA256_Update(&context,buffer,(CC_LONG)count);
    BOOL ok=!ferror(file); fclose(file); if(!ok) return @"";
    CC_SHA256_Final(digest,&context); NSMutableString *result=[NSMutableString string];
    for(unsigned i=0;i<sizeof(digest);i++) [result appendFormat:@"%02x",digest[i]];
    return result;
}

static void writeRecord(NSDictionary *record) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
    fwrite(data.bytes,1,data.length,stdout); fputc('\n',stdout); fflush(stdout);
}
int cloneRunImportProbe(NSString *path) {
    NSURL *url=[NSURL fileURLWithPath:path];
    NSError *error=nil;
    NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:&error];
    NSString *sourceHash=hashFile(url.path);
    writeRecord(@{@"event":@"start",@"home":NSHomeDirectory(),@"source":url.path,
        @"import_root":cloneImportRoot().path,@"source_bytes":attrs[NSFileSize]?:@0,
        @"source_error":error.description?:@""});
    cloneStageImport(url,^(NSURL *staged,NSError *failure){
        writeRecord(@{@"event":@"complete",@"success":@(staged!=nil),
            @"staged_path":staged.path?:@"",@"error":failure.description?:@"",
            @"main_thread":@(NSThread.isMainThread),@"source_sha256":sourceHash,
            @"source_after_sha256":hashFile(url.path),@"copy_sha256":staged?hashFile(staged.path):@""});
        if(staged) [NSFileManager.defaultManager removeItemAtURL:staged.URLByDeletingLastPathComponent error:nil];
        exit(staged?0:1);
    });
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:45];
    while(deadline.timeIntervalSinceNow>0) {
        @autoreleasepool { [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]]; }
    }
    writeRecord(@{@"event":@"timeout",@"success":@NO});
    return 2;
}
int cloneRunGroupGenerationProbe(NSString *path) {
    NSString *before=hashFile(path);NSError *error=nil;
    AppDuplicator *duplicator=[AppDuplicator new];
    NSDictionary *result=[duplicator createUpstreamCloneFromURL:[NSURL fileURLWithPath:path]
        name:@"共享组生成自检" disableCallbacks:YES isolateSharedGroup:YES error:&error];
    NSString *after=hashFile(path);
    writeRecord(@{@"event":@"group-generation",@"success":@(result!=nil),
        @"result":result?:@{},@"error":error.description?:@"",@"source_sha256":before,
        @"source_unchanged":@(before.length && [before isEqual:after])});
    // Delete only the IPA created by this explicit probe, not any user's output.
    if(result) {
        NSError *cleanup=nil;BOOL removed=[NSFileManager.defaultManager removeItemAtPath:result[@"ipa"] error:&cleanup];
        writeRecord(@{@"event":@"cleanup",@"removed":@(removed),@"error":cleanup.description?:@""});
        if(!removed) return 3;
    }
    return result && [before isEqual:after]?0:1;
}

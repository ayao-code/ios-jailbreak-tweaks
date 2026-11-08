#import "IPAImport.h"
extern NSString *docPath(void);

static NSError *importError(NSInteger code, NSString *message, NSError *underlying) {
    NSMutableDictionary *info=[@{NSLocalizedDescriptionKey:message} mutableCopy];
    if(underlying) info[NSUnderlyingErrorKey]=underlying;
    return [NSError errorWithDomain:@"CloneStudioImport" code:code userInfo:info];
}

NSURL *cloneImportRoot(void) {
    // Keep all tool-created imports under the export root; never stage in
    // another app's container. Inbox reads require the tool's storage grant.
    return [NSURL fileURLWithPath:[docPath() stringByAppendingPathComponent:@".imports"] isDirectory:YES];
}

BOOL cloneCanImportURL(NSURL *url) {
    return url.isFileURL && [@[@"ipa", @"tipa"] containsObject:url.pathExtension.lowercaseString];
}
void cloneStageImport(NSURL *url, void (^completion)(NSURL *, NSError *)) {
    if(!cloneCanImportURL(url)) {
        dispatch_async(dispatch_get_main_queue(),^{completion(nil,[NSError errorWithDomain:@"CloneStudioImport" code:1 userInfo:@{NSLocalizedDescriptionKey:@"请选择 .ipa 或 .tipa 文件。"}]);});
        return;
    }
    BOOL scoped=[url startAccessingSecurityScopedResource];
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once,^{queue=dispatch_queue_create("com.ayao.clonestudio.import",DISPATCH_QUEUE_SERIAL);});
    dispatch_async(queue,^{
        NSFileManager *fm=NSFileManager.defaultManager;
        NSURL *cache=cloneImportRoot().URLByDeletingLastPathComponent;
        if(!cache) {
            if(scoped) [url stopAccessingSecurityScopedResource];
            dispatch_async(dispatch_get_main_queue(),^{completion(nil,[NSError errorWithDomain:@"CloneStudioImport" code:4 userInfo:@{NSLocalizedDescriptionKey:@"没有可用的工具缓存目录。"}]);});
            return;
        }
        NSURL *directory=[cloneImportRoot() URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        NSURL *destination=[directory URLByAppendingPathComponent:url.lastPathComponent];
        NSError *coordinationError=nil;
        __block NSError *copyError=nil;
        __block BOOL copied=NO;
        void (^copySource)(NSURL *)=^(NSURL *source){
            NSDictionary *attrs=[fm attributesOfItemAtPath:source.path error:&copyError];
            if(!attrs) return;
            if(![attrs[NSFileType] isEqual:NSFileTypeRegular] ||
               ![attrs[NSFileSize] unsignedLongLongValue] ||
               [attrs[NSFileSize] unsignedLongLongValue]>UINT64_C(2147483648)) {
                copyError=importError(2,@"输入必须是非空的普通文件，且不超过 2 GiB。",nil);
                return;
            }
            if(![fm createDirectoryAtURL:cache withIntermediateDirectories:YES attributes:nil error:&copyError]) return;
            NSDictionary *space=[fm attributesOfFileSystemForPath:cache.path error:&copyError];
            if(!space) return;
            if([space[NSFileSystemFreeSize] unsignedLongLongValue]<[attrs[NSFileSize] unsignedLongLongValue]+67108864) {
                copyError=importError(3,@"导入副本的存储空间不足。",nil);
                return;
            }
            NSDictionary *permissions=@{NSFilePosixPermissions:@0700};
            if(![fm createDirectoryAtURL:cloneImportRoot() withIntermediateDirectories:YES attributes:permissions error:&copyError]) return;
            if(![fm createDirectoryAtURL:directory withIntermediateDirectories:NO attributes:permissions error:&copyError]) return;
            if(![fm copyItemAtURL:source toURL:destination error:&copyError]) return;
            NSDictionary *staged=[fm attributesOfItemAtPath:destination.path error:&copyError];
            if(!staged) return;
            NSDictionary *after=[fm attributesOfItemAtPath:source.path error:&copyError];
            if(!after) return;
            copied=staged && after && [staged[NSFileType] isEqual:NSFileTypeRegular] &&
                [staged[NSFileSize] isEqual:attrs[NSFileSize]] &&
                [after[NSFileSize] isEqual:attrs[NSFileSize]] &&
                [after[NSFileModificationDate] isEqual:attrs[NSFileModificationDate]] &&
                [fm isReadableFileAtPath:destination.path];
            if(copied) {
                NSFileHandle *reader=[NSFileHandle fileHandleForReadingFromURL:destination error:&copyError];
                copied=reader!=nil;
                [reader closeFile];
            }
            if(!copied && !copyError) copyError=importError(5,@"文件复制不完整或源文件发生变化，请重新分享。",nil);
        };
        NSString *home=[NSHomeDirectory() stringByResolvingSymlinksInPath];
        NSString *resolved=[url.path stringByResolvingSymlinksInPath];
        if([resolved hasPrefix:[home stringByAppendingString:@"/"]]) {
            // Open-in has already delivered a local copy to our Documents/Inbox.
            copySource(url);
        } else {
            NSFileCoordinator *coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];
            [coordinator coordinateReadingItemAtURL:url options:NSFileCoordinatorReadingWithoutChanges
                error:&coordinationError byAccessor:copySource];
        }
        if(scoped) [url stopAccessingSecurityScopedResource];
        // The coordinator can clear its out-error on success. Never share it
        // with the accessor's error, or a failed copy can appear successful.
        NSError *underlying=copyError?:coordinationError;
        NSError *error=(!copied || underlying)?importError(6,
            [NSString stringWithFormat:@"无法导入 %@：%@",url.lastPathComponent,underlying.localizedDescription?:@"未取得可读取的文件副本。"],underlying):nil;
        if(error) [fm removeItemAtURL:directory error:nil];
        dispatch_async(dispatch_get_main_queue(),^{completion(error?nil:destination,error);});
    });
}

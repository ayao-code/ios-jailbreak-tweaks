#import "AppDuplicator.h"
#import "ClonePolicy.h"
#import "MachOInspector.h"
#import "GroupMigration.h"
#import "thirdparty/SSZipArchive/SSZipArchive.h"
#include "thirdparty/SSZipArchive/minizip/unzip.h"
#include <spawn.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <CommonCrypto/CommonDigest.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
extern char **environ;
extern NSString *docPath(void);

static NSUserDefaults *identityDefaults(void) {
#if CLONE_HOST_TEST
    return [[NSUserDefaults alloc] initWithSuiteName:@"CloneStudioHostFixture"];
#else
    return NSUserDefaults.standardUserDefaults;
#endif
}

static BOOL fail(NSError **error, NSString *message) {
    if(error) *error=[NSError errorWithDomain:@"CloneStudio" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}
static NSString *fileHash(NSString *path) {
    FILE *f=fopen(path.fileSystemRepresentation,"rb"); if(!f) return nil;
    CC_SHA256_CTX context; CC_SHA256_Init(&context);
    unsigned char buffer[65536], digest[CC_SHA256_DIGEST_LENGTH]; size_t n;
    while((n=fread(buffer,1,sizeof(buffer),f))) CC_SHA256_Update(&context,buffer,(CC_LONG)n);
    BOOL ok=!ferror(f); fclose(f); if(!ok) return nil;
    CC_SHA256_Final(digest,&context); NSMutableString *out=[NSMutableString string];
    for(unsigned i=0;i<sizeof(digest);i++) [out appendFormat:@"%02x",digest[i]];
    return out;
}
static unsigned currentOS(void) {
#if CLONE_HOST_TEST
    return 16<<16 | 3<<8 | 1;
#else
    NSOperatingSystemVersion v=NSProcessInfo.processInfo.operatingSystemVersion;
    return (unsigned)(v.majorVersion<<16 | v.minorVersion<<8 | v.patchVersion);
#endif
}
static NSString *signerPath(void) {
#if CLONE_HOST_TEST
    return NSProcessInfo.processInfo.environment[@"CLONE_FIXTURE_SIGNER"];
#else
    // Only use the installed TrollStore tool, never /var/jb/bin or downloaded arbitrary helpers.
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *root=@"/var/containers/Bundle/Application";
    for(NSString *folder in [fm contentsOfDirectoryAtPath:root error:nil]) {
        NSString *app=[[root stringByAppendingPathComponent:folder] stringByAppendingPathComponent:@"TrollStore.app"];
        NSDictionary *info=[NSDictionary dictionaryWithContentsOfFile:[app stringByAppendingPathComponent:@"Info.plist"]];
        NSString *path=[app stringByAppendingPathComponent:@"ldid"];
        if([info[@"CFBundleIdentifier"] isEqual:@"com.opa334.TrollStore"] && [fm isExecutableFileAtPath:path]) return path;
    }
    return nil;
#endif
}
static NSData *signerRun(NSString *signer, NSArray<NSString *> *arguments, NSString *logPath, NSError **error) {
    posix_spawn_file_actions_t actions; posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions,STDOUT_FILENO,logPath.fileSystemRepresentation,O_WRONLY|O_CREAT|O_TRUNC,0600);
    posix_spawn_file_actions_addopen(&actions,STDERR_FILENO,"/dev/null",O_WRONLY,0);
    NSMutableArray *args=[NSMutableArray arrayWithObject:signer]; [args addObjectsFromArray:arguments];
    char **argv=calloc(args.count+1,sizeof(char *));
    if(!argv) { posix_spawn_file_actions_destroy(&actions); fail(error,@"签名参数内存分配失败。"); return nil; }
    for(NSUInteger i=0;i<args.count;i++) argv[i]=(char *)[args[i] UTF8String];
    pid_t pid; int code=posix_spawn(&pid,signer.fileSystemRepresentation,&actions,NULL,argv,environ);
    free(argv); posix_spawn_file_actions_destroy(&actions);
    int status=0; pid_t waited=-1;
    if(!code) {
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:120];
        do {
            waited=waitpid(pid,&status,WNOHANG);
            if(waited==0) [NSThread sleepForTimeInterval:0.1];
        } while((waited==0 || (waited<0 && errno==EINTR)) && deadline.timeIntervalSinceNow>0);
        if(waited==0) { kill(pid,SIGKILL); do { waited=waitpid(pid,&status,0); } while(waited<0 && errno==EINTR); }
    }
    if(code || waited<0 || !WIFEXITED(status) || WEXITSTATUS(status)) { fail(error,@"TrollStore 签名工具执行失败；没有生成可安装文件。"); return nil; }
    return [NSData dataWithContentsOfFile:logPath];
}
static NSDictionary *readEntitlements(NSString *signer, NSString *path, NSString *log, NSError **error) {
    NSData *data=signerRun(signer,@[@"-e",path],log,error); if(!data) return nil;
    // ldid prints one XML document per CPU slice. Require identical dictionaries.
    NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSRegularExpression *regex=[NSRegularExpression regularExpressionWithPattern:@"<\\?xml[\\s\\S]*?</plist>" options:0 error:nil];
    NSArray *matches=text?[regex matchesInString:text options:0 range:NSMakeRange(0,text.length)]:@[];
    if(data.length && !matches.count) { fail(error,@"签名权限输出无法解析；不会按空权限继续。"); return nil; }
    NSDictionary *result=nil;
    for(NSTextCheckingResult *match in matches) {
        NSData *xml=[[text substringWithRange:match.range] dataUsingEncoding:NSUTF8StringEncoding];
        id value=[NSPropertyListSerialization propertyListWithData:xml options:NSPropertyListImmutable format:NULL error:nil];
        if(![value isKindOfClass:NSDictionary.class] || (result && ![result isEqual:value])) { fail(error,@"CPU 切片权限不一致或无法解析；请先检查原包。"); return nil; }
        result=value;
    }
    return result?:@{};
}
static BOOL safeTree(NSString *root, NSError **error) {
    NSFileManager *fm=NSFileManager.defaultManager;
    NSDictionary *rootAttr=[fm attributesOfItemAtPath:root error:error];
    if(![rootAttr[NSFileType] isEqual:NSFileTypeDirectory]) return fail(error,@"输入必须是普通 App 目录。");
    NSDirectoryEnumerator *items=[fm enumeratorAtPath:root];
    uint64_t bytes=0; NSUInteger count=0;
    for(NSString *name in items) {
        NSDictionary *a=[fm attributesOfItemAtPath:[root stringByAppendingPathComponent:name] error:error];
        if(!a || (![a[NSFileType] isEqual:NSFileTypeRegular] && ![a[NSFileType] isEqual:NSFileTypeDirectory])) return fail(error,@"第一版不接受符号链接或特殊文件的 App 包。");
        uint64_t size=[a[NSFileSize] unsignedLongLongValue];
        if(size>UINT64_C(2147483648)-bytes || ++count>50000) return fail(error,@"App 包超过第一版 2 GiB / 5 万项限制。");
        if([a[NSFileType] isEqual:NSFileTypeRegular]) bytes+=size;
    }
    NSDictionary *space=[fm attributesOfFileSystemForPath:docPath() error:error];
    if(!space || [space[NSFileSystemFreeSize] unsignedLongLongValue]<bytes*3+268435456) return fail(error,@"可用工作空间不足。");
    return YES;
}
static BOOL validateZip(NSString *path, NSError **error) {
    unzFile file=unzOpen64(path.fileSystemRepresentation); if(!file) return fail(error,@"无法读取 IPA。");
    NSMutableSet *names=[NSMutableSet set]; uint64_t total=0; BOOL ok=YES;
    int state=unzGoToFirstFile(file); unsigned char buffer[32768];
    while(state==UNZ_OK) {
        unz_file_info64 info; char name[4096]={0};
        if(unzGetCurrentFileInfo64(file,&info,name,sizeof(name),NULL,0,NULL,0)!=UNZ_OK || info.size_filename>=sizeof(name) || memchr(name,0,info.size_filename)) { ok=NO; break; }
        NSString *entry=[[NSString alloc] initWithBytes:name length:info.size_filename encoding:NSUTF8StringEncoding];
        BOOL directory=[entry hasSuffix:@"/"];
        NSString *canonical=directory?[entry substringToIndex:entry.length-1]:entry;
        NSArray *parts=[canonical componentsSeparatedByString:@"/"];
        unsigned type=(info.external_fa>>16)&S_IFMT;
        if(!entry.length || !canonical.length || [entry hasPrefix:@"/"] || [entry containsString:@"\\"] ||
           [parts containsObject:@".."] || [parts containsObject:@"."] || [parts containsObject:@""] ||
           [names containsObject:canonical.precomposedStringWithCanonicalMapping.lowercaseString] || (type && type!=S_IFREG && type!=S_IFDIR) || (info.flag&1) ||
           info.uncompressed_size>UINT64_C(2147483648)-total || names.count>=50000) { ok=NO; break; }
        [names addObject:canonical.precomposedStringWithCanonicalMapping.lowercaseString]; total+=info.uncompressed_size;
        if(unzOpenCurrentFile(file)!=UNZ_OK) { ok=NO; break; }
        uint64_t read=0; int n;
        while((n=unzReadCurrentFile(file,buffer,sizeof(buffer)))>0) read+=(unsigned)n;
        int closed=unzCloseCurrentFile(file);
        if(n<0 || read!=info.uncompressed_size || closed!=UNZ_OK) { ok=NO; break; }
        state=unzGoToNextFile(file);
    }
    if(state!=UNZ_END_OF_LIST_OF_FILE) ok=NO;
    unzClose(file);
    if(!ok) {
        return fail(error,@"IPA 路径、CRC、文件类型或展开大小检查失败（上限 2 GiB / 5 万项）。"); }
    NSDictionary *space=[NSFileManager.defaultManager attributesOfFileSystemForPath:docPath() error:nil];
    if([space[NSFileSystemFreeSize] unsignedLongLongValue]<total*3+268435456) return fail(error,@"可用空间不足：需要展开大小的约 3 倍加 256 MiB。");
    return YES;
}

@implementation AppDuplicator
- (NSDictionary *)createUpstreamCloneFromURL:(NSURL *)input name:(NSString *)name disableCallbacks:(BOOL)disable error:(NSError **)error {
    return [self createUpstreamCloneFromURL:input name:name disableCallbacks:disable isolateSharedGroup:NO error:error];
}
- (NSString *)migrateSharedGroupInApp:(NSString *)app cloneID:(NSString *)cloneID work:(NSString *)work error:(NSError **)error {
    NSString *old=@"group.cn.damai.damaiApp";
    NSString *signer=signerPath(); if(!signer) { fail(error,@"共享组隔离需要现有 TrollStore 的 ldid。"); return nil; }
    NSMutableData *key=[[cloneID dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    unsigned char zero=0;[key appendBytes:&zero length:1];[key appendData:[old dataUsingEncoding:NSUTF8StringEncoding]];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(key.bytes,(CC_LONG)key.length,digest);
    NSString *next=[NSString stringWithFormat:@"group.cn.damai.%02x%02x%02x%02x",digest[0],digest[1],digest[2],digest[3]];
    NSString *os=[old stringByAppendingString:@"OS"];
    NSFileManager *fm=NSFileManager.defaultManager;
    NSArray *paths=[fm subpathsOfDirectoryAtPath:app error:error];if(!paths) return nil;
    NSMutableDictionary *unchanged=[NSMutableDictionary dictionary];NSUInteger total=0;
    BOOL mainChanged=NO;
    NSString *mainName=[NSDictionary dictionaryWithContentsOfFile:[app stringByAppendingPathComponent:@"Info.plist"]][@"CFBundleExecutable"];
    for(NSString *relative in paths) {
        NSString *path=[app stringByAppendingPathComponent:relative];
        NSDictionary *attrs=[fm attributesOfItemAtPath:path error:error];if(!attrs) return nil;
        if(![attrs[NSFileType] isEqual:NSFileTypeRegular]) continue;
        CloneMachOInfo m=cloneInspectMachO(path.fileSystemRepresentation);
        if(m.malformed) { fail(error,@"共享组预检遇到损坏或不可读程序。"); return nil; }
        if(!m.is_macho) { NSString *hash=fileHash(path);if(!hash) return nil;unchanged[relative]=hash;continue; }
        CloneGroupPlan *plan=cloneGroupPlan(path.fileSystemRepresentation,old.UTF8String);
        if(!plan) { fail(error,[NSString stringWithFormat:@"共享组隔离不支持 %@ 的格式或组名位置。",relative]); return nil; }
        @try {
            NSString *log=[work stringByAppendingPathComponent:@"group-signer-output.xml"];
            NSDictionary *original=readEntitlements(signer,path,log,error);if(!original) return nil;
            id grants=original[@"com.apple.security.application-groups"];
            if(grants && (![grants isKindOfClass:NSArray.class] || ![(NSArray *)grants count])) { fail(error,@"共享组权限格式无法处理。"); return nil; }
            NSMutableDictionary *ent=[original mutableCopy];NSMutableArray *groups=[NSMutableArray array];
            for(id g in grants) {
                if(![g isKindOfClass:NSString.class]) { fail(error,@"共享组权限格式无法处理。");return nil; }
                [groups addObject:[g isEqual:old]?next:([g isEqual:os]?[next stringByAppendingString:@"OS"]:g)];
            }
            if(grants) ent[@"com.apple.security.application-groups"]=groups;
            BOOL changed=cloneGroupPatchCount(plan)>0 || ![ent isEqual:original];
            if(!changed) { unchanged[relative]=fileHash(path);continue; }
            NSString *before=[work stringByAppendingPathComponent:@"group-before-sign"];
            if(![fm copyItemAtPath:path toPath:before error:error]) return nil;
            if(!cloneGroupApply(path.fileSystemRepresentation,plan,old.UTF8String,next.UTF8String)) { fail(error,@"共享组字符串校验或写入失败。");return nil; }
            NSString *xml=[work stringByAppendingPathComponent:@"group-entitlements.plist"];
            if(![ent writeToFile:xml atomically:YES] || !signerRun(signer,@[[@"-S" stringByAppendingString:xml],path],log,error)) return nil;
            NSDictionary *readback=readEntitlements(signer,path,log,error);if(!readback) return nil;
            if(![readback isEqual:ent] || !cloneGroupVerify(before.fileSystemRepresentation,path.fileSystemRepresentation,plan,old.UTF8String,next.UTF8String)) {
                fail(error,@"共享组重签改变了非目标权限、代码或加密内容，拒绝生成。");return nil;
            }
            if(![fm removeItemAtPath:before error:error]) return nil;
            total+=cloneGroupPatchCount(plan);if([relative isEqual:mainName]) mainChanged=YES;
        } @finally { cloneGroupFree(plan); }
    }
    if(!total || !mainChanged) { fail(error,@"未找到可迁移的大麦主程序共享组，未生成隔离候选。");return nil; }
    for(NSString *relative in unchanged) if(![unchanged[relative] isEqual:fileHash([app stringByAppendingPathComponent:relative])]) {
        fail(error,@"共享组处理改变了非目标文件。");return nil;
    }
    return next;
}
- (NSDictionary *)createUpstreamCloneFromURL:(NSURL *)input name:(NSString *)name disableCallbacks:(BOOL)disable isolateSharedGroup:(BOOL)isolate error:(NSError **)error {
    NSFileManager *fm=NSFileManager.defaultManager;
    if(!input.isFileURL || !name.length || name.length>80) { fail(error,@"请输入 1–80 字的分身名称。"); return nil; }
    NSString *work=[docPath() stringByAppendingPathComponent:[@".upstream-work-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    if(![fm createDirectoryAtPath:work withIntermediateDirectories:NO attributes:nil error:error]) return nil;
    NSString *ipa=nil; NSDictionary *result=nil;
    @try {
        NSString *package=[work stringByAppendingPathComponent:@"package"];
        NSString *payload=[package stringByAppendingPathComponent:@"Payload"];
        BOOL directory=NO;
        if(![fm fileExistsAtPath:input.path isDirectory:&directory]) { fail(error,@"输入文件不存在。"); return nil; }
        if(directory) {
            if(![input.pathExtension.lowercaseString isEqual:@"app"] || !safeTree(input.path,error)) return nil;
            if(![fm createDirectoryAtPath:payload withIntermediateDirectories:YES attributes:nil error:error] ||
               ![fm copyItemAtPath:input.path toPath:[payload stringByAppendingPathComponent:input.lastPathComponent] error:error]) return nil;
        } else {
            if(![@[@"ipa",@"tipa"] containsObject:input.pathExtension.lowercaseString]) { fail(error,@"请选择 IPA 或 tipa。"); return nil; }
            NSString *hash=fileHash(input.path);
            if(!hash || !validateZip(input.path,error)) return nil;
            if(![SSZipArchive unzipFileAtPath:input.path toDestination:package] || ![hash isEqual:fileHash(input.path)]) { fail(error,@"解包失败或源文件发生变化。"); return nil; }
        }
        NSArray *entries=[fm contentsOfDirectoryAtPath:payload error:error];
        if(entries.count!=1 || ![[entries.firstObject pathExtension] isEqual:@"app"]) { fail(error,@"IPA 必须只包含一个主 App。"); return nil; }
        NSString *app=[payload stringByAppendingPathComponent:entries.firstObject];
        if(!safeTree(app,error)) return nil;
        NSString *infoPath=[app stringByAppendingPathComponent:@"Info.plist"];
        NSMutableDictionary *info=[[NSDictionary dictionaryWithContentsOfFile:infoPath] mutableCopy];
        NSString *sourceID=info[@"CFBundleIdentifier"],*executable=info[@"CFBundleExecutable"];
        if(![sourceID isKindOfClass:NSString.class] || !sourceID.length || [sourceID hasPrefix:@"com.apple."] ||
           ![executable isKindOfClass:NSString.class] || !executable.length || [executable containsString:@"/"] ||
           [@[@".",@".."] containsObject:executable]) { fail(error,@"主应用身份或程序路径不合法。"); return nil; }
        NSCharacterSet *invalid=[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"] invertedSet];
        if([sourceID rangeOfCharacterFromSet:invalid].location!=NSNotFound || [sourceID containsString:@".."] ||
           [sourceID hasPrefix:@"."] || [sourceID hasSuffix:@"."]) { fail(error,@"原应用 ID 含不合法字符。"); return nil; }
        CloneMachOInfo main=cloneInspectMachO([app stringByAppendingPathComponent:executable].fileSystemRepresentation);
        if(!main.is_macho || main.malformed || main.encrypted) { fail(error,@"主程序加密或无法读取，不能制作。"); return nil; }
        if(isolate && ![sourceID isEqual:@"cn.damai.iphone"]) { fail(error,@"共享组隔离实验仅支持从原始大麦解密 IPA 生成，不接受其它 App 或再次克隆分身。");return nil; }
        // Creation always allocates a fresh identity, even for identical names.
        // Legacy per-source update mappings are deliberately neither read nor written.
        NSString *cloneID=[sourceID stringByAppendingFormat:@".%@",NSUUID.UUID.UUIDString.lowercaseString];
        if([cloneID isEqual:sourceID] || ![cloneID hasPrefix:[sourceID stringByAppendingString:@"."]] ||
           [cloneID rangeOfCharacterFromSet:invalid].location!=NSNotFound || [cloneID containsString:@".."]) { fail(error,@"实验身份映射不合法。"); return nil; }
        info[@"CFBundleIdentifier"]=cloneID;
        info[@"CFBundleDisplayName"]=name;
        if(disable) [info removeObjectForKey:@"CFBundleURLTypes"];
        if(![info writeToFile:infoPath atomically:YES]) { fail(error,@"写入副本信息失败。"); return nil; }
        NSString *newGroup=nil;
        if(isolate) { newGroup=[self migrateSharedGroupInApp:app cloneID:cloneID work:work error:error];if(!newGroup) return nil; }
        // Without group migration, keep original binaries and signatures.
        // With migration, only group constants/grants and signatures change.
        // TrollStore may transform them on install; no runtime isolation claim.
        ipa=[docPath() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-callbacks-%@-group-%@-%@.ipa",cloneID,disable?@"off":@"on",isolate?@"new":@"original",NSUUID.UUID.UUIDString]];
        if(![SSZipArchive createZipFileAtPath:ipa withContentsOfDirectory:package keepParentDirectory:NO compressionLevel:1 password:nil AES:NO progressHandler:nil] || !validateZip(ipa,error)) return nil;
        result=@{@"ipa":ipa,@"cloneID":cloneID,@"disable_callbacks":@(disable),@"experimental":@YES,
                 @"isolate_shared_group":@(isolate),@"new_group":newGroup?:@""};
        return result;
    } @catch(NSException *exception) {
        fail(error,@"制作异常，未交付候选包。"); return nil;
    } @finally {
        [fm removeItemAtPath:work error:nil];
        if(!result && ipa) [fm removeItemAtPath:ipa error:nil];
    }
}
- (NSDictionary *)createCloneFromURL:(NSURL *)input name:(NSString *)name protectOriginal:(BOOL)protect error:(NSError **)error {
    NSFileManager *fm=NSFileManager.defaultManager;
    if(!input.isFileURL || !name.length || name.length>80) { fail(error,@"请输入 1–80 字的分身名称。"); return nil; }
    NSString *signer=signerPath(); if(!signer) { fail(error,@"没有找到现有 TrollStore 的 ldid；本工具不会自动下载签名器。"); return nil; }
    NSString *work=[docPath() stringByAppendingPathComponent:[@".work-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    if(![fm createDirectoryAtPath:work withIntermediateDirectories:NO attributes:nil error:error]) return nil;
    NSString *ipa=nil,*reportPath=nil; NSDictionary *result=nil;
    @try {
        NSString *packageDir=[work stringByAppendingPathComponent:@"package"];
        NSString *payload=[packageDir stringByAppendingPathComponent:@"Payload"];
        BOOL directory=NO; [fm fileExistsAtPath:input.path isDirectory:&directory];
        NSString *sourceHash=directory?nil:fileHash(input.path);
        if(directory) {
            if(![input.path.pathExtension.lowercaseString isEqual:@"app"] || !safeTree(input.path,error)) return nil;
            if([input.path hasPrefix:docPath()]) { fail(error,@"不能把工具自己的输出目录作为已安装 App 输入。"); return nil; }
            if(![fm createDirectoryAtPath:payload withIntermediateDirectories:YES attributes:nil error:error]) return nil;
            if(![fm copyItemAtPath:input.path toPath:[payload stringByAppendingPathComponent:input.lastPathComponent] error:error]) return nil;
        } else {
            if(![@[@"ipa",@"tipa"] containsObject:input.path.pathExtension.lowercaseString] || !sourceHash) { fail(error,@"请选择可读取的 .ipa 或 .tipa 文件。"); return nil; }
            if(!validateZip(input.path,error)) return nil;
            NSString *importDir=[work stringByAppendingPathComponent:@"import"];
            if(![SSZipArchive unzipFileAtPath:input.path toDestination:importDir] || ![sourceHash isEqual:fileHash(input.path)]) { fail(error,@"解包失败或输入文件在读取期间发生变化。"); return nil; }
            if(![fm createDirectoryAtPath:packageDir withIntermediateDirectories:YES attributes:nil error:error] || ![fm moveItemAtPath:[importDir stringByAppendingPathComponent:@"Payload"] toPath:payload error:error]) return nil;
        }
        NSArray *payloadItems=[fm contentsOfDirectoryAtPath:payload error:error];
        NSArray *apps=[payloadItems filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *s,NSDictionary *b){return [s.pathExtension isEqual:@"app"];}]];
        if(apps.count!=1) { fail(error,@"IPA 必须包含一个主 App。"); return nil; }
        if(payloadItems.count!=1) { fail(error,@"Payload 中有额外条目，第一版拒绝混合包。"); return nil; }
        NSString *app=[payload stringByAppendingPathComponent:apps.firstObject]; if(!safeTree(app,error)) return nil;
        NSString *infoPath=[app stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info=[NSDictionary dictionaryWithContentsOfFile:infoPath];
        NSString *sourceID=info[@"CFBundleIdentifier"],*mainName=info[@"CFBundleExecutable"];
        if(![sourceID isKindOfClass:NSString.class] || ![mainName isKindOfClass:NSString.class] || !sourceID.length || !mainName.length || [mainName containsString:@"/"] || [mainName isEqual:@".."] || [mainName isEqual:@"."] || [sourceID hasPrefix:@"com.apple."]) { fail(error,@"主应用身份不合法或是系统 App。"); return nil; }
        NSString *minimum=info[@"MinimumOSVersion"];
        if([minimum isKindOfClass:NSString.class]) {
            // Both bundle metadata and load commands must accept the target system.
            NSOperatingSystemVersion v=NSProcessInfo.processInfo.operatingSystemVersion;
            NSString *os=[NSString stringWithFormat:@"%ld.%ld.%ld",(long)v.majorVersion,(long)v.minorVersion,(long)v.patchVersion];
#if CLONE_HOST_TEST
            os=@"16.3.1";
#endif
            if([minimum compare:os options:NSNumericSearch]==NSOrderedDescending) { fail(error,@"主 Info.plist 最低系统版本高于本机。"); return nil; }
        }
        NSString *mappingKey=[NSString stringWithFormat:@"clone.identity.%@.%d",sourceID,protect];
        NSString *cloneID=[identityDefaults() stringForKey:mappingKey];
        if(!cloneID.length) cloneID=[@"com.ayao.clone." stringByAppendingString:[NSUUID.UUID.UUIDString.lowercaseString stringByReplacingOccurrencesOfString:@"-" withString:@""]];
        if([cloneID isEqual:sourceID] || ![cloneID hasPrefix:@"com.ayao.clone."]) { fail(error,@"副本身份映射不合法。"); return nil; }
        NSMutableArray *removed=[NSMutableArray array],*warnings=[NSMutableArray arrayWithArray:@[@"只验证静态产物；安装后身份、登录、支付和原版不受影响均未验证。",@"删除回调注册不会阻止 App 主动跳转；共享组名可能写死在代码里。"]];
        if(!protect) [warnings addObject:@"兼容模式保留共享组、回调和服务资格声明，可能干扰原版，不是隔离保证。"];
        NSMutableDictionary *objects=[NSMutableDictionary dictionaryWithObject:cloneID forKey:app];
        NSArray *entries=[fm subpathsOfDirectoryAtPath:app error:error]; if(!entries) return nil;
        // Refuse known injected payloads before removing any optional components.
        for(NSString *relative in entries) {
            if([relative hasSuffix:@".troll-fools"] || [relative hasSuffix:@".troll-fools.bak"] || [relative containsString:@"CydiaSubstrate.framework"] || [relative containsString:@"AutoSkipGuard"]) { fail(error,@"包内存在已知注入或备份文件，请使用未加插件的基线。"); return nil; }
        }
        for(NSString *relative in entries) {
            if([@[@"appex",@"app"] containsObject:relative.pathExtension]) {
                NSString *nested=[app stringByAppendingPathComponent:relative];
                if(![fm fileExistsAtPath:nested]) continue;
                if(protect) { if(![fm removeItemAtPath:nested error:error]) return nil; [removed addObject:relative]; }
                else {
                    if([relative.pathExtension isEqual:@"app"]) { fail(error,@"兼容模式第一版不支持内嵌 App/Watch App，请改用无该组件的基线。"); return nil; }
                    NSDictionary *old=[NSDictionary dictionaryWithContentsOfFile:[nested stringByAppendingPathComponent:@"Info.plist"]];
                    NSString *nestedName=old[@"CFBundleExecutable"];
                    if(![old[@"CFBundleIdentifier"] isKindOfClass:NSString.class] ||
                       ![nestedName isKindOfClass:NSString.class] || !nestedName.length ||
                       [nestedName containsString:@"/"] || [nestedName isEqual:@".."] || [nestedName isEqual:@"."]) {
                        fail(error,@"内嵌组件身份或程序路径不合法。"); return nil;
                    }
                    // Path-derived suffix avoids collisions even when upstream IDs repeat.
                    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
                    NSData *key=[relative dataUsingEncoding:NSUTF8StringEncoding];
                    CC_SHA256(key.bytes,(CC_LONG)key.length,digest);
                    NSMutableString *suffix=[NSMutableString string];
                    for(unsigned i=0;i<8;i++) [suffix appendFormat:@"%02x",digest[i]];
                    objects[nested]=[cloneID stringByAppendingFormat:@".ext%@",suffix];
                }
            }
        }
        if(protect && removed.count) [warnings addObject:@"已移除全部内嵌 App/扩展：相应功能不可用；主程序是否接受降级未实测。"];
        NSMutableDictionary *sourceFiles=[NSMutableDictionary dictionary];
        NSMutableArray *machos=[NSMutableArray array],*signingRecords=[NSMutableArray array];
        for(NSString *relative in [fm subpathsOfDirectoryAtPath:app error:error]) {
            NSString *path=[app stringByAppendingPathComponent:relative];
            NSDictionary *attributes=[fm attributesOfItemAtPath:path error:error];
            if(!attributes) return nil;
            if(![attributes[NSFileType] isEqual:NSFileTypeRegular]) continue;
            NSString *hash=fileHash(path); if(!hash) { fail(error,@"无法读取包内文件。"); return nil; } sourceFiles[relative]=hash;
            CloneMachOInfo m=cloneInspectMachO(path.fileSystemRepresentation);
            if(m.malformed || (m.is_macho && (m.encrypted || !m.has_arm64 || m.jailbreak_dependency || m.max_minimum_ios>currentOS()))) { fail(error,[NSString stringWithFormat:@"无法交付：%@ 存在加密、结构、架构、系统版本或越狱依赖问题。",relative]); return nil; }
            if(m.is_macho) [machos addObject:path];
        }
        if(![machos containsObject:[app stringByAppendingPathComponent:mainName]]) { fail(error,@"主程序不是可处理的 Mach-O。"); return nil; }
        for(NSString *bundle in objects) {
            NSDictionary *bi=[NSDictionary dictionaryWithContentsOfFile:[bundle stringByAppendingPathComponent:@"Info.plist"]];
            if(![machos containsObject:[bundle stringByAppendingPathComponent:bi[@"CFBundleExecutable"]?:@""]]) { fail(error,@"内嵌组件的程序缺失或不是可处理的 Mach-O。"); return nil; }
            NSDictionary *extension=bi[@"NSExtension"];
            NSDictionary *attributes=[extension isKindOfClass:NSDictionary.class]?extension[@"NSExtensionAttributes"]:nil;
            if(!protect && ([attributes isKindOfClass:NSDictionary.class] && attributes[@"WKAppBundleIdentifier"])) { fail(error,@"第一版兼容模式不支持 Watch 关联扩展，不能只改 ID 冒充已适配。"); return nil; }
        }
        for(NSString *bundle in objects) {
            NSString *ip=[bundle stringByAppendingPathComponent:@"Info.plist"];
            NSDictionary *old=[NSDictionary dictionaryWithContentsOfFile:ip];
            NSDictionary *next=cloneInfoDictionary(old,objects[bundle],[bundle isEqual:app]?name:nil,protect);
            if(![next writeToFile:ip atomically:YES]) { fail(error,@"写入副本 Info.plist 失败。"); return nil; }
            for(NSString *relative in [fm contentsOfDirectoryAtPath:bundle error:nil]) if([relative.pathExtension isEqual:@"lproj"]) {
                NSString *strings=[[bundle stringByAppendingPathComponent:relative] stringByAppendingPathComponent:@"InfoPlist.strings"];
                NSMutableDictionary *localized=[[NSDictionary dictionaryWithContentsOfFile:strings] mutableCopy];
                if(localized && [bundle isEqual:app]) { localized[@"CFBundleDisplayName"]=name; localized[@"CFBundleName"]=name; if(![localized writeToFile:strings atomically:YES]) { fail(error,@"更新本地化显示名称失败。"); return nil; } }
            }
        }
        // Only copied files are signed. App identities use exact nonempty entitlements; frameworks do not inherit app privileges.
        NSArray *sorted=[machos sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b){return a.length==b.length?[a compare:b]:(a.length>b.length?NSOrderedAscending:NSOrderedDescending);}];
        for(NSString *path in sorted) {
            NSString *bundle=nil;
            for(NSString *candidate in objects) {
                NSDictionary *bi=[NSDictionary dictionaryWithContentsOfFile:[candidate stringByAppendingPathComponent:@"Info.plist"]];
                if([path isEqual:[candidate stringByAppendingPathComponent:bi[@"CFBundleExecutable"]?:@""]]) { bundle=candidate; break; }
            }
            NSString *log=[work stringByAppendingPathComponent:@"signer-output.xml"];
            if(![fm setAttributes:@{NSFilePosixPermissions:@0755} ofItemAtPath:path error:error]) return nil;
            NSDictionary *old=readEntitlements(signer,path,log,error); if(!old) return nil;
            NSDictionary *next=bundle?cloneEntitlements(old,objects[bundle],protect):@{};
            NSString *beforeSign=[work stringByAppendingPathComponent:@"binary-before-sign"];
            if(![fm copyItemAtPath:path toPath:beforeSign error:error]) return nil;
            NSString *xml=[work stringByAppendingPathComponent:@"entitlements.xml"];
            if(![next writeToFile:xml atomically:YES] || !signerRun(signer,@[[@"-S" stringByAppendingString:xml],path],log,error)) return nil;
            if(!cloneMachOCodeEqual(beforeSign.fileSystemRepresentation,path.fileSystemRepresentation)) { fail(error,@"签名修改了代码指令，拒绝交付。"); return nil; }
            if(![fm removeItemAtPath:beforeSign error:error]) return nil;
            NSDictionary *readback=readEntitlements(signer,path,log,error);
            if(![readback isEqual:next]) { fail(error,@"副本签名权限回读不一致。"); return nil; }
            CloneMachOInfo check=cloneInspectMachO(path.fileSystemRepresentation);
            if(check.malformed || check.encrypted || check.jailbreak_dependency) { fail(error,@"签名后 Mach-O 结构或依赖检查失败。"); return nil; }
            [signingRecords addObject:@{@"path":[path substringFromIndex:app.length+1],@"entitlements":next}];
        }
        for(NSString *relative in sourceFiles) {
            if([relative.lastPathComponent isEqual:@"Info.plist"] || [relative.lastPathComponent isEqual:@"InfoPlist.strings"] ||
               [relative containsString:@"/_CodeSignature/"] || [relative hasPrefix:@"_CodeSignature/"] ||
               [relative.lastPathComponent isEqual:@"embedded.mobileprovision"] || [machos containsObject:[app stringByAppendingPathComponent:relative]]) continue;
            if(![sourceFiles[relative] isEqual:fileHash([app stringByAppendingPathComponent:relative])]) { fail(error,@"非目标资源内容被改变，拒绝交付。"); return nil; }
        }
        NSDictionary *finalInfo=[NSDictionary dictionaryWithContentsOfFile:infoPath];
        if(![finalInfo[@"CFBundleIdentifier"] isEqual:cloneID] ||
           (protect && (finalInfo[@"CFBundleURLTypes"] || finalInfo[@"UIBackgroundModes"]))) {
            fail(error,@"最终副本身份或隔离配置回读不一致。"); return nil;
        }
        for(NSString *relative in [fm subpathsOfDirectoryAtPath:app error:nil]) if([relative.lastPathComponent isEqual:@"_CodeSignature"] || [relative.lastPathComponent isEqual:@"embedded.mobileprovision"]) {
            NSString *path=[app stringByAppendingPathComponent:relative]; if([fm fileExistsAtPath:path] && ![fm removeItemAtPath:path error:error]) return nil;
        }
        NSString *nonce=NSUUID.UUID.UUIDString;
        NSString *base=[NSString stringWithFormat:@"%@-%@",cloneID,nonce];
        ipa=[docPath() stringByAppendingPathComponent:[base stringByAppendingString:@".ipa"]];
        reportPath=[docPath() stringByAppendingPathComponent:[base stringByAppendingString:@".json"]];
        if(![SSZipArchive createZipFileAtPath:ipa withContentsOfDirectory:packageDir keepParentDirectory:NO compressionLevel:1 password:nil AES:NO progressHandler:nil] || !validateZip(ipa,error)) return nil;
        // Signing work files remain outside the packaged Payload.
        NSDictionary *report=@{@"source_bundle_id":sourceID,@"clone_bundle_id":cloneID,@"name":name,@"protect_original":@(protect),@"source_sha256":sourceHash?:@"installed bundle copy; not an atomic live snapshot",@"removed_components":removed,@"warnings":warnings,@"signed_objects":signingRecords,@"source_file_hashes":sourceFiles,@"runtime_verified":@NO,@"installed":@NO,@"signing_identity_kind":@"TrollStore-local AYAOCLONE; not Apple provisioned",@"ipa_sha256":fileHash(ipa)?:@""};
        NSData *json=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:error];
        if(!json || ![json writeToFile:reportPath options:NSDataWritingAtomic error:error]) return nil;
        [identityDefaults() setObject:cloneID forKey:mappingKey];
        result=@{@"ipa":ipa,@"report":reportPath,@"cloneID":cloneID,@"warnings":warnings};
        return result;
    } @catch(NSException *exception) {
        fail(error,@"输入包字段或打包过程异常，未生成候选；请检查包完整性。");
        return nil;
    } @finally {
        [fm removeItemAtPath:work error:nil];
        if(!result) { if(ipa) [fm removeItemAtPath:ipa error:nil]; if(reportPath) [fm removeItemAtPath:reportPath error:nil]; }
    }
}
@end

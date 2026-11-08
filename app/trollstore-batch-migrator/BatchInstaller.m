#import "BatchInstaller.h"
#import "AMFIManager.h"

#import <CommonCrypto/CommonDigest.h>
#import <spawn.h>
#import <sys/wait.h>

#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t *attr, uid_t persona, uint32_t flags);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t *attr, uid_t uid);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t *attr, uid_t gid);

@interface BatchInstaller ()
@property(nonatomic, readwrite, getter=isRunning) BOOL running;
@end

@implementation BatchInstaller

- (void)start {
    @synchronized (self) {
        if (self.running) {
            return;
        }
        self.running = YES;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self runInstallation];
    });
}

- (void)runInstallation {
    NSMutableArray<NSString *> *results = [NSMutableArray new];
    NSString *packageDirectory = [self packageDirectoryPath];
    if (!packageDirectory) {
        [self finishWithResults:@[@"失败：未找到“巨魔应用文件夹/manifest.tsv”。"] success:NO requiresRestart:NO];
        return;
    }

    NSString *manifestPath = [packageDirectory stringByAppendingPathComponent:@"manifest.tsv"];
    NSError *manifestError = nil;
    NSArray<NSDictionary<NSString *, NSString *> *> *packages = [self packagesFromManifestAtPath:manifestPath error:&manifestError];
    if (!packages) {
        [self finishWithResults:@[[NSString stringWithFormat:@"失败：清单无效（%@）", manifestError.localizedDescription ?: @"未知错误"]]
                        success:NO
                requiresRestart:NO];
        return;
    }
    [results addObject:[NSString stringWithFormat:@"已读取并验证 %lu 项安装清单。", (unsigned long)packages.count]];

    NSString *developerModeMessage = nil;
    DeveloperModePreparationResult developerModeResult = [AMFIManager prepareDeveloperModeWithMessage:&developerModeMessage];
    if (developerModeResult == DeveloperModePreparationResultFailed) {
        [self finishWithResults:@[developerModeMessage ?: @"开发者模式状态检查失败"] success:NO requiresRestart:NO];
        return;
    }
    [results addObject:developerModeMessage];
    if (developerModeResult == DeveloperModePreparationResultArmed) {
        [self finishWithResults:results success:NO requiresRestart:YES];
        return;
    }

    NSString *helperPath = [self trollStoreHelperPath];
    if (!helperPath) {
        [self finishWithResults:@[@"失败：未找到 TrollStore 2 的 trollstorehelper。"] success:NO requiresRestart:NO];
        return;
    }

    for (NSUInteger index = 0; index < packages.count; index++) {
        NSDictionary<NSString *, NSString *> *package = packages[index];
        NSString *name = package[@"name"];
        NSString *path = [packageDirectory stringByAppendingPathComponent:package[@"file"]];
        [self updateProgress:(double)index / (double)(packages.count + 1)
                      status:[NSString stringWithFormat:@"正在校验 %@…", name]];

        NSError *hashError = nil;
        NSString *actualHash = [self sha256ForFileAtPath:path error:&hashError];
        if (!actualHash) {
            [results addObject:[NSString stringWithFormat:@"%@：文件不可读（%@）", name, hashError.localizedDescription ?: @"未知错误"]];
            [self finishWithResults:results success:NO requiresRestart:NO];
            return;
        }
        if (![actualHash isEqualToString:package[@"sha256"]]) {
            [results addObject:[NSString stringWithFormat:@"%@：SHA-256 不匹配，已拒绝安装", name]];
            [self finishWithResults:results success:NO requiresRestart:NO];
            return;
        }

        [self updateProgress:(double)index / (double)(packages.count + 1)
                      status:[NSString stringWithFormat:@"正在安装 %@…", name]];
        int returnCode = [self spawnRoot:helperPath arguments:@[@"install", @"skip-uicache", path]];
        [results addObject:[NSString stringWithFormat:@"%@：helper 返回 %d", name, returnCode]];
        if (returnCode != 0 && returnCode != 184) {
            [self finishWithResults:results success:NO requiresRestart:NO];
            return;
        }
    }

    [self updateProgress:(double)packages.count / (double)(packages.count + 1) status:@"正在统一刷新 App 注册…"];
    int refreshReturnCode = [self spawnRoot:helperPath arguments:@[@"refresh"]];
    [results addObject:[NSString stringWithFormat:@"刷新 App 注册：helper 返回 %d", refreshReturnCode]];
    if (refreshReturnCode != 0) {
        [self finishWithResults:results success:NO requiresRestart:NO];
        return;
    }

    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"BatchMigration31V2Completed"];
    [self updateProgress:1.0 status:@"31 个应用已安装；未配置注入，也未修改淘宝。"];
    [self finishWithResults:results success:YES requiresRestart:NO];
}

- (NSString *)packageDirectoryPath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *packageDirectory = @"/var/mobile/Media/Downloads/巨魔应用文件夹";
    if ([fileManager fileExistsAtPath:[packageDirectory stringByAppendingPathComponent:@"manifest.tsv"]]) {
        return packageDirectory;
    }
    return nil;
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)packagesFromManifestAtPath:(NSString *)path error:(NSError **)error {
    NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:error];
    if (!contents) {
        return nil;
    }

    NSArray<NSString *> *lines = [contents componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *packages = [NSMutableArray new];
    NSCharacterSet *hexCharacters = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
    for (NSUInteger index = 1; index < lines.count; index++) {
        NSString *line = lines[index];
        if (line.length == 0) {
            continue;
        }
        NSArray<NSString *> *fields = [line componentsSeparatedByString:@"\t"];
        if (fields.count != 7) {
            return [self failManifest:error description:[NSString stringWithFormat:@"第 %lu 行字段数错误", (unsigned long)(index + 1)]];
        }

        NSString *bundleIdentifier = fields[0];
        NSString *name = fields[1].length > 0 ? fields[1] : bundleIdentifier;
        NSString *version = fields[2];
        NSString *sha256 = fields[5].lowercaseString;
        NSString *fileName = fields[6];
        BOOL validHash = sha256.length == CC_SHA256_DIGEST_LENGTH * 2
            && [[sha256 stringByTrimmingCharactersInSet:hexCharacters] length] == 0;
        BOOL validFileName = [fileName.pathExtension.lowercaseString isEqualToString:@"ipa"]
            && [fileName isEqualToString:fileName.lastPathComponent];
        if ([bundleIdentifier isEqualToString:@"com.opa334.Dopamine"] || !validHash || !validFileName) {
            return [self failManifest:error description:[NSString stringWithFormat:@"第 %lu 行包含禁止或非法项目", (unsigned long)(index + 1)]];
        }
        [packages addObject:@{
            @"name": [NSString stringWithFormat:@"%@ %@", name, version],
            @"file": fileName,
            @"sha256": sha256,
        }];
    }
    if (packages.count != 31) {
        return [self failManifest:error description:[NSString stringWithFormat:@"应为 31 项，实际为 %lu 项", (unsigned long)packages.count]];
    }
    return packages;
}

- (id)failManifest:(NSError **)error description:(NSString *)description {
    if (error) {
        *error = [NSError errorWithDomain:@"TrollStoreBatchMigrator" code:1 userInfo:@{NSLocalizedDescriptionKey: description}];
    }
    return nil;
}

- (NSString *)trollStoreHelperPath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *applicationRoot = @"/var/containers/Bundle/Application";
    NSArray<NSString *> *containerNames = [fileManager contentsOfDirectoryAtPath:applicationRoot error:nil];
    for (NSString *containerName in containerNames) {
        NSString *appPath = [[applicationRoot stringByAppendingPathComponent:containerName] stringByAppendingPathComponent:@"TrollStore.app"];
        NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
        if (![info[@"CFBundleIdentifier"] isEqualToString:@"com.opa334.TrollStore"]) {
            continue;
        }

        NSString *helperPath = [appPath stringByAppendingPathComponent:@"trollstorehelper"];
        BOOL isDirectory = NO;
        if ([fileManager fileExistsAtPath:helperPath isDirectory:&isDirectory] && !isDirectory) {
            return helperPath;
        }
    }
    return nil;
}

- (NSString *)sha256ForFileAtPath:(NSString *)path error:(NSError **)error {
    NSInputStream *stream = [NSInputStream inputStreamWithFileAtPath:path];
    [stream open];
    if (stream.streamStatus == NSStreamStatusError) {
        if (error) {
            *error = stream.streamError;
        }
        return nil;
    }

    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    uint8_t buffer[64 * 1024];
    NSInteger bytesRead = 0;
    while ((bytesRead = [stream read:buffer maxLength:sizeof(buffer)]) > 0) {
        CC_SHA256_Update(&context, buffer, (CC_LONG)bytesRead);
    }
    NSError *streamError = stream.streamError;
    [stream close];
    if (bytesRead < 0) {
        if (error) {
            *error = streamError;
        }
        return nil;
    }

    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
        [result appendFormat:@"%02x", digest[index]];
    }
    return result;
}

- (int)spawnRoot:(NSString *)path arguments:(NSArray<NSString *> *)arguments {
    NSMutableArray<NSString *> *allArguments = [NSMutableArray arrayWithObject:path];
    [allArguments addObjectsFromArray:arguments];
    char **argv = calloc(allArguments.count + 1, sizeof(char *));
    for (NSUInteger index = 0; index < allArguments.count; index++) {
        argv[index] = strdup(allArguments[index].UTF8String);
    }

    posix_spawnattr_t attributes;
    posix_spawnattr_init(&attributes);
    posix_spawnattr_set_persona_np(&attributes, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attributes, 0);
    posix_spawnattr_set_persona_gid_np(&attributes, 0);

    pid_t processIdentifier = 0;
    int spawnError = posix_spawn(&processIdentifier, path.fileSystemRepresentation, NULL, &attributes, argv, NULL);
    posix_spawnattr_destroy(&attributes);
    for (NSUInteger index = 0; index < allArguments.count; index++) {
        free(argv[index]);
    }
    free(argv);
    if (spawnError != 0) {
        return spawnError;
    }

    int waitStatus = 0;
    do {
        if (waitpid(processIdentifier, &waitStatus, 0) == -1) {
            return -222;
        }
    } while (!WIFEXITED(waitStatus) && !WIFSIGNALED(waitStatus));

    if (WIFSIGNALED(waitStatus)) {
        return 128 + WTERMSIG(waitStatus);
    }
    return WEXITSTATUS(waitStatus);
}

- (void)updateProgress:(double)progress status:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate batchInstaller:self didUpdateProgress:progress status:status];
    });
}

- (void)finishWithResults:(NSArray<NSString *> *)results success:(BOOL)success requiresRestart:(BOOL)requiresRestart {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.running = NO;
        [self.delegate batchInstaller:self didFinishWithResults:results success:success requiresRestart:requiresRestart];
    });
}

@end

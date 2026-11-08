#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>
#import <sqlite3.h>
#import <CommonCrypto/CommonDigest.h>

@interface PHAssetChangeRequest (AddedDate)
@property(nonatomic, strong) NSDate *addedDate;
@end

static NSString * const DatabasePath = @"/var/mobile/Media/PhotoData/Photos.sqlite";

static void Require(BOOL condition, NSString *message) {
    if (!condition) {
        @throw [NSException exceptionWithName:@"PhotosAlbumAddedDate" reason:message userInfo:nil];
    }
}

static NSString *TextColumn(sqlite3_stmt *statement, int column) {
    const unsigned char *text = sqlite3_column_text(statement, column);
    return text ? [NSString stringWithUTF8String:(const char *)text] : @"";
}

static NSArray<NSDictionary *> *ReadAlbum(NSString *albumUUID) {
    sqlite3 *database = NULL;
    Require(sqlite3_open_v2(DatabasePath.UTF8String, &database, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK,
            @"Cannot open Photos database read-only");
    sqlite3_busy_timeout(database, 5000);
    const char *query =
        "SELECT a.ZUUID,a.ZDATECREATED,a.ZADDEDDATE,a.ZDIRECTORY,a.ZFILENAME,a.ZKIND "
        "FROM ZGENERICALBUM g JOIN Z_28ASSETS m ON m.Z_28ALBUMS=g.Z_PK "
        "JOIN ZASSET a ON a.Z_PK=m.Z_3ASSETS "
        "WHERE g.ZUUID=? AND g.ZTRASHEDSTATE=0 AND a.ZTRASHEDSTATE=0 ORDER BY a.ZUUID";
    sqlite3_stmt *statement = NULL;
    Require(sqlite3_prepare_v2(database, query, -1, &statement, NULL) == SQLITE_OK, @"Unsupported Photos schema");
    sqlite3_bind_text(statement, 1, albumUUID.UTF8String, -1, SQLITE_TRANSIENT);
    NSMutableArray *items = [NSMutableArray array];
    int result = SQLITE_OK;
    while ((result = sqlite3_step(statement)) == SQLITE_ROW) {
        NSString *directory = TextColumn(statement, 3);
        NSString *filename = TextColumn(statement, 4);
        [items addObject:@{
            @"uuid": TextColumn(statement, 0),
            @"created": @(sqlite3_column_double(statement, 1)),
            @"added": @(sqlite3_column_double(statement, 2)),
            @"path": [[@"/var/mobile/Media" stringByAppendingPathComponent:directory]
                      stringByAppendingPathComponent:filename],
            @"filename": filename,
            @"kind": @(sqlite3_column_int(statement, 5))
        }];
    }
    Require(result == SQLITE_DONE, @"Could not finish reading album");
    sqlite3_finalize(statement);
    sqlite3_close(database);
    return items;
}

static NSArray<NSDictionary *> *ReadAssets(NSArray<NSString *> *identifiers) {
    Require(identifiers.count > 0 && identifiers.count <= 1000, @"Invalid asset scope");
    Require([NSSet setWithArray:identifiers].count == identifiers.count, @"Duplicate scoped UUID");
    sqlite3 *database = NULL;
    Require(sqlite3_open_v2(DatabasePath.UTF8String, &database, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK,
            @"Cannot open scoped Photos database read-only");
    sqlite3_busy_timeout(database, 5000);
    const char *query =
        "SELECT ZUUID,ZDATECREATED,ZADDEDDATE,ZDIRECTORY,ZFILENAME,ZKIND FROM ZASSET "
        "WHERE ZUUID=? AND ZTRASHEDSTATE=0 AND ZBUNDLESCOPE=0";
    sqlite3_stmt *statement = NULL;
    Require(sqlite3_prepare_v2(database, query, -1, &statement, NULL) == SQLITE_OK, @"Unsupported scoped Photos schema");
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *identifier in [identifiers sortedArrayUsingSelector:@selector(compare:)]) {
        Require([identifier isKindOfClass:NSString.class] && [[NSUUID alloc] initWithUUIDString:identifier] != nil,
                @"Invalid scoped asset UUID");
        sqlite3_reset(statement);
        sqlite3_clear_bindings(statement);
        sqlite3_bind_text(statement, 1, identifier.UTF8String, -1, SQLITE_TRANSIENT);
        Require(sqlite3_step(statement) == SQLITE_ROW, @"Scoped asset is absent or trashed");
        NSString *directory = TextColumn(statement, 3);
        NSString *filename = TextColumn(statement, 4);
        [items addObject:@{
            @"uuid": TextColumn(statement, 0),
            @"created": @(sqlite3_column_double(statement, 1)),
            @"added": @(sqlite3_column_double(statement, 2)),
            @"path": [[@"/var/mobile/Media" stringByAppendingPathComponent:directory] stringByAppendingPathComponent:filename],
            @"filename": filename,
            @"kind": @(sqlite3_column_int(statement, 5))
        }];
        Require(sqlite3_step(statement) == SQLITE_DONE, @"Scoped UUID is not unique");
    }
    sqlite3_finalize(statement);
    sqlite3_close(database);
    return items;
}

static NSArray<NSDictionary *> *ReadScope(NSDictionary *plan) {
    return plan[@"assetUUIDs"] ? ReadAssets(plan[@"assetUUIDs"]) : ReadAlbum(plan[@"albumUUID"]);
}

static NSString *FileHash(NSString *path) {
    FILE *file = fopen(path.fileSystemRepresentation, "rb");
    if (!file) return @"not-local";
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    unsigned char buffer[256 * 1024];
    size_t bytesRead = 0;
    while ((bytesRead = fread(buffer, 1, sizeof(buffer), file)) > 0) {
        CC_SHA256_Update(&context, buffer, (CC_LONG)bytesRead);
    }
    BOOL readFailed = ferror(file) != 0;
    fclose(file);
    Require(!readFailed, [@"Cannot hash " stringByAppendingString:path]);
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString *hash = [NSMutableString string];
    for (NSUInteger byteIndex = 0; byteIndex < sizeof(digest); byteIndex++) {
        [hash appendFormat:@"%02x", digest[byteIndex]];
    }
    return hash;
}

static void WriteJSON(id object, NSString *path) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:&error];
    Require(data != nil && [data writeToFile:path options:NSDataWritingAtomic error:&error],
            error.localizedDescription ?: @"Cannot write audit JSON");
}

static NSDictionary *LoadPlan(NSString *path) {
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&error];
    NSDictionary *plan = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
    Require([plan isKindOfClass:NSDictionary.class] && [plan[@"items"] isKindOfClass:NSArray.class],
            error.localizedDescription ?: @"Invalid plan");
    return plan;
}

static NSNumber *TargetAddedDate(NSDictionary *item) {
    NSNumber *target = item[@"targetAdded"] ?: item[@"created"];
    Require([target isKindOfClass:NSNumber.class] && isfinite(target.doubleValue), @"Invalid target added date");
    return target;
}

static NSNumber *TargetCreationDate(NSDictionary *item) {
    NSNumber *target = item[@"targetCreated"];
    Require([target isKindOfClass:NSNumber.class] && isfinite(target.doubleValue), @"Invalid target creation date");
    return target;
}

static PHFetchResult<PHAsset *> *FetchAssets(NSArray<NSString *> *identifiers) {
    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    options.includeAllBurstAssets = YES;
    return [PHAsset fetchAssetsWithLocalIdentifiers:identifiers options:options];
}

static void BackupDatabase(NSString *path) {
    Require(![[NSFileManager defaultManager] fileExistsAtPath:path], @"Backup already exists");
    sqlite3 *source = NULL;
    sqlite3 *destination = NULL;
    Require(sqlite3_open_v2(DatabasePath.UTF8String, &source, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK,
            @"Cannot open backup source");
    Require(sqlite3_open(path.UTF8String, &destination) == SQLITE_OK, @"Cannot create backup");
    sqlite3_busy_timeout(source, 5000);
    sqlite3_backup *backup = sqlite3_backup_init(destination, "main", source, "main");
    Require(backup != NULL, @"Cannot initialize consistent backup");
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:120];
    int result = SQLITE_OK;
    do {
        result = sqlite3_backup_step(backup, 1024);
        if (result == SQLITE_BUSY || result == SQLITE_LOCKED) [NSThread sleepForTimeInterval:0.05];
    } while ((result == SQLITE_OK || result == SQLITE_BUSY || result == SQLITE_LOCKED) &&
             deadline.timeIntervalSinceNow > 0);
    int finishResult = sqlite3_backup_finish(backup);
    sqlite3_close(destination);
    sqlite3_close(source);
    Require(result == SQLITE_DONE && finishResult == SQLITE_OK, @"Consistent backup failed");
}

static void PrepareScope(NSDictionary *scope, NSUInteger count, NSString *directory) {
    Require(count > 0 && count <= 1000, @"Invalid expected count");
    Require(![[NSFileManager defaultManager] fileExistsAtPath:directory], @"Audit directory already exists");
    NSError *error = nil;
    Require([[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES
            attributes:@{NSFilePosixPermissions: @0700} error:&error], error.localizedDescription);
    NSArray *before = ReadScope(scope);
    Require(before.count == count, @"Album count changed; refusing");
    BackupDatabase([directory stringByAppendingPathComponent:@"Photos.before.sqlite"]);
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *item in before) {
        NSMutableDictionary *withHash = item.mutableCopy;
        withHash[@"sha256"] = FileHash(item[@"path"]);
        [items addObject:withHash];
    }
    Require([before isEqual:ReadScope(scope)], @"Scope changed while preparing; refusing");
    NSMutableDictionary *plan = scope.mutableCopy;
    plan[@"expectedCount"] = @(count);
    plan[@"items"] = items;
    NSString *planPath = [directory stringByAppendingPathComponent:@"plan.json"];
    WriteJSON(plan, planPath);
    printf("PREPARED count=%lu plan=%s\n", (unsigned long)count, planPath.UTF8String);
}

static NSDictionary *Validate(NSDictionary *plan, BOOL verifyHashes, BOOL requireOriginal) {
    NSArray *current = ReadScope(plan);
    NSArray *items = plan[@"items"];
    Require(current.count == items.count && current.count == [plan[@"expectedCount"] unsignedIntegerValue],
            @"Album membership count changed");
    NSUInteger aligned = 0;
    NSUInteger unchanged = 0;
    NSUInteger localFiles = 0;
    for (NSUInteger itemIndex = 0; itemIndex < items.count; itemIndex++) {
        NSDictionary *before = items[itemIndex];
        NSDictionary *after = current[itemIndex];
        for (NSString *key in @[@"uuid", @"created", @"path", @"filename", @"kind"]) {
            Require([before[key] isEqual:after[key]], [@"Protected field changed: " stringByAppendingString:key]);
        }
        BOOL isAligned = [after[@"added"] isEqual:TargetAddedDate(before)];
        BOOL isOriginal = [after[@"added"] isEqual:before[@"added"]];
        Require(isAligned || isOriginal, @"Added date changed unexpectedly");
        if (requireOriginal) Require(isOriginal, @"Added date was already modified");
        aligned += isAligned;
        unchanged += !isAligned && isOriginal;
        if (verifyHashes) {
            Require([FileHash(before[@"path"]) isEqual:before[@"sha256"]], @"Original file hash changed");
            localFiles += ![before[@"sha256"] isEqual:@"not-local"];
        }
    }
    return @{@"count": @(items.count), @"aligned": @(aligned), @"remaining": @(unchanged),
             @"verifiedLocalFiles": @(localFiles)};
}

static NSDictionary *ValidateCreation(NSDictionary *plan, BOOL verifyHashes, BOOL requireOriginal) {
    NSArray *current = ReadScope(plan);
    NSArray *items = plan[@"items"];
    Require(current.count == items.count && current.count == [plan[@"expectedCount"] unsignedIntegerValue],
            @"Asset scope count changed");
    NSUInteger aligned = 0;
    NSUInteger unchanged = 0;
    NSUInteger localFiles = 0;
    for (NSUInteger itemIndex = 0; itemIndex < items.count; itemIndex++) {
        NSDictionary *before = items[itemIndex];
        NSDictionary *after = current[itemIndex];
        for (NSString *key in @[@"uuid", @"added", @"path", @"filename", @"kind"]) {
            Require([before[key] isEqual:after[key]], [@"Protected field changed: " stringByAppendingString:key]);
        }
        BOOL isAligned = [after[@"created"] isEqual:TargetCreationDate(before)];
        BOOL isOriginal = [after[@"created"] isEqual:before[@"created"]];
        Require(isAligned || isOriginal, @"Creation date changed unexpectedly");
        if (requireOriginal) Require(isOriginal, @"Creation date was already modified");
        aligned += isAligned;
        unchanged += !isAligned && isOriginal;
        if (verifyHashes) {
            Require([FileHash(before[@"path"]) isEqual:before[@"sha256"]], @"Original file hash changed");
            localFiles += ![before[@"sha256"] isEqual:@"not-local"];
        }
    }
    return @{@"count": @(items.count), @"aligned": @(aligned), @"remaining": @(unchanged),
             @"verifiedLocalFiles": @(localFiles)};
}

static void Change(NSString *planPath, NSUInteger limit, BOOL restore) {
    NSDictionary *plan = LoadPlan(planPath);
    Validate(plan, NO, NO);
    Require([PHAssetChangeRequest instancesRespondToSelector:@selector(setAddedDate:)],
            @"System does not support added-date changes");
    NSArray *current = ReadScope(plan);
    NSMutableArray *selected = [NSMutableArray array];
    NSMutableArray *identifiers = [NSMutableArray array];
    NSArray *items = plan[@"items"];
    for (NSUInteger itemIndex = 0; itemIndex < items.count && selected.count < limit; itemIndex++) {
        NSDictionary *item = items[itemIndex];
        NSNumber *target = restore ? item[@"added"] : TargetAddedDate(item);
        if ([current[itemIndex][@"added"] isEqual:target]) continue;
        [selected addObject:item];
        [identifiers addObject:[item[@"uuid"] stringByAppendingString:@"/L0/001"]];
    }
    Require(selected.count > 0, @"No changes needed");
    PHFetchResult<PHAsset *> *fetched = FetchAssets(identifiers);
    Require(fetched.count == selected.count, @"PhotoKit could not fetch every selected asset");
    NSMutableDictionary *assets = [NSMutableDictionary dictionary];
    for (PHAsset *asset in fetched) {
        assets[[asset.localIdentifier componentsSeparatedByString:@"/"].firstObject] = asset;
    }
    for (NSDictionary *item in selected) {
        PHAsset *asset = assets[item[@"uuid"]];
        Require(asset != nil && fabs(asset.creationDate.timeIntervalSinceReferenceDate - [item[@"created"] doubleValue]) < 0.001,
                @"PhotoKit creation date does not match plan");
    }
    NSError *error = nil;
    BOOL success = [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        for (NSDictionary *item in selected) {
            PHAssetChangeRequest *request = [PHAssetChangeRequest changeRequestForAsset:assets[item[@"uuid"]]];
            request.addedDate = [NSDate dateWithTimeIntervalSinceReferenceDate:
                                 [(restore ? item[@"added"] : TargetAddedDate(item)) doubleValue]];
        }
    } error:&error];
    Require(success, error.localizedDescription ?: @"PhotoKit rejected the change");
    NSDictionary *report = Validate(plan, NO, restore);
    NSDictionary *afterByUUID = [NSDictionary dictionaryWithObjects:ReadScope(plan)
                                  forKeys:[items valueForKey:@"uuid"]];
    for (NSDictionary *item in selected) {
        Require([afterByUUID[item[@"uuid"]][@"added"] isEqual:(restore ? item[@"added"] : TargetAddedDate(item))],
                @"PhotoKit reported success but the added date did not persist");
    }
    WriteJSON(report, [[planPath stringByDeletingLastPathComponent]
                      stringByAppendingPathComponent:restore ? @"restore.json" : @"change.json"]);
    printf("CHANGED count=%lu restore=%d report=%s\n", (unsigned long)selected.count, restore,
           [report description].UTF8String);
}

static void ChangeCreation(NSString *planPath, NSUInteger limit, BOOL restore) {
    NSDictionary *plan = LoadPlan(planPath);
    ValidateCreation(plan, NO, NO);
    NSArray *current = ReadScope(plan);
    NSMutableArray *selected = [NSMutableArray array];
    NSMutableArray *identifiers = [NSMutableArray array];
    NSArray *items = plan[@"items"];
    for (NSUInteger itemIndex = 0; itemIndex < items.count && selected.count < limit; itemIndex++) {
        NSDictionary *item = items[itemIndex];
        NSNumber *target = restore ? item[@"created"] : TargetCreationDate(item);
        if ([current[itemIndex][@"created"] isEqual:target]) continue;
        [selected addObject:item];
        [identifiers addObject:[item[@"uuid"] stringByAppendingString:@"/L0/001"]];
    }
    Require(selected.count > 0, @"No creation-date changes needed");
    PHFetchResult<PHAsset *> *fetched = FetchAssets(identifiers);
    Require(fetched.count == selected.count, @"PhotoKit could not fetch every selected asset");
    NSMutableDictionary *assets = [NSMutableDictionary dictionary];
    for (PHAsset *asset in fetched) {
        assets[[asset.localIdentifier componentsSeparatedByString:@"/"].firstObject] = asset;
    }
    for (NSDictionary *item in selected) {
        PHAsset *asset = assets[item[@"uuid"]];
        Require(asset != nil && fabs(asset.creationDate.timeIntervalSinceReferenceDate - [item[@"created"] doubleValue]) < 0.001,
                @"PhotoKit creation date does not match plan");
    }
    NSError *error = nil;
    BOOL success = [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        for (NSDictionary *item in selected) {
            PHAssetChangeRequest *request = [PHAssetChangeRequest changeRequestForAsset:assets[item[@"uuid"]]];
            request.creationDate = [NSDate dateWithTimeIntervalSinceReferenceDate:
                                    [(restore ? item[@"created"] : TargetCreationDate(item)) doubleValue]];
        }
    } error:&error];
    Require(success, error.localizedDescription ?: @"PhotoKit rejected the creation-date change");
    NSDictionary *report = ValidateCreation(plan, NO, restore);
    NSDictionary *afterByUUID = [NSDictionary dictionaryWithObjects:ReadScope(plan)
                                  forKeys:[items valueForKey:@"uuid"]];
    for (NSDictionary *item in selected) {
        Require([afterByUUID[item[@"uuid"]][@"created"]
                 isEqual:(restore ? item[@"created"] : TargetCreationDate(item))],
                @"PhotoKit reported success but the creation date did not persist");
    }
    WriteJSON(report, [[planPath stringByDeletingLastPathComponent]
                      stringByAppendingPathComponent:restore ? @"restore-created.json" : @"change-created.json"]);
    printf("CREATION_CHANGED count=%lu restore=%d report=%s\n", (unsigned long)selected.count, restore,
           [report description].UTF8String);
}

static void InspectClass(NSString *className) {
    Class inspectedClass = NSClassFromString(className);
    printf("CLASS %s\n", className.UTF8String);
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(inspectedClass, &methodCount);
    for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
        NSString *selectorName = NSStringFromSelector(method_getName(methods[methodIndex]));
        NSString *lowercaseName = selectorName.lowercaseString;
        if ([lowercaseName containsString:@"date"] || [lowercaseName containsString:@"sort"] ||
            [lowercaseName containsString:@"change"] || [lowercaseName containsString:@"added"]) {
            printf("%s %s\n", selectorName.UTF8String, method_getTypeEncoding(methods[methodIndex]));
        }
    }
    free(methods);
}

int main(int argumentCount, const char *arguments[]) {
    @autoreleasepool {
        @try {
        if (argumentCount == 2 && strcmp(arguments[1], "inspect") == 0) {
            InspectClass(@"PHAssetChangeRequest");
            InspectClass(@"PHAsset");
            InspectClass(@"PHAssetAddedDateProperties");
            return 0;
        }
        if (argumentCount == 5 && strcmp(arguments[1], "prepare") == 0) {
            PrepareScope(@{@"albumUUID": @(arguments[2])}, (NSUInteger)strtoul(arguments[3], NULL, 10), @(arguments[4]));
            return 0;
        }
        if (argumentCount == 5 && strcmp(arguments[1], "prepare-assets") == 0) {
            NSError *error = nil;
            NSData *data = [NSData dataWithContentsOfFile:@(arguments[2]) options:0 error:&error];
            NSArray *identifiers = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
            NSUInteger count = (NSUInteger)strtoul(arguments[3], NULL, 10);
            Require([identifiers isKindOfClass:NSArray.class] && identifiers.count == count,
                    error.localizedDescription ?: @"UUID manifest count mismatch");
            PrepareScope(@{@"assetUUIDs": identifiers}, count, @(arguments[4]));
            return 0;
        }
        if (argumentCount == 4 && strcmp(arguments[1], "apply") == 0) {
            Change(@(arguments[2]), (NSUInteger)strtoul(arguments[3], NULL, 10), NO);
            return 0;
        }
        if (argumentCount == 4 && strcmp(arguments[1], "apply-created") == 0) {
            ChangeCreation(@(arguments[2]), (NSUInteger)strtoul(arguments[3], NULL, 10), NO);
            return 0;
        }
        if (argumentCount == 3 && strcmp(arguments[1], "restore") == 0) {
            Change(@(arguments[2]), NSUIntegerMax, YES);
            return 0;
        }
        if (argumentCount == 3 && strcmp(arguments[1], "restore-created") == 0) {
            ChangeCreation(@(arguments[2]), NSUIntegerMax, YES);
            return 0;
        }
        if (argumentCount == 3 && strcmp(arguments[1], "verify") == 0) {
            NSDictionary *report = Validate(LoadPlan(@(arguments[2])), YES, NO);
            WriteJSON(report, [@(arguments[2]).stringByDeletingLastPathComponent
                              stringByAppendingPathComponent:@"verify.json"]);
            printf("VERIFIED %s\n", report.description.UTF8String);
            return 0;
        }
        if (argumentCount == 3 && strcmp(arguments[1], "verify-created") == 0) {
            NSDictionary *report = ValidateCreation(LoadPlan(@(arguments[2])), YES, NO);
            WriteJSON(report, [@(arguments[2]).stringByDeletingLastPathComponent
                              stringByAppendingPathComponent:@"verify-created.json"]);
            printf("CREATION_VERIFIED %s\n", report.description.UTF8String);
            return 0;
        }
        if (argumentCount == 3 && strcmp(arguments[1], "snapshot") == 0) {
            BackupDatabase(@(arguments[2]));
            printf("SNAPSHOT %s\n", arguments[2]);
            return 0;
        }
        fprintf(stderr, "Usage: PhotosAlbumAddedDate inspect | prepare UUID COUNT DIRECTORY | prepare-assets UUID_JSON COUNT DIRECTORY | apply PLAN LIMIT | verify PLAN | restore PLAN | apply-created PLAN LIMIT | verify-created PLAN | restore-created PLAN | snapshot PATH\n");
        return 1;
        } @catch (NSException *exception) {
            fprintf(stderr, "ERROR: %s\n", exception.reason.UTF8String);
            return 2;
        }
    }
}

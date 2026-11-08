#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>
#import <sqlite3.h>

static void Require(BOOL condition, NSString *message) {
    if (!condition) {
        @throw [NSException exceptionWithName:@"PhotosCR3Restore" reason:message userInfo:nil];
    }
}

static NSString *DatabasePath(void) {
    NSArray<NSString *> *paths = @[@"/rootfs/var/mobile/Media/PhotoData/Photos.sqlite",
                                  @"/var/mobile/Media/PhotoData/Photos.sqlite"];
    for (NSString *path in paths) {
        if ([[NSFileManager defaultManager] isReadableFileAtPath:path]) return path;
    }
    Require(NO, @"Cannot locate readable Photos index");
    return nil;
}

static void WriteJSON(id object, NSString *path) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:&error];
    Require(data != nil, error.localizedDescription ?: @"JSON serialization failed");
    if (path) {
        Require([data writeToFile:path options:NSDataWritingAtomic error:&error], error.localizedDescription);
    } else {
        fwrite(data.bytes, 1, data.length, stdout);
        printf("\n");
    }
}

static NSDictionary *LoadJSON(NSString *path) {
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&error];
    NSDictionary *value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
    Require([value isKindOfClass:NSDictionary.class], error.localizedDescription ?: @"Invalid JSON object");
    return value;
}

static NSString *FileHash(NSString *path) {
    FILE *source = fopen(path.fileSystemRepresentation, "rb");
    Require(source != NULL, @"Cannot open source file");
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    unsigned char buffer[256 * 1024];
    size_t count;
    while ((count = fread(buffer, 1, sizeof(buffer), source)) > 0) {
        CC_SHA256_Update(&context, buffer, (CC_LONG)count);
    }
    BOOL failed = ferror(source) != 0;
    fclose(source);
    Require(!failed, @"Source read failed");
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger index = 0; index < sizeof(digest); index++) {
        [result appendFormat:@"%02x", digest[index]];
    }
    return result;
}

static PHFetchResult<PHAsset *> *AllAssets(void) {
    PHFetchOptions *options = [PHFetchOptions new];
    options.includeHiddenAssets = YES;
    return [PHAsset fetchAssetsWithOptions:options];
}

static NSUInteger CR3Count(PHFetchResult<PHAsset *> *assets) {
    __block NSUInteger count = 0;
    [assets enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger index, BOOL *stop) {
        for (PHAssetResource *resource in [PHAssetResource assetResourcesForAsset:asset]) {
            if ([resource.originalFilename.pathExtension.lowercaseString isEqual:@"cr3"]) {
                count++;
                break;
            }
        }
    }];
    return count;
}

static void Snapshot(NSString *destination) {
    Require(![[NSFileManager defaultManager] fileExistsAtPath:destination], @"Snapshot already exists");
    sqlite3 *source = NULL;
    sqlite3 *backup = NULL;
    Require(sqlite3_open_v2(DatabasePath().UTF8String, &source, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK,
            @"Cannot open source index read-only");
    sqlite3_busy_timeout(source, 10000);
    Require(sqlite3_open_v2(destination.UTF8String, &backup, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL) == SQLITE_OK,
            @"Cannot create snapshot");
    sqlite3_backup *operation = sqlite3_backup_init(backup, "main", source, "main");
    Require(operation != NULL, @"Snapshot init failed");
    int result = SQLITE_OK;
    NSUInteger attempts = 0;
    do {
        result = sqlite3_backup_step(operation, 1024);
        if (result == SQLITE_BUSY || result == SQLITE_LOCKED) sqlite3_sleep(100);
        attempts++;
    } while ((result == SQLITE_OK || result == SQLITE_BUSY || result == SQLITE_LOCKED) && attempts < 500);
    int finished = sqlite3_backup_finish(operation);
    sqlite3_close(backup);
    sqlite3_close(source);
    Require(result == SQLITE_DONE && finished == SQLITE_OK, @"Snapshot did not complete");
    WriteJSON(@{@"snapshot": destination, @"sha256": FileHash(destination)}, nil);
}

static void VerifyAsset(NSDictionary *receipt, NSString *directory) {
    NSString *identifier = receipt[@"local_identifier"];
    PHFetchResult<PHAsset *> *fetched = [PHAsset fetchAssetsWithLocalIdentifiers:@[identifier] options:nil];
    Require(fetched.count == 1, @"Created asset is not available through PhotoKit");
    PHAsset *asset = fetched.firstObject;
    PHAssetResource *original = nil;
    for (PHAssetResource *resource in [PHAssetResource assetResourcesForAsset:asset]) {
        if ([resource.originalFilename.pathExtension.lowercaseString isEqual:@"cr3"]) original = resource;
    }
    Require(original != nil, @"Created asset has no CR3 original resource");
    NSString *exportPath = [directory stringByAppendingPathComponent:@"PhotoKit-original.CR3"];
    Require(![[NSFileManager defaultManager] fileExistsAtPath:exportPath], @"Verification export already exists");
    PHAssetResourceRequestOptions *options = [PHAssetResourceRequestOptions new];
    options.networkAccessAllowed = NO;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *resourceError = nil;
    [[PHAssetResourceManager defaultManager] writeDataForAssetResource:original
                                                              toFile:[NSURL fileURLWithPath:exportPath]
                                                             options:options
                                                   completionHandler:^(NSError *error) {
        resourceError = error;
        dispatch_semaphore_signal(semaphore);
    }];
    Require(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC)) == 0,
            @"Original readback timed out; do not retry import");
    Require(resourceError == nil, resourceError.localizedDescription ?: @"Original export failed");
    NSString *digest = FileHash(exportPath);
    Require([digest isEqual:receipt[@"source_sha256"]], @"PhotoKit original differs from source");
    double created = asset.creationDate.timeIntervalSinceReferenceDate;
    Require(fabs(created - [receipt[@"creation_date"] doubleValue]) < 0.01, @"Creation date did not persist");
    WriteJSON(@{@"local_identifier": identifier, @"sha256": digest, @"creation_date": @(created),
                @"width": @(asset.pixelWidth), @"height": @(asset.pixelHeight),
                @"resource_uti": original.uniformTypeIdentifier ?: @"",
                @"original_filename": original.originalFilename ?: @"",
                @"PhotoKit_original_verified": @YES, @"UI_verified": @NO},
              [directory stringByAppendingPathComponent:@"verified.json"]);
    WriteJSON(@{@"verified": @YES, @"local_identifier": identifier, @"sha256": digest}, nil);
}

static void ImportOne(NSString *planPath) {
    NSDictionary *plan = LoadJSON(planPath);
    NSString *sourcePath = plan[@"source_path"];
    NSString *directory = planPath.stringByDeletingLastPathComponent;
    NSString *receiptPath = [directory stringByAppendingPathComponent:@"receipt.json"];
    Require(![[NSFileManager defaultManager] fileExistsAtPath:receiptPath], @"Receipt exists; verify instead of importing again");
    Require([sourcePath.pathExtension.lowercaseString isEqual:@"cr3"] && [plan[@"sha256"] length] == 64,
            @"Expected CR3 plan with checksum");
    Require([FileHash(sourcePath) isEqual:plan[@"sha256"]], @"Staged file checksum mismatch");
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:sourcePath error:nil];
    Require([attributes[NSFileSize] unsignedLongLongValue] == [plan[@"bytes"] unsignedLongLongValue], @"Source size mismatch");
    PHFetchResult<PHAsset *> *before = AllAssets();
    Require(before.count == [plan[@"expected_photo_count"] unsignedIntegerValue], @"Library count changed; refresh plan");
    __block BOOL duplicate = NO;
    [before enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger index, BOOL *stop) {
        for (PHAssetResource *resource in [PHAssetResource assetResourcesForAsset:asset]) {
            if ([resource.originalFilename isEqual:plan[@"original_filename"]]) duplicate = YES;
        }
    }];
    Require(!duplicate, @"Original filename already exists; stop to avoid duplicate import");
    Require([PHAssetCreationRequest supportsAssetResourceTypes:@[@(PHAssetResourceTypePhoto)]], @"Photo resources unsupported");
    NSError *error = nil;
    __block NSString *identifier = nil;
    BOOL changed = [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
        PHAssetResourceCreationOptions *options = [PHAssetResourceCreationOptions new];
        options.originalFilename = plan[@"original_filename"];
        options.uniformTypeIdentifier = @"com.canon.cr3-raw-image";
        options.shouldMoveFile = NO;
        [request addResourceWithType:PHAssetResourceTypePhoto fileURL:[NSURL fileURLWithPath:sourcePath] options:options];
        request.creationDate = [NSDate dateWithTimeIntervalSinceReferenceDate:[plan[@"creation_date"] doubleValue]];
        if ([plan[@"latitude"] isKindOfClass:NSNumber.class] && [plan[@"longitude"] isKindOfClass:NSNumber.class]
            && fabs([plan[@"latitude"] doubleValue]) <= 90 && fabs([plan[@"longitude"] doubleValue]) <= 180) {
            request.location = [[CLLocation alloc] initWithLatitude:[plan[@"latitude"] doubleValue]
                                                        longitude:[plan[@"longitude"] doubleValue]];
        }
        identifier = request.placeholderForCreatedAsset.localIdentifier;
    } error:&error];
    if (!changed) {
        NSDictionary *failure = @{@"status": @"PhotoKit_import_failed", @"error_domain": error.domain ?: @"",
                                  @"error_code": @(error.code), @"error": error.localizedDescription ?: @"",
                                  @"details": error.userInfo.description ?: @""};
        WriteJSON(failure, [directory stringByAppendingPathComponent:@"failure.json"]);
        WriteJSON(failure, nil);
        Require(NO, @"PhotoKit refused original; no automatic conversion or retry");
    }
    Require(identifier.length > 0, @"No created identifier; inspect library before retrying");
    NSDictionary *receipt = @{@"status": @"PhotoKit_created", @"local_identifier": identifier,
                              @"source_sha256": plan[@"sha256"], @"source_path": sourcePath,
                              @"creation_date": plan[@"creation_date"], @"original_filename": plan[@"original_filename"]};
    WriteJSON(receipt, receiptPath);
    Require(AllAssets().count == before.count + 1, @"Unexpected library count after transaction; stop");
    VerifyAsset(receipt, directory);
}

static void PreviewAsset(NSString *receiptPath) {
    NSDictionary *receipt = LoadJSON(receiptPath);
    PHFetchResult<PHAsset *> *fetched = [PHAsset fetchAssetsWithLocalIdentifiers:@[receipt[@"local_identifier"]] options:nil];
    Require(fetched.count == 1, @"Cannot fetch sample for preview check");
    PHImageRequestOptions *options = [PHImageRequestOptions new];
    options.synchronous = YES;
    options.networkAccessAllowed = NO;
    options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    options.resizeMode = PHImageRequestOptionsResizeModeExact;
    __block UIImage *preview = nil;
    __block NSDictionary *information = nil;
    [[PHImageManager defaultManager] requestImageForAsset:fetched.firstObject
                                             targetSize:CGSizeMake(512, 512)
                                            contentMode:PHImageContentModeAspectFit
                                                options:options
                                          resultHandler:^(UIImage *result, NSDictionary *info) {
        preview = result;
        information = info;
    }];
    NSError *error = information[PHImageErrorKey];
    NSMutableDictionary *result = [@{@"local_identifier": receipt[@"local_identifier"],
                                      @"PhotoKit_preview_available": @(preview != nil), @"UI_verified": @NO,
                                      @"preview_error": error.localizedDescription ?: @""} mutableCopy];
    if (preview) {
        result[@"preview_width"] = @(preview.size.width);
        result[@"preview_height"] = @(preview.size.height);
        NSString *path = [receiptPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"preview.png"];
        Require([UIImagePNGRepresentation(preview) writeToFile:path atomically:YES], @"Could not save diagnostic preview");
    }
    WriteJSON(result, [receiptPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"preview-check.json"]);
    WriteJSON(result, nil);
}

static void VerifyBatch(NSString *receiptPath) {
    NSDictionary *receipt = LoadJSON(receiptPath);
    NSArray<NSDictionary *> *items = receipt[@"items"];
    Require(items.count > 0 && items.count <= 24, @"Invalid batch receipt");
    NSMutableArray *results = [NSMutableArray array];
    for (NSDictionary *item in items) {
        @autoreleasepool {
            PHFetchResult<PHAsset *> *fetched = [PHAsset fetchAssetsWithLocalIdentifiers:@[item[@"local_identifier"]] options:nil];
            Require(fetched.count == 1, @"Batch asset missing");
            PHAsset *asset = fetched.firstObject;
            PHAssetResource *original = nil;
            for (PHAssetResource *resource in [PHAssetResource assetResourcesForAsset:asset]) {
                if ([resource.originalFilename.pathExtension.lowercaseString isEqual:@"cr3"]) original = resource;
            }
            Require(original != nil, @"Batch asset has no CR3 original");
            Require([original.originalFilename isEqual:item[@"original_filename"]], @"Original filename changed");
            __block CC_SHA256_CTX context;
            CC_SHA256_Init(&context);
            __block unsigned long long length = 0;
            __block NSError *resourceError = nil;
            PHAssetResourceRequestOptions *options = [PHAssetResourceRequestOptions new];
            options.networkAccessAllowed = NO;
            dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
            [[PHAssetResourceManager defaultManager] requestDataForAssetResource:original options:options
                dataReceivedHandler:^(NSData *data) {
                    CC_SHA256_Update(&context, data.bytes, (CC_LONG)data.length);
                    length += data.length;
                } completionHandler:^(NSError *error) {
                    resourceError = error;
                    dispatch_semaphore_signal(semaphore);
                }];
            Require(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC)) == 0,
                    @"Batch readback timeout; verify receipt, never reimport");
            Require(resourceError == nil, resourceError.localizedDescription ?: @"Batch original readback failed");
            unsigned char digest[CC_SHA256_DIGEST_LENGTH];
            CC_SHA256_Final(digest, &context);
            NSMutableString *hash = [NSMutableString string];
            for (NSUInteger index = 0; index < sizeof(digest); index++) [hash appendFormat:@"%02x", digest[index]];
            Require([hash isEqual:item[@"sha256"]] && length == [item[@"bytes"] unsignedLongLongValue],
                    @"Batch original content differs");
            Require(fabs(asset.creationDate.timeIntervalSinceReferenceDate - [item[@"creation_date"] doubleValue]) < 0.01,
                    @"Batch creation date changed");
            Require(asset.pixelWidth == [item[@"expected_width"] unsignedIntegerValue]
                    && asset.pixelHeight == [item[@"expected_height"] unsignedIntegerValue], @"Batch original dimensions changed");
            if ([item[@"latitude"] isKindOfClass:NSNumber.class] && [item[@"longitude"] isKindOfClass:NSNumber.class]
                && fabs([item[@"latitude"] doubleValue]) <= 90 && fabs([item[@"longitude"] doubleValue]) <= 180) {
                Require(asset.location != nil && fabs(asset.location.coordinate.latitude - [item[@"latitude"] doubleValue]) < 0.000001
                        && fabs(asset.location.coordinate.longitude - [item[@"longitude"] doubleValue]) < 0.000001,
                        @"Batch original location changed");
            }
            [results addObject:@{@"local_identifier": item[@"local_identifier"], @"sha256": hash, @"bytes": @(length),
                                  @"original_filename": original.originalFilename, @"width": @(asset.pixelWidth),
                                  @"height": @(asset.pixelHeight), @"original_and_date_verified": @YES}];
        }
    }
    NSString *path = [receiptPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"batch-verified.json"];
    WriteJSON(@{@"verified_count": @(results.count), @"items": results}, path);
    WriteJSON(@{@"batch_verified": @YES, @"count": @(results.count)}, nil);
}

static NSSet<NSString *> *ExistingCR3Filenames(void) {
    sqlite3 *database = NULL;
    Require(sqlite3_open_v2(DatabasePath().UTF8String, &database, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK,
            @"Cannot read original filenames");
    sqlite3_busy_timeout(database, 10000);
    const char *query = "SELECT a.ZFILENAME,x.ZORIGINALFILENAME FROM ZASSET a "
        "LEFT JOIN ZADDITIONALASSETATTRIBUTES x ON x.Z_PK=a.ZADDITIONALATTRIBUTES "
        "WHERE a.ZTRASHEDSTATE=0 AND lower(a.ZFILENAME) LIKE '%.cr3'";
    sqlite3_stmt *statement = NULL;
    Require(sqlite3_prepare_v2(database, query, -1, &statement, NULL) == SQLITE_OK, @"Unsupported original filename schema");
    NSMutableSet *filenames = [NSMutableSet set];
    int result = SQLITE_OK;
    while ((result = sqlite3_step(statement)) == SQLITE_ROW) {
        for (int column = 0; column < 2; column++) {
            const unsigned char *text = sqlite3_column_text(statement, column);
            if (text) [filenames addObject:[NSString stringWithUTF8String:(const char *)text]];
        }
    }
    sqlite3_finalize(statement);
    sqlite3_close(database);
    Require(result == SQLITE_DONE, @"Original filename lookup incomplete");
    return filenames;
}

static void ImportBatch(NSString *planPath) {
    NSDictionary *plan = LoadJSON(planPath);
    NSArray<NSDictionary *> *items = plan[@"items"];
    Require([items isKindOfClass:NSArray.class] && items.count > 0 && items.count <= 24, @"Batch must contain 1 to 24 items");
    NSString *receiptPath = [planPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"batch-receipt.json"];
    Require(![[NSFileManager defaultManager] fileExistsAtPath:receiptPath], @"Batch receipt exists; verify, do not reimport");
    NSMutableSet *filenames = [NSMutableSet set];
    for (NSDictionary *item in items) {
        NSString *source = item[@"source_path"];
        Require([source.pathExtension.lowercaseString isEqual:@"cr3"] && [item[@"sha256"] length] == 64,
                @"Unexpected batch resource");
        Require(![filenames containsObject:item[@"original_filename"]], @"Duplicate batch filename");
        [filenames addObject:item[@"original_filename"]];
        Require([FileHash(source) isEqual:item[@"sha256"]], @"Batch staged checksum mismatch");
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:source error:nil];
        Require([attributes[NSFileSize] unsignedLongLongValue] == [item[@"bytes"] unsignedLongLongValue], @"Batch staged size mismatch");
    }
    PHFetchResult<PHAsset *> *before = AllAssets();
    Require(before.count == [plan[@"expected_photo_count"] unsignedIntegerValue], @"Library changed; refresh before batch");
    Require(![filenames intersectsSet:ExistingCR3Filenames()], @"Batch contains an existing original; stop to avoid duplicates");
    NSMutableArray *created = [NSMutableArray array];
    NSError *error = nil;
    BOOL success = [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        for (NSDictionary *item in items) {
            PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
            PHAssetResourceCreationOptions *options = [PHAssetResourceCreationOptions new];
            options.originalFilename = item[@"original_filename"];
            options.uniformTypeIdentifier = @"com.canon.cr3-raw-image";
            options.shouldMoveFile = NO;
            [request addResourceWithType:PHAssetResourceTypePhoto fileURL:[NSURL fileURLWithPath:item[@"source_path"]] options:options];
            request.creationDate = [NSDate dateWithTimeIntervalSinceReferenceDate:[item[@"creation_date"] doubleValue]];
            if ([item[@"latitude"] isKindOfClass:NSNumber.class] && [item[@"longitude"] isKindOfClass:NSNumber.class]
                && fabs([item[@"latitude"] doubleValue]) <= 90 && fabs([item[@"longitude"] doubleValue]) <= 180) {
                request.location = [[CLLocation alloc] initWithLatitude:[item[@"latitude"] doubleValue]
                                                             longitude:[item[@"longitude"] doubleValue]];
            }
            NSMutableDictionary *entry = [item mutableCopy];
            entry[@"local_identifier"] = request.placeholderForCreatedAsset.localIdentifier ?: @"";
            [created addObject:entry];
        }
    } error:&error];
    if (!success) {
        WriteJSON(@{@"status": @"batch_PhotoKit_failed", @"error_domain": error.domain ?: @"",
                    @"error_code": @(error.code), @"error": error.localizedDescription ?: @""},
                  [planPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"batch-failure.json"]);
        Require(NO, @"Batch transaction refused; no automatic retry");
    }
    WriteJSON(@{@"status": @"batch_PhotoKit_created", @"items": created}, receiptPath);
    Require(AllAssets().count == before.count + items.count, @"Unexpected library count after batch; stop");
    VerifyBatch(receiptPath);
}

int main(int argumentCount, const char *arguments[]) {
    @autoreleasepool {
        @try {
            if (argumentCount == 2 && strcmp(arguments[1], "inspect") == 0) {
                PHFetchResult<PHAsset *> *assets = AllAssets();
                WriteJSON(@{@"PhotoKit_count": @(assets.count), @"CR3_count": @(CR3Count(assets)),
                            @"Photos_authorization_status": @([PHPhotoLibrary authorizationStatus]),
                            @"database_path": DatabasePath()}, nil);
                return 0;
            }
            if (argumentCount == 3 && strcmp(arguments[1], "snapshot") == 0) {
                Snapshot(@(arguments[2]));
                return 0;
            }
            if (argumentCount == 3 && strcmp(arguments[1], "import-one") == 0) {
                ImportOne(@(arguments[2]));
                return 0;
            }
            if (argumentCount == 3 && strcmp(arguments[1], "verify") == 0) {
                NSString *path = @(arguments[2]);
                VerifyAsset(LoadJSON(path), path.stringByDeletingLastPathComponent);
                return 0;
            }
            if (argumentCount == 3 && strcmp(arguments[1], "preview") == 0) {
                PreviewAsset(@(arguments[2]));
                return 0;
            }
            if (argumentCount == 3 && strcmp(arguments[1], "import-batch") == 0) {
                ImportBatch(@(arguments[2]));
                return 0;
            }
            if (argumentCount == 3 && strcmp(arguments[1], "verify-batch") == 0) {
                VerifyBatch(@(arguments[2]));
                return 0;
            }
            fprintf(stderr, "Usage: PhotosCR3Restore inspect | snapshot NEW_PATH | import-one PLAN | verify RECEIPT | preview RECEIPT | import-batch PLAN | verify-batch RECEIPT\n");
            return 1;
        } @catch (NSException *exception) {
            fprintf(stderr, "ERROR: %s\n", exception.reason.UTF8String);
            return 2;
        }
    }
}

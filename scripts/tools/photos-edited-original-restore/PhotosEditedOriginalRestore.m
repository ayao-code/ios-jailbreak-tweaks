#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import <CoreLocation/CoreLocation.h>
#import <CommonCrypto/CommonDigest.h>
#import <sqlite3.h>

@interface PHAssetChangeRequest (AddedDate)
@property(nonatomic, strong) NSDate *addedDate;
@end

static NSString * const DatabasePath = @"/var/mobile/Media/PhotoData/Photos.sqlite";

static void Require(BOOL condition, NSString *message) {
    if (!condition) {
        @throw [NSException exceptionWithName:@"PhotosEditedOriginalRestore" reason:message userInfo:nil];
    }
}

static NSDictionary *LoadJSON(NSString *path) {
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&error];
    NSDictionary *value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
    Require([value isKindOfClass:NSDictionary.class], error.localizedDescription ?: @"Invalid JSON");
    return value;
}

static void WriteJSON(id value, NSString *path) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:&error];
    Require(data != nil && [data writeToFile:path options:NSDataWritingAtomic error:&error],
            error.localizedDescription ?: @"Cannot write JSON");
}

static NSString *FileHash(NSString *path) {
    FILE *file = fopen(path.fileSystemRepresentation, "rb");
    Require(file != NULL, [@"Cannot open " stringByAppendingString:path]);
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    unsigned char buffer[256 * 1024];
    size_t count = 0;
    while ((count = fread(buffer, 1, sizeof(buffer), file)) > 0) {
        CC_SHA256_Update(&context, buffer, (CC_LONG)count);
    }
    BOOL failed = ferror(file) != 0;
    fclose(file);
    Require(!failed, @"File read failed");
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger index = 0; index < sizeof(digest); index++) [result appendFormat:@"%02x", digest[index]];
    return result;
}

static void ValidateFile(NSDictionary *resource) {
    NSString *path = resource[@"sourcePath"];
    Require(path.length > 0 && [resource[@"sha256"] length] == 64, @"Invalid resource plan");
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    Require([attributes[NSFileSize] unsignedLongLongValue] == [resource[@"bytes"] unsignedLongLongValue],
            @"Resource size changed");
    Require([FileHash(path) isEqual:resource[@"sha256"]], @"Resource hash changed");
}

static PHAsset *FetchAsset(NSString *identifier) {
    NSString *localIdentifier = [identifier containsString:@"/"] ? identifier :
            [identifier stringByAppendingString:@"/L0/001"];
    PHFetchOptions *options = [PHFetchOptions new];
    options.includeHiddenAssets = YES;
    options.includeAllBurstAssets = YES;
    for (NSUInteger attempt = 0; attempt < 60; attempt++) {
        PHFetchResult<PHAsset *> *assets = [PHAsset fetchAssetsWithLocalIdentifiers:@[localIdentifier] options:options];
        if (assets.count == 1) return assets.firstObject;
        PHFetchResult<PHAsset *> *allAssets = [PHAsset fetchAssetsWithOptions:options];
        __block PHAsset *matchedAsset = nil;
        [allAssets enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger index, BOOL *stop) {
            NSString *assetUUID = [asset.localIdentifier componentsSeparatedByString:@"/"].firstObject;
            if ([assetUUID isEqual:identifier]) {
                matchedAsset = asset;
                *stop = YES;
            }
        }];
        if (matchedAsset != nil) return matchedAsset;
        [NSThread sleepForTimeInterval:0.5];
    }
    Require(NO, @"Asset is unavailable after waiting");
    return nil;
}

static PHAssetCollection *FetchAlbum(NSString *identifier) {
    PHFetchResult<PHAssetCollection *> *collections =
            [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:@[identifier] options:nil];
    Require(collections.count == 1, @"Album is unavailable");
    return collections.firstObject;
}

static NSDictionary *DatabaseAsset(NSString *identifier) {
    sqlite3 *database = NULL;
    Require(sqlite3_open_v2(DatabasePath.UTF8String, &database, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK,
            @"Cannot open Photos database read-only");
    sqlite3_busy_timeout(database, 5000);
    const char *query = "SELECT ZDATECREATED,ZADDEDDATE,ZHIDDEN,ZHASADJUSTMENTS,ZWIDTH,ZHEIGHT,ZLATITUDE,ZLONGITUDE,ZKIND,ZKINDSUBTYPE,ZDURATION FROM ZASSET WHERE ZUUID=? AND ZTRASHEDSTATE=0 AND ZBUNDLESCOPE=0";
    sqlite3_stmt *statement = NULL;
    Require(sqlite3_prepare_v2(database, query, -1, &statement, NULL) == SQLITE_OK, @"Unsupported Photos schema");
    sqlite3_bind_text(statement, 1, identifier.UTF8String, -1, SQLITE_TRANSIENT);
    Require(sqlite3_step(statement) == SQLITE_ROW, @"Created database asset is absent");
    NSDictionary *result = @{
        @"created": @(sqlite3_column_double(statement, 0)), @"added": @(sqlite3_column_double(statement, 1)),
        @"hidden": @(sqlite3_column_int(statement, 2)), @"hasAdjustments": @(sqlite3_column_int(statement, 3)),
        @"width": @(sqlite3_column_int(statement, 4)), @"height": @(sqlite3_column_int(statement, 5)),
        @"latitude": @(sqlite3_column_double(statement, 6)), @"longitude": @(sqlite3_column_double(statement, 7)),
        @"kind": @(sqlite3_column_int(statement, 8)), @"kindSubtype": @(sqlite3_column_int(statement, 9)),
        @"duration": @(sqlite3_column_double(statement, 10))
    };
    Require(sqlite3_step(statement) == SQLITE_DONE, @"Created UUID is not unique");
    sqlite3_finalize(statement);
    sqlite3_close(database);
    return result;
}

static void ExportResource(PHAssetResource *resource, NSString *path) {
    Require(![[NSFileManager defaultManager] fileExistsAtPath:path], @"Verification export already exists");
    PHAssetResourceRequestOptions *options = [PHAssetResourceRequestOptions new];
    options.networkAccessAllowed = NO;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *resourceError = nil;
    [[PHAssetResourceManager defaultManager] writeDataForAssetResource:resource
                                                              toFile:[NSURL fileURLWithPath:path]
                                                             options:options
                                                   completionHandler:^(NSError *error) {
        resourceError = error;
        dispatch_semaphore_signal(semaphore);
    }];
    Require(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 1800 * NSEC_PER_SEC)) == 0,
            @"Resource export timed out");
    Require(resourceError == nil, resourceError.localizedDescription ?: @"Resource export failed");
}

static BOOL AlbumContainsAsset(PHAssetCollection *album, NSString *identifier) {
    PHFetchResult<PHAsset *> *assets = [PHAsset fetchAssetsInAssetCollection:album options:nil];
    for (PHAsset *asset in assets) {
        NSString *assetUUID = [asset.localIdentifier componentsSeparatedByString:@"/"].firstObject;
        if ([assetUUID isEqual:identifier]) return YES;
    }
    return NO;
}

static void DeleteAsset(NSString *identifier) {
    PHAsset *asset = FetchAsset(identifier);
    NSError *error = nil;
    BOOL success = [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        [PHAssetChangeRequest deleteAssets:@[asset]];
    } error:&error];
    Require(success, error.localizedDescription ?: @"Rollback delete failed");
}

static void CreateAlbum(NSString *title, NSString *receiptPath) {
    Require(title.length > 0, @"Album title is empty");
    Require(![[NSFileManager defaultManager] fileExistsAtPath:receiptPath], @"Album receipt already exists");
    PHFetchOptions *options = [PHFetchOptions new];
    options.predicate = [NSPredicate predicateWithFormat:@"localizedTitle == %@", title];
    PHFetchResult<PHAssetCollection *> *existing =
            [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum
                                                     subtype:PHAssetCollectionSubtypeAlbumRegular
                                                     options:options];
    Require(existing.count == 0, @"Album title already exists");
    __block NSString *localIdentifier = nil;
    NSError *error = nil;
    BOOL success = [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        PHAssetCollectionChangeRequest *request =
                [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:title];
        localIdentifier = request.placeholderForCreatedAssetCollection.localIdentifier;
    } error:&error];
    Require(success && localIdentifier.length > 0, error.localizedDescription ?: @"Album creation failed");
    PHAssetCollection *album = FetchAlbum(localIdentifier);
    Require([album.localizedTitle isEqual:title], @"Created album title differs");
    WriteJSON(@{ @"status": @"created", @"title": title, @"localIdentifier": localIdentifier }, receiptPath);
}

static NSDictionary *Verify(NSDictionary *receipt, NSString *directory) {
    NSDictionary *plan = receipt[@"plan"];
    NSString *identifier = [receipt[@"localIdentifier"] componentsSeparatedByString:@"/"].firstObject;
    PHAsset *asset = FetchAsset(identifier);
    PHAssetCollection *album = FetchAlbum(plan[@"albumIdentifier"]);
    NSDictionary *databaseAsset = DatabaseAsset(identifier);
    Require(!asset.hidden && ![databaseAsset[@"hidden"] boolValue], @"Created asset is unexpectedly hidden");
    Require(![databaseAsset[@"hasAdjustments"] boolValue], @"Created original unexpectedly has adjustments");
    Require(AlbumContainsAsset(album, identifier), @"Created asset is absent from target album");
    Require(fabs(asset.creationDate.timeIntervalSinceReferenceDate - [plan[@"creationDate"] doubleValue]) < 0.001,
            @"Creation date differs");
    Require(fabs([databaseAsset[@"added"] doubleValue] - [plan[@"addedDate"] doubleValue]) < 0.001,
            @"Added date differs");
    Require([databaseAsset[@"kind"] integerValue] == [plan[@"kind"] integerValue] &&
            [databaseAsset[@"kindSubtype"] integerValue] == [plan[@"kindSubtype"] integerValue],
            @"Media kind differs");
    if ([plan[@"latitude"] doubleValue] >= -90 && [plan[@"longitude"] doubleValue] >= -180) {
        Require(asset.location != nil && fabs(asset.location.coordinate.latitude - [plan[@"latitude"] doubleValue]) < 0.000001 &&
                fabs(asset.location.coordinate.longitude - [plan[@"longitude"] doubleValue]) < 0.000001,
                @"Location differs");
    }
    NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:asset];
    NSMutableDictionary<NSNumber *, PHAssetResource *> *byType = [NSMutableDictionary dictionary];
    for (PHAssetResource *resource in resources) byType[@(resource.type)] = resource;
    NSDictionary *primary = plan[@"primary"];
    PHAssetResourceType primaryType = [plan[@"mediaKind"] isEqual:@"video"] ? PHAssetResourceTypeVideo : PHAssetResourceTypePhoto;
    PHAssetResource *primaryResource = byType[@(primaryType)];
    Require(primaryResource != nil && [primaryResource.originalFilename isEqual:primary[@"originalFilename"]],
            @"Primary resource is absent or renamed");
    NSString *primaryExport = [directory stringByAppendingPathComponent:[@"verify-primary-" stringByAppendingString:primary[@"originalFilename"]]];
    ExportResource(primaryResource, primaryExport);
    Require([FileHash(primaryExport) isEqual:primary[@"sha256"]], @"Primary resource bytes differ");
    NSMutableDictionary *result = [@{
        @"status": @"verified", @"uuid": identifier, @"primarySHA256": primary[@"sha256"],
        @"hidden": @NO, @"hasAdjustments": @NO, @"albumIdentifier": plan[@"albumIdentifier"],
        @"albumTitle": album.localizedTitle ?: @"", @"created": databaseAsset[@"created"],
        @"added": databaseAsset[@"added"], @"kind": databaseAsset[@"kind"],
        @"kindSubtype": databaseAsset[@"kindSubtype"], @"width": databaseAsset[@"width"],
        @"height": databaseAsset[@"height"], @"duration": databaseAsset[@"duration"]
    } mutableCopy];
    NSDictionary *paired = plan[@"pairedVideo"];
    if ([paired isKindOfClass:NSDictionary.class]) {
        Require((asset.mediaSubtypes & PHAssetMediaSubtypePhotoLive) != 0, @"Created asset is not a Live Photo");
        PHAssetResource *pairedResource = byType[@(PHAssetResourceTypePairedVideo)];
        Require(pairedResource != nil && [pairedResource.originalFilename isEqual:paired[@"originalFilename"]],
                @"Paired video is absent or renamed");
        NSString *pairedExport = [directory stringByAppendingPathComponent:[@"verify-paired-" stringByAppendingString:paired[@"originalFilename"]]];
        ExportResource(pairedResource, pairedExport);
        Require([FileHash(pairedExport) isEqual:paired[@"sha256"]], @"Paired video bytes differ");
        result[@"pairedVideoSHA256"] = paired[@"sha256"];
        result[@"livePhoto"] = @YES;
    } else {
        result[@"livePhoto"] = @NO;
    }
    WriteJSON(result, [directory stringByAppendingPathComponent:@"verify.json"]);
    return result;
}

static void ImportOne(NSString *planPath) {
    NSDictionary *plan = LoadJSON(planPath);
    NSString *directory = planPath.stringByDeletingLastPathComponent;
    NSString *receiptPath = [directory stringByAppendingPathComponent:@"receipt.json"];
    Require(![[NSFileManager defaultManager] fileExistsAtPath:receiptPath], @"Receipt already exists");
    PHAssetCollection *album = FetchAlbum(plan[@"albumIdentifier"]);
    ValidateFile(plan[@"primary"]);
    if ([plan[@"pairedVideo"] isKindOfClass:NSDictionary.class]) ValidateFile(plan[@"pairedVideo"]);
    __block NSString *localIdentifier = nil;
    NSError *error = nil;
    BOOL success = [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
        PHAssetResourceCreationOptions *primaryOptions = [PHAssetResourceCreationOptions new];
        primaryOptions.originalFilename = plan[@"primary"][@"originalFilename"];
        primaryOptions.shouldMoveFile = NO;
        PHAssetResourceType primaryType = [plan[@"mediaKind"] isEqual:@"video"] ? PHAssetResourceTypeVideo : PHAssetResourceTypePhoto;
        [request addResourceWithType:primaryType fileURL:[NSURL fileURLWithPath:plan[@"primary"][@"sourcePath"]] options:primaryOptions];
        NSDictionary *paired = plan[@"pairedVideo"];
        if ([paired isKindOfClass:NSDictionary.class]) {
            PHAssetResourceCreationOptions *pairedOptions = [PHAssetResourceCreationOptions new];
            pairedOptions.originalFilename = paired[@"originalFilename"];
            pairedOptions.shouldMoveFile = NO;
            [request addResourceWithType:PHAssetResourceTypePairedVideo fileURL:[NSURL fileURLWithPath:paired[@"sourcePath"]] options:pairedOptions];
        }
        request.creationDate = [NSDate dateWithTimeIntervalSinceReferenceDate:[plan[@"creationDate"] doubleValue]];
        request.hidden = NO;
        if ([plan[@"latitude"] doubleValue] >= -90 && [plan[@"longitude"] doubleValue] >= -180) {
            request.location = [[CLLocation alloc] initWithLatitude:[plan[@"latitude"] doubleValue]
                                                         longitude:[plan[@"longitude"] doubleValue]];
        }
        localIdentifier = request.placeholderForCreatedAsset.localIdentifier;
    } error:&error];
    Require(success && localIdentifier.length > 0, error.localizedDescription ?: @"PhotoKit import failed");
    NSString *identifier = [localIdentifier componentsSeparatedByString:@"/"].firstObject;
    PHAsset *asset = FetchAsset(identifier);
    error = nil;
    success = [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        PHAssetChangeRequest *assetRequest = [PHAssetChangeRequest changeRequestForAsset:asset];
        assetRequest.addedDate = [NSDate dateWithTimeIntervalSinceReferenceDate:[plan[@"addedDate"] doubleValue]];
        PHAssetCollectionChangeRequest *albumRequest = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:album];
        [albumRequest addAssets:@[asset]];
    } error:&error];
    if (!success) {
        DeleteAsset(identifier);
        Require(NO, error.localizedDescription ?: @"Metadata or album update failed and asset was rolled back");
    }
    NSDictionary *receipt = @{ @"status": @"created", @"localIdentifier": localIdentifier, @"plan": plan };
    WriteJSON(receipt, receiptPath);
    @try {
        NSDictionary *verified = Verify(receipt, directory);
        printf("IMPORTED_AND_VERIFIED %s\n", verified.description.UTF8String);
    } @catch (NSException *exception) {
        DeleteAsset(identifier);
        [[NSFileManager defaultManager] removeItemAtPath:receiptPath error:nil];
        @throw exception;
    }
}

static void FinishExisting(NSString *planPath, NSString *identifier) {
    NSDictionary *plan = LoadJSON(planPath);
    NSString *directory = planPath.stringByDeletingLastPathComponent;
    NSString *receiptPath = [directory stringByAppendingPathComponent:@"receipt.json"];
    Require(![[NSFileManager defaultManager] fileExistsAtPath:receiptPath], @"Receipt already exists");
    ValidateFile(plan[@"primary"]);
    if ([plan[@"pairedVideo"] isKindOfClass:NSDictionary.class]) ValidateFile(plan[@"pairedVideo"]);
    PHAsset *asset = FetchAsset(identifier);
    Require(fabs(asset.creationDate.timeIntervalSinceReferenceDate - [plan[@"creationDate"] doubleValue]) < 0.001,
            @"Existing asset creation date differs");
    PHAssetCollection *album = FetchAlbum(plan[@"albumIdentifier"]);
    NSError *error = nil;
    BOOL success = [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        PHAssetChangeRequest *assetRequest = [PHAssetChangeRequest changeRequestForAsset:asset];
        assetRequest.addedDate = [NSDate dateWithTimeIntervalSinceReferenceDate:[plan[@"addedDate"] doubleValue]];
        PHAssetCollectionChangeRequest *albumRequest = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:album];
        [albumRequest addAssets:@[asset]];
    } error:&error];
    if (!success) {
        DeleteAsset(identifier);
        Require(NO, error.localizedDescription ?: @"Existing asset completion failed and asset was rolled back");
    }
    NSString *localIdentifier = [identifier containsString:@"/"] ? identifier :
            [identifier stringByAppendingString:@"/L0/001"];
    NSDictionary *receipt = @{ @"status": @"recovered", @"localIdentifier": localIdentifier, @"plan": plan };
    WriteJSON(receipt, receiptPath);
    @try {
        NSDictionary *verified = Verify(receipt, directory);
        printf("RECOVERED_AND_VERIFIED %s\n", verified.description.UTF8String);
    } @catch (NSException *exception) {
        DeleteAsset(identifier);
        [[NSFileManager defaultManager] removeItemAtPath:receiptPath error:nil];
        @throw exception;
    }
}

int main(int argumentCount, const char *arguments[]) {
    @autoreleasepool {
        @try {
            if (argumentCount == 4 && strcmp(arguments[1], "create-album") == 0) {
                CreateAlbum(@(arguments[2]), @(arguments[3]));
                return 0;
            }
            if (argumentCount == 3 && strcmp(arguments[1], "import-one") == 0) {
                ImportOne(@(arguments[2]));
                return 0;
            }
            if (argumentCount == 3 && strcmp(arguments[1], "verify") == 0) {
                NSString *receiptPath = @(arguments[2]);
                Verify(LoadJSON(receiptPath), receiptPath.stringByDeletingLastPathComponent);
                return 0;
            }
            if (argumentCount == 4 && strcmp(arguments[1], "finish-existing") == 0) {
                FinishExisting(@(arguments[2]), @(arguments[3]));
                return 0;
            }
            fprintf(stderr, "Usage: PhotosEditedOriginalRestore create-album TITLE RECEIPT | import-one PLAN | finish-existing PLAN UUID | verify RECEIPT\n");
            return 1;
        } @catch (NSException *exception) {
            fprintf(stderr, "ERROR: %s\n", exception.reason.UTF8String);
            return 2;
        }
    }
}

#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import <CoreLocation/CoreLocation.h>
#import <CommonCrypto/CommonDigest.h>
#import <sqlite3.h>

@interface PHAssetChangeRequest (AddedDate)
@property(nonatomic, strong) NSDate *addedDate;
@end

static NSString *DatabasePath(void) {
    NSString *rootHidePath = @"/rootfs/var/mobile/Media/PhotoData/Photos.sqlite";
    return [[NSFileManager defaultManager] fileExistsAtPath:rootHidePath] ? rootHidePath :
        @"/var/mobile/Media/PhotoData/Photos.sqlite";
}

static void Require(BOOL condition, NSString *message) {
    if (!condition) {
        @throw [NSException exceptionWithName:@"PhotosCameraRollTransfer" reason:message userInfo:nil];
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
            (void)index;
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
    Require(sqlite3_open_v2(DatabasePath().UTF8String, &database, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK,
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

static NSDictionary *ResourceHash(PHAssetResource *resource) {
    PHAssetResourceRequestOptions *options = [PHAssetResourceRequestOptions new];
    options.networkAccessAllowed = NO;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *resourceError = nil;
    __block CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    __block unsigned long long bytes = 0;
    [[PHAssetResourceManager defaultManager] requestDataForAssetResource:resource options:options
        dataReceivedHandler:^(NSData *data) {
            @synchronized (resource) {
                CC_SHA256_Update(&context, data.bytes, (CC_LONG)data.length);
                bytes += data.length;
            }
        } completionHandler:^(NSError *error) {
            resourceError = error;
            dispatch_semaphore_signal(semaphore);
        }];
    Require(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 1800 * NSEC_PER_SEC)) == 0,
            @"Resource read timed out; do not import again, inspect receipt");
    Require(resourceError == nil, resourceError.localizedDescription ?: @"Resource read failed");
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString *hash = [NSMutableString string];
    for (NSUInteger index = 0; index < sizeof(digest); index++) [hash appendFormat:@"%02x", digest[index]];
    return @{ @"sha256": hash, @"bytes": @(bytes) };
}

static BOOL AlbumContainsAsset(PHAssetCollection *album, NSString *identifier) {
    PHFetchResult<PHAsset *> *assets = [PHAsset fetchAssetsInAssetCollection:album options:nil];
    for (PHAsset *asset in assets) {
        NSString *assetUUID = [asset.localIdentifier componentsSeparatedByString:@"/"].firstObject;
        if ([assetUUID isEqual:identifier]) return YES;
    }
    return NO;
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
    PHAssetCollection *album = [plan[@"albumIdentifier"] length] ? FetchAlbum(plan[@"albumIdentifier"]) : nil;
    NSDictionary *databaseAsset = DatabaseAsset(identifier);
    Require(!asset.hidden && ![databaseAsset[@"hidden"] boolValue], @"Created asset is unexpectedly hidden");
    BOOL slowMotion = [plan[@"kind"] integerValue] == 1 && [plan[@"kindSubtype"] integerValue] == 101;
    Require(![databaseAsset[@"hasAdjustments"] boolValue] || slowMotion, @"Created original unexpectedly has adjustments");
    if (album) Require(AlbumContainsAsset(album, identifier), @"Created asset is absent from target album");
    Require(fabs(asset.creationDate.timeIntervalSinceReferenceDate - [plan[@"creationDate"] doubleValue]) < 0.001,
            @"Creation date differs");
    Require(fabs([databaseAsset[@"added"] doubleValue] - [plan[@"addedDate"] doubleValue]) < 0.001,
            @"Added date differs");
    Require([databaseAsset[@"kind"] integerValue] == [plan[@"kind"] integerValue], @"Media kind differs");
    if (![plan[@"allowSystemDerivedSubtype"] boolValue]) {
        Require([databaseAsset[@"kindSubtype"] integerValue] == [plan[@"kindSubtype"] integerValue], @"Media subtype differs");
    }
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
    NSDictionary *primaryHash = ResourceHash(primaryResource);
    Require([primaryHash[@"sha256"] isEqual:primary[@"sha256"]] && [primaryHash[@"bytes"] unsignedLongLongValue] == [primary[@"bytes"] unsignedLongLongValue], @"Primary resource bytes differ");
    NSMutableDictionary *result = [@{
        @"status": @"verified", @"uuid": identifier, @"primarySHA256": primary[@"sha256"],
        @"hidden": @NO, @"hasAdjustments": databaseAsset[@"hasAdjustments"], @"albumIdentifier": plan[@"albumIdentifier"] ?: @"",
        @"albumTitle": album.localizedTitle ?: @"", @"created": databaseAsset[@"created"],
        @"added": databaseAsset[@"added"], @"kind": databaseAsset[@"kind"],
        @"kindSubtype": databaseAsset[@"kindSubtype"], @"width": databaseAsset[@"width"],
        @"height": databaseAsset[@"height"], @"duration": databaseAsset[@"duration"]
    } mutableCopy];
    result[@"sourceKindSubtype"] = plan[@"kindSubtype"];
    result[@"kindSubtypePreserved"] = @([databaseAsset[@"kindSubtype"] integerValue] == [plan[@"kindSubtype"] integerValue]);
    NSDictionary *paired = plan[@"pairedVideo"];
    if ([paired isKindOfClass:NSDictionary.class]) {
        Require((asset.mediaSubtypes & PHAssetMediaSubtypePhotoLive) != 0, @"Created asset is not a Live Photo");
        PHAssetResource *pairedResource = byType[@(PHAssetResourceTypePairedVideo)];
        Require(pairedResource != nil && [pairedResource.originalFilename isEqual:paired[@"originalFilename"]],
                @"Paired video is absent or renamed");
        NSDictionary *pairedHash = ResourceHash(pairedResource);
        Require([pairedHash[@"sha256"] isEqual:paired[@"sha256"]] && [pairedHash[@"bytes"] unsignedLongLongValue] == [paired[@"bytes"] unsignedLongLongValue], @"Paired video bytes differ");
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
    PHAssetCollection *album = [plan[@"albumIdentifier"] length] ? FetchAlbum(plan[@"albumIdentifier"]) : nil;
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
    NSDictionary *receipt = @{ @"status": @"created_pending_metadata", @"localIdentifier": localIdentifier, @"plan": plan };
    WriteJSON(receipt, receiptPath);
    PHAsset *asset = FetchAsset(identifier);
    error = nil;
    success = [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        PHAssetChangeRequest *assetRequest = [PHAssetChangeRequest changeRequestForAsset:asset];
        assetRequest.addedDate = [NSDate dateWithTimeIntervalSinceReferenceDate:[plan[@"addedDate"] doubleValue]];
        if (album) {
            PHAssetCollectionChangeRequest *albumRequest = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:album];
            [albumRequest addAssets:@[asset]];
        }
    } error:&error];
    if (!success) {
        Require(NO, error.localizedDescription ?: @"Metadata update failed; keep receipt and inspect existing asset");
    }
    receipt = @{ @"status": @"created", @"localIdentifier": localIdentifier, @"plan": plan };
    WriteJSON(receipt, receiptPath);
    @try {
        NSDictionary *verified = Verify(receipt, directory);
        printf("IMPORTED_AND_VERIFIED %s\n", verified.description.UTF8String);
    } @catch (NSException *exception) {
        @throw exception;
    }
}

static void FinishExisting(NSString *planPath, NSString *identifier) {
    NSDictionary *plan = LoadJSON(planPath);
    NSString *directory = planPath.stringByDeletingLastPathComponent;
    NSString *receiptPath = [directory stringByAppendingPathComponent:@"receipt.json"];
    Require([[NSFileManager defaultManager] fileExistsAtPath:receiptPath], @"Recovery requires the original creation receipt");
    NSDictionary *existingReceipt = LoadJSON(receiptPath);
    Require([[[existingReceipt[@"localIdentifier"] componentsSeparatedByString:@"/"] firstObject] isEqual:identifier], @"Receipt identifier differs");
    Require([existingReceipt[@"plan"] isEqual:plan], @"Recovery plan differs from creation receipt");
    ValidateFile(plan[@"primary"]);
    if ([plan[@"pairedVideo"] isKindOfClass:NSDictionary.class]) ValidateFile(plan[@"pairedVideo"]);
    PHAsset *asset = FetchAsset(identifier);
    Require(fabs(asset.creationDate.timeIntervalSinceReferenceDate - [plan[@"creationDate"] doubleValue]) < 0.001,
            @"Existing asset creation date differs");
    PHAssetCollection *album = [plan[@"albumIdentifier"] length] ? FetchAlbum(plan[@"albumIdentifier"]) : nil;
    NSError *error = nil;
    BOOL success = [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        PHAssetChangeRequest *assetRequest = [PHAssetChangeRequest changeRequestForAsset:asset];
        assetRequest.addedDate = [NSDate dateWithTimeIntervalSinceReferenceDate:[plan[@"addedDate"] doubleValue]];
        if (album) {
            PHAssetCollectionChangeRequest *albumRequest = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:album];
            [albumRequest addAssets:@[asset]];
        }
    } error:&error];
    if (!success) {
        Require(NO, error.localizedDescription ?: @"Existing asset completion failed; preserve receipt and asset");
    }
    NSString *localIdentifier = [identifier containsString:@"/"] ? identifier :
            [identifier stringByAppendingString:@"/L0/001"];
    NSDictionary *receipt = @{ @"status": @"recovered", @"localIdentifier": localIdentifier, @"plan": plan };
    WriteJSON(receipt, receiptPath);
    @try {
        NSDictionary *verified = Verify(receipt, directory);
        printf("RECOVERED_AND_VERIFIED %s\n", verified.description.UTF8String);
    } @catch (NSException *exception) {
        @throw exception;
    }
}

static NSUInteger PersonalAssetCount(void) {
    sqlite3 *database = NULL;
    Require(sqlite3_open_v2(DatabasePath().UTF8String, &database, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK,
            @"Cannot read active asset count");
    sqlite3_busy_timeout(database, 10000);
    sqlite3_stmt *statement = NULL;
    Require(sqlite3_prepare_v2(database, "SELECT count(*) FROM ZASSET WHERE ZTRASHEDSTATE=0 AND ZBUNDLESCOPE=0", -1, &statement, NULL) == SQLITE_OK,
            @"Cannot prepare asset count");
    Require(sqlite3_step(statement) == SQLITE_ROW, @"Cannot fetch asset count");
    NSUInteger count = (NSUInteger)sqlite3_column_int64(statement, 0);
    sqlite3_finalize(statement);
    sqlite3_close(database);
    return count;
}

static void VerifyBatch(NSString *receiptPath) {
    NSDictionary *receipt = LoadJSON(receiptPath);
    NSArray *entries = receipt[@"entries"];
    Require(entries.count > 0 && entries.count <= 24, @"Invalid batch receipt");
    NSMutableArray *verified = [NSMutableArray array];
    for (NSDictionary *entry in entries) {
        @autoreleasepool {
            NSString *directory = [receiptPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:entry[@"plan"][@"sourceUUID"]];
            Require([[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil], @"Cannot create verification directory");
            NSDictionary *result = Verify(entry, directory);
            [verified addObject:@{ @"sourceUUID": entry[@"plan"][@"sourceUUID"], @"sourceOrder": entry[@"plan"][@"sourceOrder"], @"verification": result }];
        }
    }
    WriteJSON(@{ @"status": @"verified", @"count": @(verified.count), @"entries": verified },
              [receiptPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"batch-verified.json"]);
    printf("BATCH_VERIFIED count=%lu\n", (unsigned long)verified.count);
    fflush(stdout);
}

static void FinishBatch(NSString *receiptPath) {
    NSDictionary *receipt = LoadJSON(receiptPath);
    NSArray *entries = receipt[@"entries"];
    Require(entries.count > 0 && entries.count <= 24, @"Invalid batch size");
    NSMutableArray<PHAsset *> *assets = [NSMutableArray array];
    for (NSDictionary *entry in entries) [assets addObject:FetchAsset(entry[@"localIdentifier"])];
    NSError *error = nil;
    BOOL success = [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        for (NSUInteger i = 0; i < entries.count; i++) {
            NSDictionary *plan = entries[i][@"plan"];
            PHAssetChangeRequest *request = [PHAssetChangeRequest changeRequestForAsset:assets[i]];
            request.addedDate = [NSDate dateWithTimeIntervalSinceReferenceDate:[plan[@"addedDate"] doubleValue]];
            request.creationDate = [NSDate dateWithTimeIntervalSinceReferenceDate:[plan[@"creationDate"] doubleValue]];
            if (plan[@"favorite"]) request.favorite = [plan[@"favorite"] boolValue];
            request.hidden = NO;
            if (fabs([plan[@"latitude"] doubleValue]) <= 90 && fabs([plan[@"longitude"] doubleValue]) <= 180) {
                request.location = [[CLLocation alloc] initWithLatitude:[plan[@"latitude"] doubleValue]
                                                             longitude:[plan[@"longitude"] doubleValue]];
            }
        }
    } error:&error];
    Require(success, error.localizedDescription ?: @"Batch metadata update failed; preserve receipt");
    NSMutableDictionary *landed = [receipt mutableCopy];
    landed[@"status"] = @"metadata_updated";
    WriteJSON(landed, receiptPath);
    VerifyBatch(receiptPath);
}

static void ImportBatch(NSString *planPath) {
    NSDictionary *batch = LoadJSON(planPath);
    NSArray<NSDictionary *> *items = batch[@"items"];
    Require([items isKindOfClass:NSArray.class] && items.count > 0 && items.count <= 24, @"Batch must contain 1 to 24 items");
    NSString *receiptPath = [planPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"batch-receipt.json"];
    Require(![[NSFileManager defaultManager] fileExistsAtPath:receiptPath], @"Receipt exists; finish/verify, never recreate");
    NSMutableSet *identifiers = [NSMutableSet set];
    for (NSDictionary *plan in items) {
        Require(![identifiers containsObject:plan[@"sourceUUID"]], @"Duplicate source asset in batch");
        [identifiers addObject:plan[@"sourceUUID"]];
        ValidateFile(plan[@"primary"]);
        if ([plan[@"pairedVideo"] isKindOfClass:NSDictionary.class]) ValidateFile(plan[@"pairedVideo"]);
    }
    NSUInteger before = PersonalAssetCount();
    Require(before == [batch[@"expectedAssetCount"] unsignedIntegerValue], @"Active library changed before batch; stop");
    NSMutableArray *entries = [NSMutableArray array];
    NSError *error = nil;
    BOOL success = [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        for (NSDictionary *plan in items) {
            PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
            PHAssetResourceCreationOptions *options = [PHAssetResourceCreationOptions new];
            options.originalFilename = plan[@"primary"][@"originalFilename"];
            if ([plan[@"primary"][@"uniformTypeIdentifier"] length]) options.uniformTypeIdentifier = plan[@"primary"][@"uniformTypeIdentifier"];
            options.shouldMoveFile = NO;
            PHAssetResourceType type = [plan[@"mediaKind"] isEqual:@"video"] ? PHAssetResourceTypeVideo : PHAssetResourceTypePhoto;
            [request addResourceWithType:type fileURL:[NSURL fileURLWithPath:plan[@"primary"][@"sourcePath"]] options:options];
            NSDictionary *paired = plan[@"pairedVideo"];
            if ([paired isKindOfClass:NSDictionary.class]) {
                PHAssetResourceCreationOptions *pairedOptions = [PHAssetResourceCreationOptions new];
                pairedOptions.originalFilename = paired[@"originalFilename"];
                pairedOptions.shouldMoveFile = NO;
                [request addResourceWithType:PHAssetResourceTypePairedVideo fileURL:[NSURL fileURLWithPath:paired[@"sourcePath"]] options:pairedOptions];
            }
            request.creationDate = [NSDate dateWithTimeIntervalSinceReferenceDate:[plan[@"creationDate"] doubleValue]];
            request.hidden = NO;
            if (plan[@"favorite"]) request.favorite = [plan[@"favorite"] boolValue];
            if (fabs([plan[@"latitude"] doubleValue]) <= 90 && fabs([plan[@"longitude"] doubleValue]) <= 180) {
                request.location = [[CLLocation alloc] initWithLatitude:[plan[@"latitude"] doubleValue] longitude:[plan[@"longitude"] doubleValue]];
            }
            [entries addObject:@{ @"localIdentifier": request.placeholderForCreatedAsset.localIdentifier ?: @"", @"plan": plan }];
        }
    } error:&error];
    if (!success) {
        WriteJSON(@{ @"status": @"failed", @"error": error.localizedDescription ?: @"PhotoKit failure", @"code": @(error.code) },
                  [planPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"batch-failure.json"]);
    }
    Require(success, error.localizedDescription ?: @"Batch creation failed; no retry");
    WriteJSON(@{ @"status": @"created_pending_metadata", @"entries": entries, @"expectedFinalCount": @(before + entries.count) }, receiptPath);
    // Receipt is durable before any observation or metadata update.
    for (NSDictionary *entry in entries) Require([entry[@"localIdentifier"] length] > 0, @"Missing created identity; inspect receipt");
    FinishBatch(receiptPath);
    Require(PersonalAssetCount() == before + entries.count, @"Unexpected final active count; preserve verified receipts");
}

int main(int argumentCount, const char *arguments[]) {
    @autoreleasepool {
        @try {
            if (argumentCount == 3 && strcmp(arguments[1], "import-batch") == 0) { ImportBatch(@(arguments[2])); return 0; }
            if (argumentCount == 3 && strcmp(arguments[1], "finish-batch") == 0) { FinishBatch(@(arguments[2])); return 0; }
            if (argumentCount == 3 && strcmp(arguments[1], "verify-batch") == 0) { VerifyBatch(@(arguments[2])); return 0; }
            if (argumentCount == 2 && strcmp(arguments[1], "inspect") == 0) {
                printf("addedDateSupported=%d photosAuthorization=%ld databasePath=%s\n", [PHAssetChangeRequest instancesRespondToSelector:@selector(setAddedDate:)], (long)[PHPhotoLibrary authorizationStatus], DatabasePath().UTF8String);
                return 0;
            }
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
            fprintf(stderr, "Usage: PhotosCameraRollTransfer create-album TITLE RECEIPT | import-one PLAN | finish-existing PLAN UUID | verify RECEIPT\n");
            return 1;
        } @catch (NSException *exception) {
            fprintf(stderr, "ERROR: %s\n", exception.reason.UTF8String);
            return 2;
        }
    }
}

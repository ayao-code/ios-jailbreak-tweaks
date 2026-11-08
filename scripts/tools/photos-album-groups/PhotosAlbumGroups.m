#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

static void Require(BOOL condition, NSString *message) {
    if (!condition) {
        @throw [NSException exceptionWithName:@"PhotosAlbumGroups" reason:message userInfo:nil];
    }
}

static NSDictionary *LoadJSON(NSString *path) {
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&error];
    NSDictionary *value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
    Require([value isKindOfClass:NSDictionary.class], error.localizedDescription ?: @"Invalid JSON plan");
    return value;
}

static void WriteJSON(id value, NSString *path) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:&error];
    Require(data != nil && [data writeToFile:path options:NSDataWritingAtomic error:&error],
            error.localizedDescription ?: @"Cannot write result JSON");
}

static NSArray<NSDictionary *> *ValidatedGroups(NSDictionary *plan) {
    NSArray *groups = plan[@"groups"];
    Require([groups isKindOfClass:NSArray.class] && groups.count > 0, @"Plan has no groups");
    NSMutableSet *titles = [NSMutableSet set];
    NSMutableSet *identifiers = [NSMutableSet set];
    for (NSDictionary *group in groups) {
        NSString *title = group[@"title"];
        NSArray *assetUUIDs = group[@"assetUUIDs"];
        Require([title isKindOfClass:NSString.class] && title.length > 0, @"Invalid album title");
        Require([assetUUIDs isKindOfClass:NSArray.class] && assetUUIDs.count > 0, @"Album has no assets");
        Require(![titles containsObject:title], @"Duplicate album title");
        [titles addObject:title];
        for (NSString *identifier in assetUUIDs) {
            Require([identifier isKindOfClass:NSString.class] && [[NSUUID alloc] initWithUUIDString:identifier] != nil,
                    @"Invalid asset UUID");
            Require(![identifiers containsObject:identifier], @"Duplicate asset UUID across groups");
            [identifiers addObject:identifier];
        }
    }
    return groups;
}

static PHAssetCollection *UniqueAlbumWithTitle(NSString *title) {
    PHFetchOptions *options = [PHFetchOptions new];
    options.predicate = [NSPredicate predicateWithFormat:@"localizedTitle == %@", title];
    PHFetchResult<PHAssetCollection *> *albums =
        [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum
                                                 subtype:PHAssetCollectionSubtypeAny
                                                 options:options];
    Require(albums.count <= 1, @"Album title is not unique");
    return albums.firstObject;
}

static NSDictionary<NSString *, PHAsset *> *FetchAssets(NSArray<NSDictionary *> *groups) {
    NSMutableArray *localIdentifiers = [NSMutableArray array];
    for (NSDictionary *group in groups) {
        for (NSString *identifier in group[@"assetUUIDs"]) {
            [localIdentifiers addObject:[identifier stringByAppendingString:@"/L0/001"]];
        }
    }
    PHFetchResult<PHAsset *> *fetched = [PHAsset fetchAssetsWithLocalIdentifiers:localIdentifiers options:nil];
    Require(fetched.count == localIdentifiers.count, @"PhotoKit could not fetch every planned asset");
    NSMutableDictionary *assets = [NSMutableDictionary dictionary];
    for (PHAsset *asset in fetched) {
        NSString *identifier = [asset.localIdentifier componentsSeparatedByString:@"/"].firstObject;
        assets[identifier] = asset;
    }
    Require(assets.count == localIdentifiers.count, @"Fetched asset identifiers are not unique");
    return assets;
}

static NSArray<PHAsset *> *OrderedAssets(NSArray<NSString *> *identifiers,
                                        NSDictionary<NSString *, PHAsset *> *assets) {
    NSMutableArray *ordered = [NSMutableArray array];
    for (NSString *identifier in identifiers) {
        PHAsset *asset = assets[identifier];
        Require(asset != nil, @"Planned asset disappeared");
        [ordered addObject:asset];
    }
    return ordered;
}

static void DeleteCollections(NSArray<PHAssetCollection *> *collections) {
    if (collections.count == 0) return;
    NSError *error = nil;
    BOOL success = [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        [PHAssetCollectionChangeRequest deleteAssetCollections:collections];
    } error:&error];
    Require(success, error.localizedDescription ?: @"Could not roll back created albums");
}

static NSDictionary *Verify(NSDictionary *plan) {
    NSArray<NSDictionary *> *groups = ValidatedGroups(plan);
    NSMutableArray *reports = [NSMutableArray array];
    for (NSDictionary *group in groups) {
        PHAssetCollection *album = UniqueAlbumWithTitle(group[@"title"]);
        Require(album != nil, @"Planned album is absent");
        PHFetchResult<PHAsset *> *members = [PHAsset fetchAssetsInAssetCollection:album options:nil];
        NSMutableSet *actual = [NSMutableSet set];
        for (PHAsset *asset in members) {
            [actual addObject:[asset.localIdentifier componentsSeparatedByString:@"/"].firstObject];
        }
        NSSet *expected = [NSSet setWithArray:group[@"assetUUIDs"]];
        Require(members.count == expected.count && [actual isEqual:expected], @"Album membership differs from plan");
        [reports addObject:@{@"title": group[@"title"], @"albumUUID": album.localIdentifier,
                             @"memberCount": @(members.count)}];
    }
    return @{@"status": @"verified", @"groupCount": @(reports.count), @"groups": reports};
}

static void Create(NSString *planPath, NSString *resultPath) {
    NSDictionary *plan = LoadJSON(planPath);
    NSArray<NSDictionary *> *groups = ValidatedGroups(plan);
    NSDictionary<NSString *, PHAsset *> *assets = FetchAssets(groups);
    for (NSDictionary *group in groups) {
        Require(UniqueAlbumWithTitle(group[@"title"]) == nil, @"Planned album title already exists");
    }
    NSMutableArray *createdIdentifiers = [NSMutableArray array];
    NSError *error = nil;
    BOOL created = [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        for (NSDictionary *group in groups) {
            PHAssetCollectionChangeRequest *request =
                [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:group[@"title"]];
            [createdIdentifiers addObject:request.placeholderForCreatedAssetCollection.localIdentifier];
        }
    } error:&error];
    Require(created && createdIdentifiers.count == groups.count,
            error.localizedDescription ?: @"Could not create planned albums");
    PHFetchResult<PHAssetCollection *> *createdAlbums =
        [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:createdIdentifiers options:nil];
    Require(createdAlbums.count == groups.count, @"Could not read back every created album");
    NSMutableDictionary *albumByIdentifier = [NSMutableDictionary dictionary];
    for (PHAssetCollection *album in createdAlbums) albumByIdentifier[album.localIdentifier] = album;
    NSMutableArray *orderedAlbums = [NSMutableArray array];
    for (NSString *identifier in createdIdentifiers) {
        PHAssetCollection *album = albumByIdentifier[identifier];
        Require(album != nil, @"Created album disappeared");
        [orderedAlbums addObject:album];
    }
    error = nil;
    BOOL added = [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        for (NSUInteger index = 0; index < groups.count; index++) {
            PHAssetCollectionChangeRequest *request =
                [PHAssetCollectionChangeRequest changeRequestForAssetCollection:orderedAlbums[index]];
            [request addAssets:OrderedAssets(groups[index][@"assetUUIDs"], assets)];
        }
    } error:&error];
    if (!added) {
        DeleteCollections(orderedAlbums);
        Require(NO, error.localizedDescription ?: @"Could not add assets to created albums");
    }
    NSDictionary *report = Verify(plan);
    WriteJSON(report, resultPath);
    printf("CREATED_AND_VERIFIED %s\n", report.description.UTF8String);
}

int main(int argumentCount, const char *arguments[]) {
    @autoreleasepool {
        @try {
            if (argumentCount == 4 && strcmp(arguments[1], "create") == 0) {
                Create(@(arguments[2]), @(arguments[3]));
                return 0;
            }
            if (argumentCount == 3 && strcmp(arguments[1], "verify") == 0) {
                NSDictionary *report = Verify(LoadJSON(@(arguments[2])));
                WriteJSON(report, [@(arguments[2]).stringByDeletingLastPathComponent
                                  stringByAppendingPathComponent:@"verify.json"]);
                printf("VERIFIED %s\n", report.description.UTF8String);
                return 0;
            }
            fprintf(stderr, "Usage: PhotosAlbumGroups create PLAN RESULT | verify PLAN\n");
            return 1;
        } @catch (NSException *exception) {
            fprintf(stderr, "ERROR: %s\n", exception.reason.UTF8String);
            return 2;
        }
    }
}

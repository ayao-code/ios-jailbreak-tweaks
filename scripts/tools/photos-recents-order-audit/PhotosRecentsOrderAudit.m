#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

static NSArray *Identifiers(PHFetchResult<PHAsset *> *assets) {
    NSMutableArray *identifiers = [NSMutableArray arrayWithCapacity:assets.count];
    [assets enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger index, BOOL *stop) {
        (void)index; (void)stop;
        [identifiers addObject:[asset.localIdentifier componentsSeparatedByString:@"/"].firstObject ?: @""];
    }];
    return identifiers;
}

int main(void) {
    @autoreleasepool {
        @try {
            NSMutableArray *results = [NSMutableArray array];
            for (NSNumber *subtype in @[@(PHAssetCollectionSubtypeSmartAlbumUserLibrary), @(PHAssetCollectionSubtypeSmartAlbumRecentlyAdded)]) {
                PHFetchResult<PHAssetCollection *> *collections = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:subtype.integerValue options:nil];
                for (PHAssetCollection *collection in collections) {
                    PHFetchOptions *options = [PHFetchOptions new];
                    NSArray *normal = Identifiers([PHAsset fetchAssetsInAssetCollection:collection options:options]);
                    options.includeAllBurstAssets = YES;
                    NSArray *allBurst = Identifiers([PHAsset fetchAssetsInAssetCollection:collection options:options]);
                    [results addObject:@{@"subtype": subtype, @"title": collection.localizedTitle ?: @"", @"defaultUUIDs": normal, @"includeAllBurstUUIDs": allBurst}];
                }
            }
            NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"authorization": @([PHPhotoLibrary authorizationStatus]), @"collections": results} options:NSJSONWritingPrettyPrinted error:nil];
            if (!data) return 2;
            fwrite(data.bytes, 1, data.length, stdout);
            printf("\n");
            return 0;
        } @catch (NSException *exception) {
            fprintf(stderr, "%s\n", exception.reason.UTF8String);
            return 2;
        }
    }
}

#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import <CommonCrypto/CommonDigest.h>

static void Require(BOOL condition, NSString *message) {
    if (!condition) {
        @throw [NSException exceptionWithName:@"PhotosResourceHash" reason:message userInfo:nil];
    }
}

static NSDictionary *LoadJSON(NSString *path) {
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&error];
    NSDictionary *value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
    Require([value isKindOfClass:NSDictionary.class], error.localizedDescription ?: @"Invalid JSON plan");
    return value;
}

static void WriteJSON(id value) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:&error];
    Require(data != nil, error.localizedDescription ?: @"Cannot serialize result");
    fwrite(data.bytes, 1, data.length, stdout);
    printf("\n");
}

static NSString *DigestString(unsigned char digest[CC_SHA256_DIGEST_LENGTH]) {
    NSMutableString *value = [NSMutableString string];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
        [value appendFormat:@"%02x", digest[index]];
    }
    return value;
}

static NSDictionary *HashResource(NSDictionary *item) {
    NSString *identifier = item[@"assetUUID"];
    NSString *resourceFilename = item[@"resourceFilename"];
    NSString *burstIdentifier = item[@"burstIdentifier"];
    NSNumber *creationDate = item[@"creationDate"];
    NSNumber *resourceType = item[@"resourceType"];
    Require((identifier.length > 0 || resourceFilename.length > 0 || creationDate != nil) && resourceType != nil,
            @"Invalid item");
    PHFetchOptions *fetchOptions = [PHFetchOptions new];
    fetchOptions.includeHiddenAssets = YES;
    fetchOptions.includeAllBurstAssets = YES;
    PHFetchResult<PHAsset *> *assets = burstIdentifier.length > 0 ?
            [PHAsset fetchAssetsWithBurstIdentifier:burstIdentifier options:fetchOptions] :
            [PHAsset fetchAssetsWithOptions:fetchOptions];
    __block PHAsset *selectedAsset = nil;
    __block PHAssetResource *selectedResource = nil;
    [assets enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger index, BOOL *stop) {
        NSString *assetUUID = [asset.localIdentifier componentsSeparatedByString:@"/"].firstObject;
        BOOL assetMatches = identifier.length == 0 || [assetUUID isEqual:identifier];
        if (creationDate != nil) {
            assetMatches = assetMatches && asset.creationDate != nil &&
                    fabs(asset.creationDate.timeIntervalSinceReferenceDate - creationDate.doubleValue) < 0.001;
        }
        if (!assetMatches) return;
        for (PHAssetResource *resource in [PHAssetResource assetResourcesForAsset:asset]) {
            BOOL typeMatches = resource.type == resourceType.integerValue;
            BOOL filenameMatches = resourceFilename.length == 0 || [resource.originalFilename isEqual:resourceFilename];
            if (typeMatches && filenameMatches) {
                Require(selectedResource == nil, @"Resource selector is not unique");
                selectedAsset = asset;
                selectedResource = resource;
            }
        }
    }];
    Require(selectedResource != nil, @"Resource not found");
    PHAssetResourceRequestOptions *requestOptions = [PHAssetResourceRequestOptions new];
    requestOptions.networkAccessAllowed = NO;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *resourceError = nil;
    __block unsigned long long byteCount = 0;
    __block CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    [[PHAssetResourceManager defaultManager] requestDataForAssetResource:selectedResource
                                                                 options:requestOptions
                                                     dataReceivedHandler:^(NSData *data) {
        CC_SHA256_Update(&context, data.bytes, (CC_LONG)data.length);
        byteCount += data.length;
    } completionHandler:^(NSError *error) {
        resourceError = error;
        dispatch_semaphore_signal(semaphore);
    }];
    Require(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 1800 * NSEC_PER_SEC)) == 0,
            @"Resource hash timed out");
    Require(resourceError == nil, resourceError.localizedDescription ?: @"Resource read failed");
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    return @{
        @"assetUUID": [selectedAsset.localIdentifier componentsSeparatedByString:@"/"].firstObject,
        @"localIdentifier": selectedAsset.localIdentifier,
        @"resourceType": resourceType,
        @"originalFilename": selectedResource.originalFilename ?: @"",
        @"bytes": @(byteCount),
        @"sha256": DigestString(digest)
    };
}

static void ListDate(NSTimeInterval center, NSTimeInterval tolerance) {
    PHFetchOptions *options = [PHFetchOptions new];
    options.includeHiddenAssets = YES;
    options.includeAllBurstAssets = YES;
    PHFetchResult<PHAsset *> *assets = [PHAsset fetchAssetsWithOptions:options];
    NSMutableArray *results = [NSMutableArray array];
    [assets enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger index, BOOL *stop) {
        if (asset.creationDate == nil || fabs(asset.creationDate.timeIntervalSinceReferenceDate - center) > tolerance) return;
        NSMutableArray *resources = [NSMutableArray array];
        for (PHAssetResource *resource in [PHAssetResource assetResourcesForAsset:asset]) {
            [resources addObject:@{ @"type": @(resource.type), @"originalFilename": resource.originalFilename ?: @"" }];
        }
        [results addObject:@{
            @"localIdentifier": asset.localIdentifier,
            @"creationDate": @(asset.creationDate.timeIntervalSinceReferenceDate),
            @"burstIdentifier": asset.burstIdentifier ?: @"",
            @"representsBurst": @(asset.representsBurst),
            @"resources": resources
        }];
    }];
    WriteJSON(@{ @"status": @"listed_read_only", @"results": results });
}

int main(int argumentCount, const char *arguments[]) {
    @autoreleasepool {
        @try {
            if (argumentCount == 4 && strcmp(arguments[1], "list-date") == 0) {
                ListDate(strtod(arguments[2], NULL), strtod(arguments[3], NULL));
                return 0;
            }
            if (argumentCount != 2) {
                fprintf(stderr, "Usage: PhotosResourceHash PLAN | list-date APPLE_TIME TOLERANCE\n");
                return 1;
            }
            NSDictionary *plan = LoadJSON(@(arguments[1]));
            NSArray *items = plan[@"items"];
            Require([items isKindOfClass:NSArray.class], @"Plan items are absent");
            NSMutableArray *results = [NSMutableArray arrayWithCapacity:items.count];
            for (NSDictionary *item in items) {
                [results addObject:HashResource(item)];
            }
            WriteJSON(@{ @"status": @"hashed_read_only", @"results": results });
            return 0;
        } @catch (NSException *exception) {
            fprintf(stderr, "ERROR: %s\n", exception.reason.UTF8String);
            return 2;
        }
    }
}

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <ImageIO/ImageIO.h>
#import <stdatomic.h>

static const NSUInteger CR3ScanLimit = 16 * 1024 * 1024;
static const NSInteger CR3SyntheticRequestBase = 700000;
static CFStringRef const CR3PrefsDomain = CFSTR("ayao.photosrecentssort");
static CFStringRef const CR3PrefsChangedNotification = CFSTR("ayao.photosrecentssort/preferences.changed");

typedef void (^CR3DataCompletion)(NSData *data, NSError *error);

@interface CR3JPEGScanner : NSObject

@property (nonatomic, readonly) NSData *bestData;
@property (nonatomic, readonly) NSUInteger bestPixels;

- (instancetype)initWithAsset:(PHAsset *)asset requiredLongEdge:(NSUInteger)requiredLongEdge requireFullSize:(BOOL)requireFullSize;
- (NSData *)appendChunk:(NSData *)chunk error:(NSError **)error;
- (NSData *)finishWithError:(NSError **)error;

@end

static dispatch_queue_t CR3StateQueue;
static NSCache<NSString *, NSData *> *CR3JPEGCache;
static NSMutableDictionary<NSString *, NSMutableArray<CR3DataCompletion> *> *CR3PendingLoads;
static NSMutableSet<NSNumber *> *CR3ActiveRequestIDs;
static atomic_int CR3NextRequestID = CR3SyntheticRequestBase;
static atomic_bool CR3PreviewEnabled = true;

static BOOL CR3ReadPreference(CFStringRef key, BOOL fallback) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(key, CR3PrefsDomain);
    if (!value) {
        return fallback;
    }
    BOOL result = fallback;
    if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
        result = CFBooleanGetValue((CFBooleanRef)value);
    }
    CFRelease(value);
    return result;
}

static void CR3LoadPreferences(void) {
    CFPreferencesAppSynchronize(CR3PrefsDomain);
    BOOL masterEnabled = CR3ReadPreference(CFSTR("enabled"), YES);
    BOOL previewEnabled = CR3ReadPreference(CFSTR("cr3PreviewEnabled"), YES);
    atomic_store(&CR3PreviewEnabled, masterEnabled && previewEnabled);
    if (!atomic_load(&CR3PreviewEnabled)) {
        [CR3JPEGCache removeAllObjects];
    }
}

static void CR3PreferencesChanged(__unused CFNotificationCenterRef center,
                                  __unused void *observer,
                                  __unused CFStringRef name,
                                  __unused const void *object,
                                  __unused CFDictionaryRef userInfo) {
    CR3LoadPreferences();
}

static NSError *CR3Error(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:@"ayao.cr3previewcompat"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

static NSString *CR3AssetUUID(PHAsset *asset) {
    return [asset.localIdentifier componentsSeparatedByString:@"/"].firstObject;
}

static BOOL CR3IsTargetAsset(PHAsset *asset) {
    @try {
        NSString *uniformTypeIdentifier = [asset valueForKey:@"uniformTypeIdentifier"];
        NSInteger thumbnailIndex = [[asset valueForKey:@"thumbnailIndex"] integerValue];
        return [uniformTypeIdentifier isEqualToString:@"com.canon.cr3-raw-image"] &&
               thumbnailIndex == NSIntegerMax;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

static NSInteger CR3AssetOrientation(PHAsset *asset) {
    @try {
        NSInteger orientation = [[asset valueForKey:@"orientation"] integerValue];
        return orientation >= 1 && orientation <= 8 ? orientation : 1;
    } @catch (__unused NSException *exception) {
        return 1;
    }
}

static UIImageOrientation CR3UIImageOrientation(PHAsset *asset) {
    switch (CR3AssetOrientation(asset)) {
        case 2: return UIImageOrientationUpMirrored;
        case 3: return UIImageOrientationDown;
        case 4: return UIImageOrientationDownMirrored;
        case 5: return UIImageOrientationLeftMirrored;
        case 6: return UIImageOrientationRight;
        case 7: return UIImageOrientationRightMirrored;
        case 8: return UIImageOrientationLeft;
        default: return UIImageOrientationUp;
    }
}

static PHAssetResource *CR3OriginalResource(PHAsset *asset) {
    for (PHAssetResource *resource in [PHAssetResource assetResourcesForAsset:asset]) {
        if ([resource.originalFilename.pathExtension.lowercaseString isEqualToString:@"cr3"]) {
            return resource;
        }
    }
    return nil;
}

static BOOL CR3IsJPEGStart(const uint8_t *bytes, NSUInteger length, NSUInteger offset) {
    return offset + 2 < length && bytes[offset] == 0xFF && bytes[offset + 1] == 0xD8 && bytes[offset + 2] == 0xFF;
}

@implementation CR3JPEGScanner {
    NSMutableData *_buffer;
    NSUInteger _scanOffset;
    NSUInteger _expectedWidth;
    NSUInteger _expectedHeight;
    NSUInteger _requiredLongEdge;
    BOOL _requireFullSize;
    NSData *_bestData;
    NSUInteger _bestPixels;
}

- (instancetype)initWithAsset:(PHAsset *)asset requiredLongEdge:(NSUInteger)requiredLongEdge requireFullSize:(BOOL)requireFullSize {
    self = [super init];
    if (self) {
        _buffer = [NSMutableData data];
        _expectedWidth = asset.pixelWidth;
        _expectedHeight = asset.pixelHeight;
        _requiredLongEdge = requiredLongEdge;
        _requireFullSize = requireFullSize;
    }
    return self;
}

- (NSData *)bestData {
    return _bestData;
}

- (NSUInteger)bestPixels {
    return _bestPixels;
}

- (BOOL)isFullSizeWidth:(NSUInteger)width height:(NSUInteger)height {
    return (width == _expectedWidth && height == _expectedHeight) ||
           (width == _expectedHeight && height == _expectedWidth);
}

- (NSData *)scanBufferedData {
    const uint8_t *bytes = (const uint8_t *)_buffer.bytes;
    NSUInteger length = _buffer.length;

    while (_scanOffset + 3 < length) {
        NSUInteger start = NSNotFound;
        for (NSUInteger offset = _scanOffset; offset + 3 < length; offset++) {
            if (CR3IsJPEGStart(bytes, length, offset)) {
                start = offset;
                break;
            }
        }
        if (start == NSNotFound) {
            _scanOffset = length > 2 ? length - 2 : 0;
            return nil;
        }

        NSUInteger end = NSNotFound;
        for (NSUInteger offset = start + 3; offset + 1 < length; offset++) {
            if (bytes[offset] == 0xFF && bytes[offset + 1] == 0xD9) {
                end = offset + 2;
                break;
            }
        }
        if (end == NSNotFound) {
            _scanOffset = start;
            return nil;
        }

        NSData *candidate = [_buffer subdataWithRange:NSMakeRange(start, end - start)];
        CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)candidate, NULL);
        NSDictionary *properties = source ? CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL)) : nil;
        if (source) {
            CFRelease(source);
        }

        NSUInteger width = [properties[(NSString *)kCGImagePropertyPixelWidth] unsignedIntegerValue];
        NSUInteger height = [properties[(NSString *)kCGImagePropertyPixelHeight] unsignedIntegerValue];
        if (width == 0 || height == 0) {
            _scanOffset = start + 3;
            continue;
        }

        NSUInteger pixels = width * height;
        if (pixels > _bestPixels) {
            _bestPixels = pixels;
            _bestData = candidate;
        }

        BOOL isFullSize = [self isFullSizeWidth:width height:height];
        BOOL isLargeEnough = MAX(width, height) >= _requiredLongEdge;
        if ((_requireFullSize && isFullSize) || (!_requireFullSize && isLargeEnough)) {
            return candidate;
        }

        _scanOffset = end;
    }
    return nil;
}

- (NSData *)appendChunk:(NSData *)chunk error:(NSError **)error {
    if (_buffer.length + chunk.length > CR3ScanLimit) {
        NSUInteger remaining = CR3ScanLimit - _buffer.length;
        if (remaining > 0) {
            [_buffer appendData:[chunk subdataWithRange:NSMakeRange(0, remaining)]];
        }
        NSData *result = [self scanBufferedData];
        if (!result && error) {
            *error = CR3Error(2, @"No suitable embedded JPEG found within scan limit");
        }
        return result;
    }

    [_buffer appendData:chunk];
    return [self scanBufferedData];
}

- (NSData *)finishWithError:(NSError **)error {
    NSData *result = [self scanBufferedData] ?: _bestData;
    if (!result && error) {
        *error = CR3Error(3, @"No decodable embedded JPEG found");
    }
    return result;
}

@end

static NSString *CR3CacheKey(PHAsset *asset, BOOL requireFullSize) {
    return [NSString stringWithFormat:@"%@:%@", CR3AssetUUID(asset), requireFullSize ? @"full" : @"preview"];
}

static void CR3FinishLoad(NSString *cacheKey, NSData *data, NSError *error) {
    dispatch_async(CR3StateQueue, ^{
        if (data.length > 0) {
            [CR3JPEGCache setObject:data forKey:cacheKey cost:data.length];
        }
        NSArray<CR3DataCompletion> *completions = [CR3PendingLoads[cacheKey] copy];
        [CR3PendingLoads removeObjectForKey:cacheKey];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            for (CR3DataCompletion completion in completions) {
                completion(data, error);
            }
        });
    });
}

static void CR3LoadEmbeddedJPEG(PHAsset *asset,
                                NSUInteger requiredLongEdge,
                                BOOL requireFullSize,
                                BOOL networkAccessAllowed,
                                CR3DataCompletion completion) {
    NSString *cacheKey = CR3CacheKey(asset, requireFullSize);
    dispatch_async(CR3StateQueue, ^{
        NSData *cachedData = [CR3JPEGCache objectForKey:cacheKey];
        if (cachedData) {
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                completion(cachedData, nil);
            });
            return;
        }

        NSMutableArray<CR3DataCompletion> *pendingCompletions = CR3PendingLoads[cacheKey];
        if (pendingCompletions) {
            [pendingCompletions addObject:[completion copy]];
            return;
        }
        CR3PendingLoads[cacheKey] = [NSMutableArray arrayWithObject:[completion copy]];

        PHAssetResource *resource = CR3OriginalResource(asset);
        if (!resource) {
            CR3FinishLoad(cacheKey, nil, CR3Error(1, @"CR3 original resource not found"));
            return;
        }

        PHAssetResourceRequestOptions *resourceOptions = [PHAssetResourceRequestOptions new];
        resourceOptions.networkAccessAllowed = networkAccessAllowed;
        CR3JPEGScanner *scanner = [[CR3JPEGScanner alloc] initWithAsset:asset
                                                      requiredLongEdge:requiredLongEdge
                                                       requireFullSize:requireFullSize];
        PHAssetResourceManager *resourceManager = [PHAssetResourceManager defaultManager];
        __block PHAssetResourceDataRequestID resourceRequestID = PHInvalidAssetResourceDataRequestID;
        __block BOOL finished = NO;

        resourceRequestID = [resourceManager
            requestDataForAssetResource:resource
                                options:resourceOptions
                    dataReceivedHandler:^(NSData *chunk) {
                        if (finished) {
                            return;
                        }
                        NSError *scanError;
                        NSData *result = [scanner appendChunk:chunk error:&scanError];
                        if (!result && !scanError) {
                            return;
                        }

                        finished = YES;
                        if (resourceRequestID != PHInvalidAssetResourceDataRequestID) {
                            [resourceManager cancelDataRequest:resourceRequestID];
                        }
                        CR3FinishLoad(cacheKey, result, scanError);
                    }
                      completionHandler:^(NSError *resourceError) {
                          if (finished) {
                              return;
                          }
                          finished = YES;
                          NSError *scanError;
                          NSData *result = [scanner finishWithError:&scanError];
                          CR3FinishLoad(cacheKey, result, result ? nil : (resourceError ?: scanError));
                      }];
    });
}

static PHImageRequestID CR3CreateRequestID(void) {
    PHImageRequestID requestID = atomic_fetch_add(&CR3NextRequestID, 1);
    @synchronized (CR3ActiveRequestIDs) {
        [CR3ActiveRequestIDs addObject:@(requestID)];
    }
    return requestID;
}

static BOOL CR3TakeActiveRequest(PHImageRequestID requestID) {
    @synchronized (CR3ActiveRequestIDs) {
        NSNumber *key = @(requestID);
        if (![CR3ActiveRequestIDs containsObject:key]) {
            return NO;
        }
        [CR3ActiveRequestIDs removeObject:key];
        return YES;
    }
}

static void CR3CancelRequest(PHImageRequestID requestID) {
    @synchronized (CR3ActiveRequestIDs) {
        [CR3ActiveRequestIDs removeObject:@(requestID)];
    }
}

static NSDictionary *CR3ResultInfo(PHImageRequestID requestID, NSError *error) {
    if (error) {
        return @{PHImageResultRequestIDKey: @(requestID), PHImageErrorKey: error, PHImageCancelledKey: @NO};
    }
    return @{PHImageResultRequestIDKey: @(requestID),
             PHImageResultIsDegradedKey: @NO,
             PHImageResultIsInCloudKey: @NO,
             PHImageCancelledKey: @NO};
}

static UIImage *CR3ImageForTargetSize(NSData *data, CGSize targetSize, UIImageOrientation orientation) {
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) {
        return nil;
    }

    CGFloat requestedPixels = MAX(targetSize.width, targetSize.height);
    if (!isfinite(requestedPixels) || requestedPixels <= 0.0) {
        requestedPixels = 6000.0;
    }
    requestedPixels = MIN(MAX(requestedPixels, 64.0), 6000.0);
    NSDictionary *thumbnailOptions = @{
        (NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (NSString *)kCGImageSourceThumbnailMaxPixelSize: @(ceil(requestedPixels)),
        (NSString *)kCGImageSourceShouldCacheImmediately: @YES
    };
    CGImageRef imageRef = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)thumbnailOptions);
    CFRelease(source);
    if (!imageRef) {
        return nil;
    }

    UIImage *image = [UIImage imageWithCGImage:imageRef scale:1.0 orientation:orientation];
    CGImageRelease(imageRef);
    return image;
}

static PHImageRequestID CR3RequestImage(PHAsset *asset,
                                        CGSize targetSize,
                                        PHImageRequestOptions *options,
                                        void (^resultHandler)(UIImage *result, NSDictionary *info)) {
    PHImageRequestID requestID = CR3CreateRequestID();
    CGFloat requestedPixels = MAX(targetSize.width, targetSize.height);
    BOOL requireFullSize = !isfinite(requestedPixels) || requestedPixels > 1620.0;
    NSUInteger requiredLongEdge = requireFullSize ? MAX(asset.pixelWidth, asset.pixelHeight) : 1620;
    UIImageOrientation orientation = CR3UIImageOrientation(asset);
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSData *resultData;
    __block NSError *resultError;
    CR3LoadEmbeddedJPEG(asset, requiredLongEdge, requireFullSize, options.isNetworkAccessAllowed, ^(NSData *data, NSError *error) {
        resultData = data;
        resultError = error;
        dispatch_semaphore_signal(semaphore);
    });
    long waitResult = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    if (waitResult != 0) {
        resultError = CR3Error(5, @"Embedded JPEG request timed out");
    }
    UIImage *image = resultData ? CR3ImageForTargetSize(resultData, targetSize, orientation) : nil;
    resultError = resultError ?: (image ? nil : CR3Error(4, @"Embedded JPEG decode failed"));
    if (CR3TakeActiveRequest(requestID) && resultHandler) {
        resultHandler(image, CR3ResultInfo(requestID, resultError));
    }
    return requestID;
}

%hook PHImageManager

- (PHImageRequestID)requestImageForAsset:(PHAsset *)asset
                              targetSize:(CGSize)targetSize
                             contentMode:(PHImageContentMode)contentMode
                                 options:(PHImageRequestOptions *)options
                           resultHandler:(void (^)(UIImage *result, NSDictionary *info))resultHandler {
    if (!atomic_load(&CR3PreviewEnabled) || !CR3IsTargetAsset(asset)) {
        return %orig;
    }
    return CR3RequestImage(asset, targetSize, options ?: [PHImageRequestOptions new], resultHandler);
}

- (void)cancelImageRequest:(PHImageRequestID)requestID {
    if (requestID >= CR3SyntheticRequestBase) {
        CR3CancelRequest(requestID);
        return;
    }
    %orig;
}

%end

%ctor {
    @autoreleasepool {
        CR3StateQueue = dispatch_queue_create("ayao.cr3previewcompat.state", DISPATCH_QUEUE_SERIAL);
        CR3JPEGCache = [NSCache new];
        CR3JPEGCache.countLimit = 16;
        CR3JPEGCache.totalCostLimit = 32 * 1024 * 1024;
        CR3PendingLoads = [NSMutableDictionary dictionary];
        CR3ActiveRequestIDs = [NSMutableSet set];
        CR3LoadPreferences();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        CR3PreferencesChanged,
                                        CR3PrefsChangedNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        %init;
    }
}

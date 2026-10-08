#import "CR3Processor.h"
#import <CoreGraphics/CoreGraphics.h>
#import <CoreLocation/CoreLocation.h>
#import <ImageIO/ImageIO.h>
#import <Photos/Photos.h>
#import <UIKit/UIKit.h>
#include "libraw/libraw.h"

static NSString * const CR3UTI = @"com.canon.cr3-raw-image";
static NSString * const GeneratedSuffix = @"_RAW_sRGB_Q100.jpg";

@interface CR3WorkItem : NSObject
@property(nonatomic, strong) PHAsset *asset;
@property(nonatomic, strong) PHAssetResource *resource;
@property(nonatomic, copy) NSString *filename;
@end

@implementation CR3WorkItem
@end

@interface CR3Processor ()
@property(nonatomic, strong) dispatch_queue_t workQueue;
@property(nonatomic, copy) NSArray<CR3WorkItem *> *pendingItems;
@property(nonatomic, assign, getter=isRunning) BOOL running;
@property(nonatomic, assign) BOOL pauseRequested;
@end

@implementation CR3Processor

- (instancetype)init {
    self = [super init];
    if (self) {
        _workQueue = dispatch_queue_create("com.ayao.cr3companion.processing", DISPATCH_QUEUE_SERIAL);
        _pendingItems = @[];
    }
    return self;
}

static NSString *AssetUUID(PHAsset *asset) {
    return [asset.localIdentifier componentsSeparatedByString:@"/"].firstObject;
}

static NSString *OutputFilename(PHAsset *asset, PHAssetResource *resource) {
    NSString *stem = [resource.originalFilename stringByDeletingPathExtension];
    NSString *uuidPrefix = [[AssetUUID(asset) substringToIndex:8] uppercaseString];
    return [NSString stringWithFormat:@"%@_%@%@", stem, uuidPrefix, GeneratedSuffix];
}

static NSString *LegacyOutputFilename(PHAssetResource *resource) {
    return [NSString stringWithFormat:@"%@%@", [resource.originalFilename stringByDeletingPathExtension], GeneratedSuffix];
}

static PHAssetResource *CR3Resource(PHAsset *asset) {
    for (PHAssetResource *resource in [PHAssetResource assetResourcesForAsset:asset]) {
        if ([resource.uniformTypeIdentifier isEqualToString:CR3UTI] ||
            [resource.originalFilename.pathExtension caseInsensitiveCompare:@"cr3"] == NSOrderedSame) {
            return resource;
        }
    }
    return nil;
}

static NSDictionary<NSString *, PHAsset *> *AssetsByOriginalFilename(void) {
    NSMutableDictionary<NSString *, PHAsset *> *result = [NSMutableDictionary dictionary];
    PHFetchResult<PHAsset *> *assets = [PHAsset fetchAssetsWithOptions:nil];
    [assets enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger index, BOOL *stop) {
        for (PHAssetResource *resource in [PHAssetResource assetResourcesForAsset:asset]) {
            if (resource.originalFilename.length != 0 && !result[resource.originalFilename]) {
                result[resource.originalFilename] = asset;
            }
        }
    }];
    return result;
}

- (void)scan {
    if (self.isRunning) {
        return;
    }
    [self.delegate processor:self didUpdateProgress:0 status:@"正在扫描图库…"];
    dispatch_async(self.workQueue, ^{
        NSDictionary<NSString *, PHAsset *> *existing = AssetsByOriginalFilename();
        NSMutableArray<CR3WorkItem *> *pending = [NSMutableArray array];
        __block NSUInteger total = 0;
        __block NSUInteger processed = 0;
        PHFetchOptions *options = [PHFetchOptions new];
        options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:YES]];
        PHFetchResult<PHAsset *> *assets = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:options];
        [assets enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger index, BOOL *stop) {
            PHAssetResource *resource = CR3Resource(asset);
            if (!resource) {
                return;
            }
            total++;
            NSString *filename = OutputFilename(asset, resource);
            if (existing[filename] || existing[LegacyOutputFilename(resource)]) {
                processed++;
                return;
            }
            CR3WorkItem *item = [CR3WorkItem new];
            item.asset = asset;
            item.resource = resource;
            item.filename = filename;
            [pending addObject:item];
        }];
        self.pendingItems = pending;
        double estimatedGiB = pending.count * 22.07 / 1024.0;
        NSString *summary = [NSString stringWithFormat:@"CR3 总数：%lu\n已处理：%lu\n待处理：%lu\n预计新增：约 %.2f GiB",
                             (unsigned long)total,
                             (unsigned long)processed,
                             (unsigned long)pending.count,
                             estimatedGiB];
        [self.delegate processor:self didUpdateSummary:summary canStart:pending.count != 0];
        [self.delegate processor:self didUpdateProgress:0 status:pending.count == 0 ? @"没有新的 CR3。" : @"扫描完成，可开始处理。"];
    });
}

- (void)start {
    if (self.isRunning || self.pendingItems.count == 0) {
        return;
    }
    self.running = YES;
    self.pauseRequested = NO;
    UIApplication.sharedApplication.idleTimerDisabled = YES;
    NSArray<CR3WorkItem *> *items = self.pendingItems;
    dispatch_async(self.workQueue, ^{
        NSUInteger completed = 0;
        NSUInteger failed = 0;
        for (CR3WorkItem *item in items) {
            if (self.pauseRequested) {
                break;
            }
            NSString *status = [NSString stringWithFormat:@"正在处理 %lu/%lu：%@",
                                (unsigned long)(completed + failed + 1),
                                (unsigned long)items.count,
                                item.resource.originalFilename];
            [self.delegate processor:self didUpdateProgress:(double)(completed + failed) / items.count status:status];
            NSError *error;
            if ([self processItem:item verifyOnly:NO error:&error]) {
                completed++;
            } else {
                failed++;
                [self.delegate processor:self didUpdateProgress:(double)(completed + failed) / items.count
                                                           status:[NSString stringWithFormat:@"%@ 失败：%@", item.resource.originalFilename, error.localizedDescription]];
            }
        }
        self.running = NO;
        NSString *message;
        if (self.pauseRequested) {
            message = [NSString stringWithFormat:@"已暂停。完成 %lu 张，失败 %lu 张；重新扫描后可继续。",
                       (unsigned long)completed, (unsigned long)failed];
        } else {
            message = [NSString stringWithFormat:@"处理完成：成功 %lu 张，失败 %lu 张。",
                       (unsigned long)completed, (unsigned long)failed];
        }
        [self.delegate processor:self didUpdateProgress:1 status:message];
        [self.delegate processor:self didFinishWithMessage:message];
    });
}

- (void)pause {
    self.pauseRequested = YES;
}

- (void)verifyDecoder {
    if (self.isRunning) {
        return;
    }
    self.running = YES;
    UIApplication.sharedApplication.idleTimerDisabled = YES;
    dispatch_async(self.workQueue, ^{
        __block CR3WorkItem *item;
        PHFetchResult<PHAsset *> *assets = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:nil];
        [assets enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger index, BOOL *stop) {
            PHAssetResource *resource = CR3Resource(asset);
            if (resource) {
                item = [CR3WorkItem new];
                item.asset = asset;
                item.resource = resource;
                item.filename = OutputFilename(asset, resource);
                *stop = YES;
            }
        }];
        NSError *error;
        BOOL success = item && [self processItem:item verifyOnly:YES error:&error];
        self.running = NO;
        NSString *message = success ? @"本机 LibRaw 解码验证通过，未向图库新增照片。" :
                                     [NSString stringWithFormat:@"解码验证失败：%@", error.localizedDescription ?: @"没有找到 CR3"];
        [self.delegate processor:self didFinishWithMessage:message];
    });
}

static BOOL WaitForResource(PHAssetResource *resource, NSURL *destinationURL, NSError **error) {
    [[NSFileManager defaultManager] removeItemAtURL:destinationURL error:nil];
    [[NSFileManager defaultManager] createFileAtPath:destinationURL.path contents:nil attributes:nil];
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingToURL:destinationURL error:error];
    if (!fileHandle) {
        return NO;
    }
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *requestError;
    PHAssetResourceRequestOptions *options = [PHAssetResourceRequestOptions new];
    options.networkAccessAllowed = YES;
    [[PHAssetResourceManager defaultManager] requestDataForAssetResource:resource
                                                                 options:options
                                                      dataReceivedHandler:^(NSData *data) {
        @try {
            [fileHandle writeData:data];
        } @catch (NSException *exception) {
            requestError = [NSError errorWithDomain:@"CR3Companion" code:11 userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"写入 CR3 临时文件失败"}];
        }
    } completionHandler:^(NSError *completionError) {
        requestError = requestError ?: completionError;
        [fileHandle closeFile];
        dispatch_semaphore_signal(semaphore);
    }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    if (requestError && error) {
        *error = requestError;
    }
    return requestError == nil;
}

static NSDictionary *ImageProperties(NSURL *sourceURL) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)sourceURL, NULL);
    if (!source) {
        return @{};
    }
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    CFRelease(source);
    return properties ?: @{};
}

static BOOL DecodeCR3ToJPEG(NSURL *sourceURL, NSURL *destinationURL, NSError **error) {
    LibRaw raw;
    raw.imgdata.params.use_camera_wb = 1;
    raw.imgdata.params.use_auto_wb = 0;
    raw.imgdata.params.output_color = 1;
    raw.imgdata.params.output_bps = 8;
    raw.imgdata.params.user_qual = 3;
    raw.imgdata.params.no_auto_bright = 0;
    int result = raw.open_file(sourceURL.fileSystemRepresentation);
    if (result != LIBRAW_SUCCESS) {
        if (error) {
            *error = [NSError errorWithDomain:@"CR3Companion" code:20 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:libraw_strerror(result)]}];
        }
        return NO;
    }
    result = raw.unpack();
    if (result == LIBRAW_SUCCESS) {
        result = raw.dcraw_process();
    }
    int imageError = LIBRAW_SUCCESS;
    libraw_processed_image_t *image = result == LIBRAW_SUCCESS ? raw.dcraw_make_mem_image(&imageError) : nullptr;
    if (result != LIBRAW_SUCCESS || !image || imageError != LIBRAW_SUCCESS || image->type != LIBRAW_IMAGE_BITMAP || image->colors != 3 || image->bits != 8) {
        int finalError = result != LIBRAW_SUCCESS ? result : imageError;
        if (image) {
            LibRaw::dcraw_clear_mem(image);
        }
        if (error) {
            *error = [NSError errorWithDomain:@"CR3Companion" code:21 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:libraw_strerror(finalError)] ?: @"RAW 解码输出无效"}];
        }
        return NO;
    }

    NSData *pixelData = [NSData dataWithBytes:image->data length:image->data_size];
    size_t width = image->width;
    size_t height = image->height;
    LibRaw::dcraw_clear_mem(image);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pixelData);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef cgImage = CGImageCreate(width, height, 8, 24, width * 3, colorSpace,
                                       kCGBitmapByteOrderDefault | kCGImageAlphaNone,
                                       provider, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    if (!cgImage) {
        if (error) {
            *error = [NSError errorWithDomain:@"CR3Companion" code:22 userInfo:@{NSLocalizedDescriptionKey: @"无法创建 RGB 图像"}];
        }
        return NO;
    }

    NSDictionary *sourceProperties = ImageProperties(sourceURL);
    NSMutableDictionary *destinationProperties = [NSMutableDictionary dictionary];
    destinationProperties[(NSString *)kCGImageDestinationLossyCompressionQuality] = @1.0;
    NSNumber *orientation = sourceProperties[(NSString *)kCGImagePropertyOrientation];
    if (orientation) {
        destinationProperties[(NSString *)kCGImagePropertyOrientation] = orientation;
    }
    NSDictionary *exif = sourceProperties[(NSString *)kCGImagePropertyExifDictionary];
    NSDictionary *tiff = sourceProperties[(NSString *)kCGImagePropertyTIFFDictionary];
    NSDictionary *gps = sourceProperties[(NSString *)kCGImagePropertyGPSDictionary];
    if (exif) {
        destinationProperties[(NSString *)kCGImagePropertyExifDictionary] = exif;
    }
    if (tiff) {
        destinationProperties[(NSString *)kCGImagePropertyTIFFDictionary] = tiff;
    }
    if (gps) {
        destinationProperties[(NSString *)kCGImagePropertyGPSDictionary] = gps;
    }

    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)destinationURL, CFSTR("public.jpeg"), 1, NULL);
    if (!destination) {
        CGImageRelease(cgImage);
        if (error) {
            *error = [NSError errorWithDomain:@"CR3Companion" code:23 userInfo:@{NSLocalizedDescriptionKey: @"无法创建 JPEG 文件"}];
        }
        return NO;
    }
    CGImageDestinationAddImage(destination, cgImage, (__bridge CFDictionaryRef)destinationProperties);
    BOOL finalized = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    CGImageRelease(cgImage);
    if (!finalized && error) {
        *error = [NSError errorWithDomain:@"CR3Companion" code:24 userInfo:@{NSLocalizedDescriptionKey: @"JPEG 写入失败"}];
    }
    return finalized;
}

static NSArray<PHAssetCollection *> *EditableAlbums(PHAsset *asset) {
    NSMutableArray<PHAssetCollection *> *albums = [NSMutableArray array];
    PHFetchResult<PHAssetCollection *> *collections =
        [PHAssetCollection fetchAssetCollectionsContainingAsset:asset withType:PHAssetCollectionTypeAlbum options:nil];
    [collections enumerateObjectsUsingBlock:^(PHAssetCollection *collection, NSUInteger index, BOOL *stop) {
        if ([collection canPerformEditOperation:PHCollectionEditOperationAddContent]) {
            [albums addObject:collection];
        }
    }];
    return albums;
}

static BOOL ImportJPEG(NSURL *jpegURL, PHAsset *sourceAsset, NSError **error) {
    NSArray<PHAssetCollection *> *albums = EditableAlbums(sourceAsset);
    __block NSString *createdIdentifier;
    BOOL changed = [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        PHAssetChangeRequest *createRequest = [PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:jpegURL];
        createRequest.creationDate = sourceAsset.creationDate;
        createRequest.location = sourceAsset.location;
        createRequest.favorite = sourceAsset.favorite;
        createRequest.hidden = sourceAsset.hidden;
        PHObjectPlaceholder *placeholder = createRequest.placeholderForCreatedAsset;
        createdIdentifier = placeholder.localIdentifier;
        for (PHAssetCollection *album in albums) {
            PHAssetCollectionChangeRequest *albumRequest = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:album];
            [albumRequest addAssets:@[placeholder]];
        }
    } error:error];
    return changed && createdIdentifier.length != 0;
}

- (BOOL)processItem:(CR3WorkItem *)item verifyOnly:(BOOL)verifyOnly error:(NSError **)error {
    NSString *temporaryDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:temporaryDirectory withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }
    NSURL *sourceURL = [NSURL fileURLWithPath:[temporaryDirectory stringByAppendingPathComponent:item.resource.originalFilename]];
    NSURL *jpegURL = [NSURL fileURLWithPath:[temporaryDirectory stringByAppendingPathComponent:item.filename]];
    BOOL success = WaitForResource(item.resource, sourceURL, error) && DecodeCR3ToJPEG(sourceURL, jpegURL, error);
    if (success && !verifyOnly) {
        success = ImportJPEG(jpegURL, item.asset, error);
    }
    [[NSFileManager defaultManager] removeItemAtPath:temporaryDirectory error:nil];
    return success;
}

@end

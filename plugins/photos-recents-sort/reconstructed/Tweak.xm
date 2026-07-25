// Reconstructed from static analysis of PhotosRecentsSort.dylib.
// This is a behavior-oriented source skeleton, not a byte-accurate recovery.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <CoreLocation/CoreLocation.h>

static NSString * const kPRSPrefsDomain = @"ayao.photosrecentssort";
static BOOL PRSEnabled = YES;
static BOOL PRSGalleryCleanEnabled = YES;
static BOOL PRSRecentsTimeSortEnabled = NO;
static BOOL PRSSkipDeleteConfirmationEnabled = NO;
static NSMapTable *PRSFetchResultMap = nil; // PHFetchResult -> NSArray<PHAsset *>

static void PRSPrefsChanged(__unused CFNotificationCenterRef center,
                            __unused void *observer,
                            __unused CFStringRef name,
                            __unused const void *object,
                            __unused CFDictionaryRef userInfo) {
    PRSLoadPrefs();
}

static BOOL PRSReadBool(NSString *key, BOOL fallback) {
    CFPropertyListRef value = CFPreferencesCopyAppValue((CFStringRef)key, (CFStringRef)kPRSPrefsDomain);
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

static void PRSLoadPrefs(void) {
    CFPreferencesAppSynchronize((CFStringRef)kPRSPrefsDomain);
    PRSEnabled = PRSReadBool(@"enabled", YES);
    PRSGalleryCleanEnabled = PRSReadBool(@"galleryCleanEnabled", YES);
    PRSRecentsTimeSortEnabled = PRSReadBool(@"recentsTimeSortEnabled", NO);
    PRSSkipDeleteConfirmationEnabled = PRSReadBool(@"skipDeleteConfirmationEnabled", NO);
}

@interface PRSAssetSortKey : NSObject
@property (nonatomic, copy) NSString *localIdentifier;
@property (nonatomic, strong) NSDate *creationDate;
@property (nonatomic, assign) double dayBucket;
@property (nonatomic, assign) BOOL hasLocation;
@property (nonatomic, assign) NSInteger latBucket;
@property (nonatomic, assign) NSInteger lonBucket;
@property (nonatomic, copy) NSString *locationBucket;
@property (nonatomic, copy) NSString *nameKey;
@property (nonatomic, assign) NSUInteger originalIndex;
@end

@implementation PRSAssetSortKey
@end

static BOOL PRSShouldHandleCollection(PHAssetCollection *collection) {
    if (!collection) {
        return NO;
    }

    NSString *title = [collection localizedTitle] ?: @"";
    if ([title isEqualToString:@"Recents"] || [title isEqualToString:@"最近项目"]) {
        return YES;
    }

    // Static strings also show AllPhotos / All / Recent / Recents.
    if ([title rangeOfString:@"Recent"].location != NSNotFound ||
        [title rangeOfString:@"最近"].location != NSNotFound ||
        [title rangeOfString:@"AllPhotos"].location != NSNotFound) {
        return YES;
    }

    return NO;
}

static NSString *PRSLocationBucketForAsset(PHAsset *asset) {
    CLLocation *location = [asset location];
    if (!location) {
        return nil;
    }
    CLLocationCoordinate2D c = [location coordinate];
    return [NSString stringWithFormat:@"%ld:%ld",
            (long)llround(c.latitude * 100.0),
            (long)llround(c.longitude * 100.0)];
}

static NSString *PRSNameKeyForAsset(PHAsset *asset) {
    NSArray *resources = [PHAssetResource assetResourcesForAsset:asset];
    NSString *filename = [[resources firstObject] originalFilename];
    if (!filename.length) {
        return @"<nil>";
    }
    NSString *name = [[filename stringByDeletingPathExtension] lowercaseString];
    return name ?: @"<nil>";
}

static PRSAssetSortKey *PRSBuildSortKey(PHAsset *asset, NSUInteger index) {
    PRSAssetSortKey *key = [PRSAssetSortKey new];
    key.localIdentifier = [asset localIdentifier];
    key.creationDate = [asset creationDate] ?: [NSDate distantFuture];
    key.originalIndex = index;
    key.nameKey = PRSNameKeyForAsset(asset);

    NSDate *start = nil;
    NSTimeInterval interval = 0;
    [[NSCalendar currentCalendar] rangeOfUnit:NSCalendarUnitDay
                                    startDate:&start
                                     interval:&interval
                                      forDate:key.creationDate];
    key.dayBucket = [start timeIntervalSinceReferenceDate];

    CLLocation *location = [asset location];
    key.hasLocation = (location != nil);
    if (location) {
        CLLocationCoordinate2D c = [location coordinate];
        key.latBucket = llround(c.latitude * 100.0);
        key.lonBucket = llround(c.longitude * 100.0);
        key.locationBucket = PRSLocationBucketForAsset(asset);
    }

    return key;
}

static NSComparisonResult PRSCompareKeys(PRSAssetSortKey *lhs, PRSAssetSortKey *rhs) {
    if (lhs.dayBucket < rhs.dayBucket) return NSOrderedAscending;
    if (lhs.dayBucket > rhs.dayBucket) return NSOrderedDescending;

    if (lhs.hasLocation != rhs.hasLocation) {
        return lhs.hasLocation ? NSOrderedAscending : NSOrderedDescending;
    }

    if (lhs.latBucket < rhs.latBucket) return NSOrderedAscending;
    if (lhs.latBucket > rhs.latBucket) return NSOrderedDescending;
    if (lhs.lonBucket < rhs.lonBucket) return NSOrderedAscending;
    if (lhs.lonBucket > rhs.lonBucket) return NSOrderedDescending;

    NSComparisonResult fileCompare = [lhs.nameKey compare:rhs.nameKey options:NSCaseInsensitiveSearch];
    if (fileCompare != NSOrderedSame) {
        return fileCompare;
    }

    if (lhs.originalIndex < rhs.originalIndex) return NSOrderedAscending;
    if (lhs.originalIndex > rhs.originalIndex) return NSOrderedDescending;
    return NSOrderedSame;
}

static NSArray<PHAsset *> *PRSSortedAssetsFromFetchResult(PHFetchResult *result) {
    NSMutableArray *pairs = [NSMutableArray arrayWithCapacity:[result count]];
    for (NSUInteger idx = 0; idx < [result count]; idx++) {
        PHAsset *asset = [result objectAtIndex:idx];
        if (!asset) {
            continue;
        }
        [pairs addObject:@{
            @"asset": asset,
            @"key": PRSBuildSortKey(asset, idx),
        }];
    }

    [pairs sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
        return PRSCompareKeys(lhs[@"key"], rhs[@"key"]);
    }];

    NSMutableArray *assets = [NSMutableArray arrayWithCapacity:[pairs count]];
    for (NSDictionary *pair in pairs) {
        [assets addObject:pair[@"asset"]];
    }
    return assets;
}

static void PRSRegisterFetchResult(PHFetchResult *result, PHAssetCollection *collection) {
    if (!PRSEnabled || !PRSRecentsTimeSortEnabled || !result || !PRSShouldHandleCollection(collection)) {
        return;
    }

    if (!PRSFetchResultMap) {
        PRSFetchResultMap = [NSMapTable weakToStrongObjectsMapTable];
    }

    NSArray *assets = PRSSortedAssetsFromFetchResult(result);
    if ([assets count] > 0) {
        [PRSFetchResultMap setObject:assets forKey:result];
    }
}

static NSArray *PRSSortedAssetsForFetchResult(id fetchResult) {
    return [PRSFetchResultMap objectForKey:fetchResult];
}

static void PRSHideView(UIView *view) {
    if (!PRSEnabled || !PRSGalleryCleanEnabled || !view) {
        return;
    }
    [view setAlpha:0.0];
    [view setUserInteractionEnabled:NO];
}

%hook UIViewController

- (void)viewWillAppear:(BOOL)animated {
    PRSLoadPrefs();
    %orig;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    PRSLoadPrefs();
}

%end

%hook PXCuratedLibraryZoomLevelControl

- (void)didMoveToWindow {
    %orig;
    PRSHideView((UIView *)self);
}

- (void)layoutSubviews {
    %orig;
    PRSHideView((UIView *)self);
}

- (void)setAlpha:(CGFloat)alpha {
    %orig(PRSGalleryCleanEnabled ? 0.0 : alpha);
}

- (CGSize)intrinsicContentSize {
    if (PRSEnabled && PRSGalleryCleanEnabled) {
        return CGSizeZero;
    }
    return %orig;
}

- (double)height {
    if (PRSEnabled && PRSGalleryCleanEnabled) {
        return 0.0;
    }
    return %orig;
}

%end

%hook _PXCuratedLibraryZoomLevelSegmentedControl

- (void)didMoveToWindow {
    %orig;
    PRSHideView((UIView *)self);
}

- (void)layoutSubviews {
    %orig;
    PRSHideView((UIView *)self);
}

- (void)setAlpha:(CGFloat)alpha {
    %orig(PRSGalleryCleanEnabled ? 0.0 : alpha);
}

- (CGSize)intrinsicContentSize {
    if (PRSEnabled && PRSGalleryCleanEnabled) {
        return CGSizeZero;
    }
    return %orig;
}

- (double)height {
    if (PRSEnabled && PRSGalleryCleanEnabled) {
        return 0.0;
    }
    return %orig;
}

%end

%hook PXCuratedLibrarySecondaryToolbarController

- (double)height {
    if (PRSEnabled && PRSGalleryCleanEnabled) {
        return 0.0;
    }
    return %orig;
}

- (double)_height {
    if (PRSEnabled && PRSGalleryCleanEnabled) {
        return 0.0;
    }
    return %orig;
}

- (id)contentView {
    id view = %orig;
    if (PRSEnabled && PRSGalleryCleanEnabled && [view isKindOfClass:[UIView class]]) {
        PRSHideView((UIView *)view);
    }
    return view;
}

%end

%hook UICollectionView

- (void)setDataSource:(id)dataSource {
    %orig;
    if (PRSEnabled && PRSRecentsTimeSortEnabled) {
        [self reloadData];
    }
}

- (void)didMoveToWindow {
    %orig;
    if (PRSEnabled && PRSRecentsTimeSortEnabled) {
        [self reloadData];
    }
}

- (void)reloadData {
    %orig;
}

%end

%hook PHAsset

+ (id)fetchAssetsInAssetCollection:(PHAssetCollection *)collection options:(PHFetchOptions *)options {
    id result = %orig;
    PRSRegisterFetchResult(result, collection);
    return result;
}

+ (id)fetchAssetsWithOptions:(PHFetchOptions *)options {
    id result = %orig;
    // Static analysis confirms this path is also hooked, but the original
    // collection source is less explicit here. Keep it as a future patch point.
    return result;
}

%end

%hook PHFetchResult

- (id)objectAtIndex:(NSUInteger)index {
    NSArray *sorted = PRSSortedAssetsForFetchResult(self);
    if (sorted && index < [sorted count]) {
        return sorted[index];
    }
    return %orig;
}

- (id)objectAtIndexedSubscript:(NSUInteger)index {
    NSArray *sorted = PRSSortedAssetsForFetchResult(self);
    if (sorted && index < [sorted count]) {
        return sorted[index];
    }
    return %orig;
}

- (NSUInteger)indexOfObject:(id)object {
    NSArray *sorted = PRSSortedAssetsForFetchResult(self);
    if (sorted) {
        NSUInteger idx = [sorted indexOfObject:object];
        if (idx != NSNotFound) {
            return idx;
        }
    }
    return %orig;
}

%end

%hook PUDeletePhotosActionController

- (BOOL)shouldSkipDeleteConfirmation {
    if (PRSEnabled && PRSSkipDeleteConfirmationEnabled) {
        return YES;
    }
    return %orig;
}

%end

%ctor {
    PRSLoadPrefs();
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        PRSPrefsChanged,
        CFSTR("ayao.photosrecentssort/preferences.changed"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
}

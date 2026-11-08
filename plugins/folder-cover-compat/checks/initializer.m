#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <assert.h>
#import <stdlib.h>

// Isolated runtime models: none of these classes touches UIApplication,
// windows, real icons, or personal data. Test the actual production dylib.
@interface SBRootFolder : NSObject @end
@implementation SBRootFolder @end
@interface SBIconListModel : NSObject { @public id _folder; } @end
@implementation SBIconListModel @end
@interface SBFolder : NSObject { @public id _parent; } @end
@implementation SBFolder @end
@interface SBFolderIcon : NSObject { @public id _folder; } @end
@implementation SBFolderIcon @end
@interface SBIconGridImage : NSObject
@property(nonatomic) CGSize size;
@property(nonatomic) CGFloat scale;
+ (CGSize)sizeForLayout:(id)layout;
+ (CGRect)rectAtIndex:(NSUInteger)i inLayout:(id)layout maxCount:(NSUInteger)n;
@end
@implementation SBIconGridImage
+ (CGSize)sizeForLayout:(id)layout { (void)layout; return CGSizeMake(45, 61); }
+ (CGRect)rectAtIndex:(NSUInteger)i inLayout:(id)layout maxCount:(NSUInteger)n {
    (void)i; (void)layout; (void)n; return CGRectMake(1, 2, 13, 13);
}
@end
@interface SBFolderIconImageCache : NSObject {
@public id _listLayout;
@public SBIconGridImage *_cached;
@public NSUInteger rebuilds;
}
- (id)imageForPageAtIndex:(NSUInteger)page inFolderIcon:(id)icon;
- (void)rebuildImagesForFolderIcon:(id)icon;
+ (id)imageForPageAtIndex:(NSUInteger)page inFolderIcon:(id)icon listLayout:(id)layout
    gridCellImageProvider:(id)provider pool:(id)pool;
+ (id)gridCellImageOfSize:(CGSize)size forIconImage:(id)image;
@end
@implementation SBFolderIconImageCache
- (id)imageForPageAtIndex:(NSUInteger)page inFolderIcon:(id)icon {
    if (!_cached) _cached = [[self class] imageForPageAtIndex:page inFolderIcon:icon
        listLayout:_listLayout gridCellImageProvider:nil pool:nil];
    return _cached;
}
- (void)rebuildImagesForFolderIcon:(id)icon {
    rebuilds++;
    _cached = nil;
    [self imageForPageAtIndex:0 inFolderIcon:icon];
}
+ (id)imageForPageAtIndex:(NSUInteger)page inFolderIcon:(id)icon listLayout:(id)layout
    gridCellImageProvider:(id)provider pool:(id)pool {
    (void)page; (void)icon; (void)provider; (void)pool;
    SBIconGridImage *image = [SBIconGridImage new];
    image.size = [SBIconGridImage sizeForLayout:layout];
    image.scale = 3;
    return image;
}
+ (id)gridCellImageOfSize:(CGSize)size forIconImage:(id)image { (void)size; return image; }
@end
@interface SBFolderIconImageView : NSObject {
@public id _icon;
@public SBFolderIconImageCache *_cache;
}
- (void)setIcon:(id)icon location:(id)location animated:(BOOL)animated;
- (void)updateImageAnimated:(BOOL)animated;
- (void)fulfillGridImageForPageElement:(id)element;
- (void)folderIconImageCache:(id)cache didUpdateImagesForFolderIcon:(id)icon;
- (id)_folderIcon;
- (id)_folderIconImageCache;
@end
@implementation SBFolderIconImageView
- (id)_folderIcon { return _icon; }
- (id)_folderIconImageCache { return _cache; }
- (void)setIcon:(id)icon location:(id)location animated:(BOOL)animated {
    (void)location; (void)animated; _icon = icon;
}
- (void)updateImageAnimated:(BOOL)animated { (void)animated; [_cache imageForPageAtIndex:0 inFolderIcon:_icon]; }
- (void)fulfillGridImageForPageElement:(id)element { (void)element; [self updateImageAnimated:NO]; }
- (void)folderIconImageCache:(id)cache didUpdateImagesForFolderIcon:(id)icon {
    (void)cache; (void)icon; [self updateImageAnimated:NO];
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 4) return 64;
        // Injector has already selected this helper by its real executable
        // name. This changes only getprogname for the production guard.
        setprogname("SpringBoard");
        // The two stub images are UUID gate fixtures, NOT actual addon code.
        if (!dlopen(argv[1], RTLD_NOW | RTLD_LOCAL)) { fprintf(stderr, "gate1: %s\n", dlerror()); return 69; }
        if (!dlopen(argv[2], RTLD_NOW | RTLD_LOCAL)) { fprintf(stderr, "gate2: %s\n", dlerror()); return 69; }
        void *patch = dlopen(argv[3], RTLD_NOW | RTLD_LOCAL);
        if (!patch) { fprintf(stderr, "%s\n", dlerror()); return 69; }
        uint64_t *counters = dlsym(patch, "FCCounters");
        assert(counters && counters[0] == 1);
        SBRootFolder *root = [SBRootFolder new];
        SBIconListModel *list = [SBIconListModel new]; list->_folder = root;
        SBFolder *folder = [SBFolder new]; folder->_parent = list;
        SBFolderIcon *icon = [SBFolderIcon new]; icon->_folder = folder;
        SBFolderIconImageCache *cache = [SBFolderIconImageCache new]; cache->_listLayout = [NSObject new];
        SBFolderIconImageView *view = [SBFolderIconImageView new]; view->_cache = cache;
        [view setIcon:icon location:@"SBIconLocationRoot" animated:NO];
        [view updateImageAnimated:NO];
        fprintf(stderr, "preflight size=%g,%g counters=%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu\n",
            cache->_cached.size.width, cache->_cached.size.height,
            counters[0], counters[1], counters[2], counters[3], counters[4], counters[5], counters[6], counters[7]);
        assert(cache->_cached.size.width == 60 && cache->_cached.size.height == 60);
        assert(counters[2] && counters[3]);
        SBIconGridImage *bad = [SBIconGridImage new]; bad.size = CGSizeMake(45, 61); bad.scale = 3;
        cache->_cached = bad;
        [view fulfillGridImageForPageElement:nil];
        assert(cache->rebuilds == 1 && cache->_cached.size.width == 60 && cache->_cached.size.height == 60);
        [view setIcon:icon location:@"SBIconLocationAppLibraryCategoryPodExpanded" animated:NO];
        cache->_cached = nil;
        [view updateImageAnimated:NO];
        assert(cache->_cached.size.width == 45 && cache->_cached.size.height == 61);
        assert([SBIconGridImage sizeForLayout:cache->_listLayout].width == 45);
        assert(folder->_parent == list && list->_folder == root);
        printf("{\"initializer\":true,\"production_hook_calls\":true,\"square_home_cover\":true,"
            "\"bad_cache_regenerated\":true,\"non_target_unchanged\":true,\"real_UI_verified\":false}\n");
    }
    return 0;
}

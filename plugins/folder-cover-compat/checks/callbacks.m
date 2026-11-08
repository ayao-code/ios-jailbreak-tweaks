#define FC_FIXTURE 1
#import "../Tweak.m"
#import <assert.h>

@implementation FCFixtureImage
@end

@interface FCFixtureGridImage : FCFixtureImage
@end
@implementation FCFixtureGridImage
@end

@interface FCFixtureRootFolder : NSObject
@end
@implementation FCFixtureRootFolder
@end

@interface FCFixtureListModel : NSObject { @public id _folder; }
@end
@implementation FCFixtureListModel
@end

@interface FCFixtureFolder : NSObject {
@public id _parent;
}
@end
@implementation FCFixtureFolder
@end

@interface FCFixtureIcon : NSObject {
@public id _folder;
}
@end
@implementation FCFixtureIcon
@end

@interface FCFixtureCache : NSObject {
@public id _listLayout;
@public UIImage *_cachedImage;
@public BOOL _failRebuild;
@public NSUInteger _rebuildCount;
}
@end

@interface FCFixtureView : NSObject {
@public id _icon;
@public FCFixtureCache *_cache;
}
- (id)_folderIcon;
- (id)_folderIconImageCache;
@end

static BOOL throwOnUpdate;
static NSUInteger untouchedCalls;
static id otherIcon;
static id otherLayout;
static UIImage *returnedImage;
static BOOL probeNested;

static CGSize OriginalSize(id self, SEL cmd, id layout) {
    (void)self; (void)cmd; (void)layout;
    untouchedCalls++;
    return CGSizeMake(45, 61);
}

static CGRect OriginalRect(id self, SEL cmd, NSUInteger index, id layout, NSUInteger count) {
    (void)self; (void)cmd; (void)index; (void)layout; (void)count;
    return CGRectMake(1, 2, 13, 13);
}

static id OriginalCell(id self, SEL cmd, CGSize size, id image) {
    (void)self; (void)cmd;
    if (activeCall && activeCall->rendering) assert(size.width == 138 && size.height == 138);
    return image;
}

static id OriginalFactory(id self, SEL cmd, NSUInteger page, id icon,
                          id layout, id provider, id pool) {
    (void)self; (void)cmd; (void)page; (void)icon; (void)provider; (void)pool;
    CGSize size = CoverSize(nil, NULL, layout);
    BOOL target = activeCall && activeCall->rendering;
    if (target) assert(size.width == 60 && size.height == 60);
    if (probeNested && target) {
        // A different icon/layout factory must never inherit square forcing.
        probeNested = NO;
        GeneratePage(nil, NULL, 0, otherIcon, otherLayout, nil, nil);
        assert(activeCall && activeCall->layout == layout);
    }
    if (target) {
        CGRect rect = CellRect(nil, NULL, 0, layout, 9);
        assert(rect.origin.x == 0 && rect.origin.y == 0 && rect.size.width == 60);
        assert(CGRectIsEmpty(CellRect(nil, NULL, 1, layout, 9)));
        assert(CellImage(nil, NULL, CGSizeMake(13, 13), returnedImage) == returnedImage);
    } else {
        assert(size.width == 45 && size.height == 61);
    }
    return returnedImage;
}

static id OriginalPage(id self, SEL cmd, NSUInteger page, id icon) {
    (void)cmd;
    FCFixtureCache *cache = self;
    if (cache->_cachedImage) return cache->_cachedImage;
    UIImage *image = GeneratePage(nil, NULL, page, icon, cache->_listLayout, nil, nil);
    cache->_cachedImage = image;
    return image;
}

@implementation FCFixtureCache
- (void)rebuildImagesForFolderIcon:(id)icon {
    _rebuildCount++;
    // Synchronous observer re-entry is common. No recursive rebuild allowed.
    UIImage *before = PageImage(self, NULL, 0, icon);
    assert(before == _cachedImage);
    if (_failRebuild) return;
    _cachedImage = nil;
    OriginalPage(self, NULL, 0, icon);
}
@end

@implementation FCFixtureView
- (id)_folderIcon { return _icon; }
- (id)_folderIconImageCache { return _cache; }
@end

static void OriginalSetIcon(id self, SEL cmd, id icon, id location, BOOL animated) {
    (void)cmd; (void)location; (void)animated;
    ((FCFixtureView *)self)->_icon = icon;
}

static void OriginalUpdate(id self, SEL cmd, BOOL animated) {
    (void)cmd; (void)animated;
    FCFixtureView *view = self;
    if (throwOnUpdate) [NSException raise:@"FixtureError" format:@"fixture exception"];
    PageImage(view->_cache, NULL, 0, view->_icon);
}

static void OriginalFulfill(id self, SEL cmd, id element) {
    (void)element;
    OriginalUpdate(self, cmd, NO);
}

static void OriginalDidUpdate(id self, SEL cmd, id cache, id icon) {
    (void)cache; (void)icon;
    OriginalUpdate(self, cmd, NO);
}

void MSHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original) {
    (void)cls; (void)selector; (void)replacement; (void)original;
    // The fixture must not install any hook or simulate installation success.
    abort();
}

static FCFixtureGridImage *Image(CGSize size) {
    FCFixtureGridImage *image = [FCFixtureGridImage new];
    image.size = size;
    image.scale = 3;
    return image;
}

int main(void) {
    @autoreleasepool {
        // Same initializer must reject a non-SpringBoard host without UIKit,
        // hooking or side effects. Calling it twice remains a safe no-op.
        Init(); Init();
        assert(FCCounters[0] == 0);
        folderViewClass = [FCFixtureView class];
        folderIconClass = [FCFixtureIcon class];
        rootFolderClass = [FCFixtureRootFolder class];
        listModelClass = [FCFixtureListModel class];
        gridImageClass = [FCFixtureGridImage class];
        coverEnabled = YES;
        coverSide = 60;
        originalSetIcon = OriginalSetIcon;
        originalUpdate = OriginalUpdate;
        originalFulfill = OriginalFulfill;
        originalDidUpdate = OriginalDidUpdate;
        originalSize = OriginalSize;
        originalRect = OriginalRect;
        originalCellImage = OriginalCell;
        originalGeneratePage = OriginalFactory;
        originalPageImage = OriginalPage;

        FCFixtureRootFolder *root = [FCFixtureRootFolder new];
        FCFixtureListModel *list = [FCFixtureListModel new]; list->_folder = root;
        FCFixtureFolder *folder = [FCFixtureFolder new]; folder->_parent = list;
        FCFixtureIcon *icon = [FCFixtureIcon new]; icon->_folder = folder;
        FCFixtureCache *cache = [FCFixtureCache new]; cache->_listLayout = [NSObject new];
        FCFixtureView *view = [FCFixtureView new]; view->_cache = cache;
        returnedImage = Image(CGSizeMake(60, 60));
        otherIcon = [FCFixtureIcon new]; otherLayout = [NSObject new];

        assert(!IsHomeFolder(icon, @"SBIconLocationFolder"));
        assert(!IsHomeFolder(icon, @"SBIconLocationAppLibraryCategoryPodExpanded"));
        assert(!IsHomeFolder([NSObject new], @"SBIconLocationRoot"));
        assert(CoverSize(nil, NULL, cache->_listLayout).width == 45);
        assert(activeCall == NULL);

        SetIcon(view, NULL, icon, @"SBIconLocationRoot", NO);
        probeNested = YES;
        Update(view, NULL, NO);
        assert(cache->_cachedImage == returnedImage && FCCounters[2] > 0);
        assert(activeCall == NULL);
        NSUInteger changes = FCCounters[3];
        Update(view, NULL, NO); // square cached image stays untouched
        assert(FCCounters[3] == changes);

        cache->_cachedImage = Image(CGSizeMake(45, 61));
        Fulfill(view, NULL, nil);
        assert(cache->_cachedImage == returnedImage && cache->_rebuildCount == 1);
        assert(!rebuilding && activeCall == NULL);

        cache->_cachedImage = Image(CGSizeMake(45, 61)); cache->_failRebuild = YES;
        Update(view, NULL, NO); Update(view, NULL, NO);
        assert(cache->_rebuildCount == 2); // no repeated rebuild of same failed image
        assert(FCCounters[7] == 1);
        cache->_failRebuild = NO;

        // Additional pages / other folders / other cache instances pass through.
        FCCall scoped = { .view = view, .icon = icon, .cache = cache,
            .layout = cache->_listLayout, .side = 60 };
        Push(&scoped);
        NSUInteger beforeSize = FCCounters[3];
        PageImage(cache, NULL, 1, icon);
        PageImage(cache, NULL, 0, otherIcon);
        FCFixtureCache *otherCache = [FCFixtureCache new];
        otherCache->_listLayout = otherLayout;
        PageImage(otherCache, NULL, 0, icon);
        assert(FCCounters[3] == beforeSize && activeCall == &scoped);
        Pop(&scoped);

        // A nested folder is not a root-home-screen cover.
        folder->_parent = [FCFixtureFolder new];
        assert(!IsHomeFolder(icon, @"SBIconLocationRoot"));
        folder->_parent = list;
        list->_folder = [FCFixtureFolder new];
        assert(!IsHomeFolder(icon, @"SBIconLocationRoot"));
        list->_folder = root;

        // No valid cache/layout must never activate geometry forcing.
        id originalLayout = cache->_listLayout;
        cache->_listLayout = nil;
        FCCall unavailable = {0};
        assert(!PrepareExistingCall(view, &unavailable));
        cache->_listLayout = originalLayout;

        // Non-target view inside an active target invocation must clear context.
        FCCall outer = { .view = view, .icon = icon, .cache = cache,
            .layout = cache->_listLayout, .side = 60, .rendering = YES };
        Push(&outer);
        SetIcon(view, NULL, icon, @"SBIconLocationFolder", NO);
        changes = FCCounters[3];
        Update(view, NULL, NO);
        assert(FCCounters[3] == changes && activeCall == &outer);
        Pop(&outer);

        SetIcon(view, NULL, icon, @"SBIconLocationRoot", NO);
        throwOnUpdate = YES;
        @try { Update(view, NULL, NO); assert(0); }
        @catch (NSException *exception) { assert([exception.name isEqualToString:@"FixtureError"]); }
        assert(activeCall == NULL && !rebuilding);
        throwOnUpdate = NO;

        // Normalized cover logic must never change parent or layout storage.
        assert(folder->_parent == list && list->_folder == root && cache->_listLayout != nil);
        coverEnabled = NO;
        assert(!IsHomeFolder(icon, @"SBIconLocationRoot"));
        // Stress reentrant context save/restore without runtime hook install.
        coverEnabled = YES;
        cache->_cachedImage = returnedImage;
        for (NSUInteger i = 0; i < 1000; i++) {
            Update(view, NULL, NO);
            assert(activeCall == NULL && !rebuilding);
        }
        NSLog(@"[FolderCoverFixture] production callbacks passed; no device rendering claim");
    }
    return 0;
}

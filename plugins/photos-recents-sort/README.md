# Photos 增强

这个目录不是从 Git 历史恢复出来的源码，而是 2026-07-25 从设备 `192.168.0.110` 上已安装包 `ayao.photosrecentssort` 导出的本地快照和静态分析结果。

## 当前确认的包信息

- package id: `ayao.photosrecentssort`
- 名称: `Photos 增强`
- 版本: `0.1.0`
- 注入目标: `com.apple.mobileslideshow`
- 依赖: `mobilesubstrate`, `preferenceloader`

## 目录说明

- `device-export/`
  - 从设备已安装路径直接导出的文件快照。
  - 包含 `PhotosRecentsSort.dylib`、注入 plist、设置 bundle、PreferenceLoader 入口，以及 dpkg 文件清单和 md5。
  - 这不是原始 `.deb`，只是已安装内容的回收。
- `reconstructed/`
  - 基于 `otool`、`nm`、`strings` 和 plist 元数据做的源码级还原。
  - 目标是保留设计和行为，不承诺与原始源码逐行一致。

## 已确认的功能

从包描述、设置 plist 和二进制元数据可确认这个 tweak 做了三类事情：

1. 图库清爽模式
   - 隐藏照片 App 里和缩放层级相关的控件。
   - 压缩对应工具栏高度。
   - 设置项默认开启。

2. 最近项目时间排序
   - 只作用于照片 App 的最近项目展示。
   - 通过 hook `PHAsset` / `PHFetchResult` 相关路径，在内存里做重排。
   - 包描述明确说明它不修改照片库数据库。
   - 设置项默认关闭。

3. 删除无需确认
   - hook `PUDeletePhotosActionController` 的确认逻辑。
   - 只作用于照片 App。
   - 设置项默认关闭。

## 已确认的设置项

来自设置页 `Root.plist`：

- `enabled`，默认 `1`
- `galleryCleanEnabled`，默认 `1`
- `recentsTimeSortEnabled`，默认 `0`
- `skipDeleteConfirmationEnabled`，默认 `0`

设置页按钮 `respringTapped` 会执行一次桌面重启；prefs bundle 二进制里能看到 `sbreload` 和 `killall SpringBoard` 两条回退路径。

## 已确认的 hook 映射

通过 `MSHookMessageEx` 调用点和 Objective-C selector 表，可以确认下列 hook：

- `UIViewController`
  - `viewWillAppear:`
  - `viewDidAppear:`
- `PXCuratedLibraryZoomLevelControl`
  - `didMoveToWindow`
  - `layoutSubviews`
  - `setAlpha:`
  - `intrinsicContentSize`
  - `height`
- `_PXCuratedLibraryZoomLevelSegmentedControl`
  - `didMoveToWindow`
  - `layoutSubviews`
  - `setAlpha:`
  - `intrinsicContentSize`
  - `height`
- `PXCuratedLibrarySecondaryToolbarController`
  - `height`
  - `_height`
  - `contentView`
- `UICollectionView`
  - `setDataSource:`
  - `didMoveToWindow`
  - `reloadData`
- `PHAsset` 类方法
  - `fetchAssetsInAssetCollection:options:`
  - `fetchAssetsWithOptions:`
- `PHFetchResult`
  - `objectAtIndex:`
  - `objectAtIndexedSubscript:`
  - `indexOfObject:`
- `PUDeletePhotosActionController`
  - `shouldSkipDeleteConfirmation`

## 排序逻辑的可还原程度

能还原出设计轮廓，但还原不到原始作者源码的精确实现细节。

当前能确认的点：

- 二进制里定义了 `PRSAssetSortKey` 类。
- 这个类有以下字段：
  - `localIdentifier`
  - `creationDate`
  - `dayBucket`
  - `hasLocation`
  - `latBucket`
  - `lonBucket`
  - `locationBucket`
  - `nameKey`
  - `originalIndex`
- 排序过程中会读取：
  - `PHAsset.creationDate`
  - `PHAsset.location`
  - `PHAssetResource.originalFilename`
  - `PHAssetCollection.localizedTitle`
  - `assetCollectionType`
  - `assetCollectionSubtype`

这说明它不是简单按 `creationDate` 一个字段排序，而是构造了一个较稳定的复合排序键，避免同一天、同位置、同批次素材的顺序抖动。

## 还原边界

- 没找到原始 `.deb`。
- 没有仓库内源码历史。
- 目前目录下的 `reconstructed/` 只能作为行为级源码骨架，适合继续人工补全，不适合作为“原始源码已完全恢复”的证据。

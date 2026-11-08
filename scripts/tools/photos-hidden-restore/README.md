# 隐藏项目原件恢复工具

一次性 PhotoKit 工具，用于从已校验备份恢复普通照片、视频和 Live Photo，并恢复拍摄日期、原添加时间、位置和隐藏状态。它不直接写 `Photos.sqlite`，不注入任何 App，不转码原始资源。

每个计划包含主资源、可选 `pairedVideo`、两个资源的大小与 SHA-256、原始文件名、拍摄日期、添加时间和位置。`import-one` 先核对暂存文件，再以 PhotoKit 创建隐藏项目；随后通过 `PHAssetChangeRequest.addedDate` 恢复原添加时间。验证会通过 PhotoKit 导出主资源和配套 MOV，逐一比对 SHA-256，并回读隐藏状态、日期和 Live Photo 类型。任何验证失败都会删除本轮刚创建的项目。

必须先做完整图库快照和重复检查，并先用一张 Live Photo 做 UI 验证；确认隐藏相簿可见、长按可播放、日期位置正确后，才可扩展批量流程。

```sh
xcrun clang -target arm64-apple-ios16.0 \
  -isysroot "$HOME/theos/sdks/iPhoneOS16.5.sdk" \
  -fobjc-arc -O2 -Wall -Wextra -Wno-deprecated-declarations \
  -framework Foundation -framework Photos -framework CoreLocation -lsqlite3 \
  PhotosHiddenRestore.m -o /tmp/PhotosHiddenRestore
ldid -Sentitlements.plist /tmp/PhotosHiddenRestore
```

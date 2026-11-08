# 编辑前原件恢复工具

用于将已校验但当前图库缺失的编辑前原件作为新的、未编辑、非隐藏项目恢复到一个独立相簿。工具通过 PhotoKit 创建项目，不直接写 `Photos.sqlite`，不转码，不覆盖现有项目。

每项计划包含原始资源路径、字节数、SHA-256、拍摄日期、原添加时间、位置和目标相簿标识。导入后立即通过 PhotoKit 导出主资源和 Live Photo 配套视频并核对 SHA-256，同时验证非隐藏、无编辑、日期、位置、媒体类型及相簿归属。失败会删除本轮刚创建的项目。编辑后项目记录的裁剪尺寸或剪辑时长不能用于约束编辑前原件，恢复后的尺寸和时长以原始资源自身为准。

```sh
xcrun clang -target arm64-apple-ios16.0 \
  -isysroot "$HOME/theos/sdks/iPhoneOS16.5.sdk" \
  -fobjc-arc -O2 -Wall -Wextra -Wno-deprecated-declarations \
  -framework Foundation -framework Photos -framework CoreLocation -lsqlite3 \
  PhotosEditedOriginalRestore.m -o /tmp/PhotosEditedOriginalRestore
ldid -Sentitlements.plist /tmp/PhotosEditedOriginalRestore
```

命令：`create-album TITLE RECEIPT`、`import-one PLAN`、`finish-existing PLAN UUID`、`verify RECEIPT`。`import-one` 会等待最多 30 秒让新建项目进入 PhotoKit 查询视图。`finish-existing` 仅用于已确认由本轮创建、但在即时查询延迟中未能写回执的孤立项目；它会补齐添加时间和相簿归属，再执行同一套原件哈希验证。同名相簿或已有回执会拒绝继续，避免误用旧会话或重复导入。

读取项目时启用 `includeAllBurstAssets`，确保带原始连拍标识、被系统折叠为非首选成员的原件仍可按 local identifier 核验并加入目标相簿；工具不会修改或拆散系统连拍组。

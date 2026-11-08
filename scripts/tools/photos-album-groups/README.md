# 照片分组相簿工具

一次性 PhotoKit 命令行工具。它只创建用户相簿并把现有照片加入相簿，不复制或重新导入媒体，不修改拍摄日期、添加时间、位置、原件或已有相簿成员。

计划格式为 `{"groups":[{"title":"相簿名","assetUUIDs":["UUID"]}]}`。标题和项目 UUID 必须全局唯一；目标标题已存在时拒绝执行。创建相簿与加入成员分两个 PhotoKit 事务完成；第二阶段失败时删除本轮刚创建的相簿，避免留下半成品。成功后必须使用 `verify` 回读每个相簿的精确成员集合，并比较操作前后图库快照。

```sh
xcrun clang -target arm64-apple-ios16.0 \
  -isysroot "$HOME/theos/sdks/iPhoneOS16.5.sdk" \
  -fobjc-arc -O2 -Wall -Wextra -Wno-deprecated-declarations \
  -framework Foundation -framework Photos \
  PhotosAlbumGroups.m -o /tmp/PhotosAlbumGroups
ldid -Sentitlements.plist /tmp/PhotosAlbumGroups
```

执行：`PhotosAlbumGroups create PLAN RESULT`，随后执行 `PhotosAlbumGroups verify PLAN`。操作前必须保存含 WAL 的一致性图库备份；操作后确认仅新增预期相簿和成员关系，所有资产字段及既有相簿不变。

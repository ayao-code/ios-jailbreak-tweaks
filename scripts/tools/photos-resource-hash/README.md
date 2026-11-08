# PhotoKit 原始资源只读哈希工具

用于已授权越狱设备的照片恢复核验。工具按资产 UUID 和 `PHAssetResourceType` 读取 PhotoKit 原始资源数据流，在内存中计算 SHA-256 和字节数，不导出文件、不写图库、不注入任何 App。

```sh
xcrun clang -target arm64-apple-ios16.0 \
  -isysroot "$HOME/theos/sdks/iPhoneOS16.5.sdk" \
  -fobjc-arc -O2 -Wall -Wextra -Wno-deprecated-declarations \
  -framework Foundation -framework Photos \
  PhotosResourceHash.m -o /tmp/PhotosResourceHash
ldid -Sentitlements.plist /tmp/PhotosResourceHash
```

输入 JSON：

```json
{"items":[{"resourceFilename":"IMG_0001.JPG","resourceType":0}]}
```

可以使用 `assetUUID`、`resourceFilename`、Apple 参考时间 `creationDate`、`burstIdentifier` 或它们的组合限定资源。传入 `burstIdentifier` 时使用 PhotoKit 的连拍专用查询接口读取系统折叠成员。`resourceType` 使用 `PHAssetResourceType` 的整数值，例如照片为 `0`、视频为 `1`、Live Photo 配套视频为 `3`。若选择条件匹配多份资源，工具会拒绝继续，避免选错资源。

`list-date APPLE_TIME TOLERANCE` 只读列出时间窗口内 PhotoKit 可见项目的真实 local identifier、burst identifier 和资源名，用于核对数据库 UUID 与 PhotoKit 标识不一致的导入项目。

# CR3 原件单项恢复工具

仅用于用户明确授权的越狱设备照片恢复，不注入任何 App。默认先 `inspect`，使用 SQLite 只读源及 backup API 保存含 WAL 的一致性快照，再通过 PhotoKit 新增一张 CR3。不要直接写 Photos.sqlite。

构建：

```sh
xcrun clang -target arm64-apple-ios16.0 \
  -isysroot "$HOME/theos/sdks/iPhoneOS16.5.sdk" \
  -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations \
  -framework Foundation -framework Photos -framework CoreLocation -framework UIKit -lsqlite3 \
  PhotosCR3Restore.m -o /tmp/PhotosCR3Restore
ldid -Sentitlements.plist /tmp/PhotosCR3Restore
```

独立工具不是 tweak，不需要 Filter，也不会开启高敏 App 注入。RootHide 下选择 `/rootfs/var/mobile/Media/PhotoData/Photos.sqlite`，普通 rootless 下选择标准路径。

命令：`inspect`、`snapshot NEW_PATH`、`import-one PLAN`、`verify RECEIPT`、`preview RECEIPT`。计划包含暂存 CR3 路径、SHA-256、字节数、原始文件名、Apple 2001 基准拍摄时间、可选位置及预期 PhotoKit 总数。导入时保存源文件，不转码，创建失败即停；已有 receipt 或同名资源拒绝重复导入。

创建成功后立即保存新 localIdentifier，再通过 PHAssetResourceManager 读回 CR3 原始资源，校验 SHA-256 和拍摄时间。仅新增一个项目，不自动修改已有资源、删除项目或批量恢复。若校验超时或失败，不得再次导入，应保留现场并核查 receipt 对应项目。

数据库及 PhotoKit 验证不等于 UI 确认；单项恢复后需实际核对照片 App 可见性、预览和信息，再决定下一步。系统拒绝不支持的 RAW 时不能自动改成 JPEG 或直接写入图库数据库。

用户确认单项 UI 后可使用 `import-batch PLAN`，每批最多 24 张，先核对暂存文件 SHA-256、总数及重复文件名，再使用一个 PhotoKit 事务。成功后先写 batch-receipt.json，再流式读回每张原件核对哈希、大小、拍摄时间及有效位置，写 batch-verified.json。失败必须停止；已有回执只能 `verify-batch RECEIPT`，不能再次导入。每批按顺序执行，不并发写图库；硬盘读取与手机传输可流水线并行，无压缩或转码。

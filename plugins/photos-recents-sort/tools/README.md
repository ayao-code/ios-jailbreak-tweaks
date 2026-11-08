# 指定相簿添加时间修复工具

一次性命令行工具，不安装插件、不常驻运行。必须先获得用户对指定相簿和日期规则的明确授权。

通过 PhotoKit 的运行时私有 `PHAssetChangeRequest.addedDate` 接口修改添加时间，不直接写图库数据库，不修改拍摄日期、原始媒体或相簿成员。接口及数据库只适配已验证的 iOS 16.3，其他版本先执行 `inspect`，不能据此假定兼容。

`prepare` 使用 SQLite backup API 创建包含 WAL 的一致性数据库备份，同时保存精确成员 UUID、原始日期和本地原文件 SHA-256。数据库访问为只读；只有备份文件会被 SQLite 写入。成员、拍摄日期或路径改变时拒绝操作。未下载的原文件记录为 `not-local`，不会触发云端下载。

## 构建

```sh
xcrun clang -target arm64-apple-ios16.0 \
  -isysroot "$HOME/theos/sdks/iPhoneOS16.5.sdk" \
  -fobjc-arc -O2 -Wall -Wextra -Wno-deprecated-declarations \
  -framework Foundation -framework Photos -lsqlite3 \
  PhotosAlbumAddedDate.m -o /tmp/PhotosAlbumAddedDate
ldid -Sentitlements.plist /tmp/PhotosAlbumAddedDate
```

## 执行顺序

```text
PhotosAlbumAddedDate inspect
PhotosAlbumAddedDate prepare <相簿UUID> <精确数量> <新审计目录>
PhotosAlbumAddedDate apply <审计目录>/plan.json 1
PhotosAlbumAddedDate verify <审计目录>/plan.json
PhotosAlbumAddedDate apply <审计目录>/plan.json <精确数量>
PhotosAlbumAddedDate verify <审计目录>/plan.json
```

`apply` 默认把添加时间对齐现有拍摄时间；计划提供 `targetAdded` 时使用该目标，已完成的成员跳过。每次写入使用一个 PhotoKit 事务。先验证单项，确认添加时间生效、拍摄日期和原文件不变后再继续。`verify` 核对数据库成员、日期和原文件哈希，并输出 aligned/remaining 数量。它不证明屏幕显示已刷新或 iCloud 其他设备已同步。

可执行 `PhotosAlbumAddedDate snapshot <新备份路径>`，获取操作后的一致性快照，与 `Photos.before.sqlite` 比较全图库添加时间及受保护属性，检查修改范围。

如需回滚，取得用户授权后执行 `PhotosAlbumAddedDate restore <审计目录>/plan.json`，通过同一 PhotoKit 接口恢复原添加时间。不要用整库覆盖方式恢复，以免覆盖操作后的其他图库变更。完成后保留审计备份，移除设备上的临时工具；仓库中的源码与构建说明保留。

## 拍摄日期补全

对于原件缺少可用拍摄日期、但已通过独立备份映射确认日期的精确 UUID，可在 `prepare-assets` 生成的项目中加入 `targetCreated`，再依次执行 `apply-created PLAN 1`、`verify-created PLAN`。该流程只修改 PhotoKit 的 `creationDate`，把 `addedDate` 作为受保护字段核验，因此不会主动改变“最近项目”的添加顺序。`restore-created PLAN` 恢复计划中的原拍摄日期。

日期来源必须有可审计证据，不能仅按当前邻居猜测。先选一个容易在界面定位的样本，比较全库前后快照，确认只有目标项目的拍摄日期及系统记账字段变化、添加时间和原文件哈希不变，再由用户确认界面后扩大范围。

## 指定恢复批次

没有单独相簿的恢复批次使用 `prepare-assets <UUID数组JSON> <精确数量> <新审计目录>`。UUID 数组从入库回执产生，仅包括本次授权的项目，不按文件扩展名或整个“最近项目”扩大范围；不创建临时相簿。每个 UUID 必须唯一、存在于未删除的个人主库。生成计划后复用 `apply`、`verify`、`restore` 和单项优先流程。添加时间改为拍摄日期只会按日期重新定位，不保证所有项目出现在列表顶部。

精确 UUID 范围可能包含连拍非首选成员。PhotoKit fetch 必须启用 `includeAllBurstAssets`，否则默认折叠会导致取回数量小于计划并在写入前安全拒绝；该选项只影响指定 UUID 的可见性，不扩大计划或数据库范围。

如果现有照片使用恢复时的添加时间且顺序已正确，不能直接把缺失批次添加时间设为过去的拍摄时间。可以在备份日期与现有照片对应关系已验证的前提下，仅为目标项目设置计划中的 `targetAdded`，取相邻非目标项目现有添加时间之间的唯一值。拍摄时间 `created` 仍作为受保护字段核验；`restore` 仍恢复计划原 `added`。操作前后必须确认所有非目标项目添加时间完全不变、原有相对顺序不变，先单项验证实际 UI，再扩大范围。

`plan-recents-insertion.py <现有照片映射JSON> <CR3恢复回执映射JSON> <新输出JSON>` 仅在 Mac 生成插入建议，不连接或修改手机。现有映射必须按添加时间升序且备份文件名日期非递减；同秒 CR3 放在现有同秒组之后，同一间隙均匀分配唯一添加时间。缺少前后邻居、时间碰撞或顺序不一致时拒绝生成。输出不是直接可执行的 PhotoKit 计划：必须先用 `prepare-assets` 获取最新设备备份及原件哈希，确认邻居和全库受保护字段未漂移，再按 UUID 将 `targetAdded` 合入对应项目。首轮应建立只有一张样本的独立计划，不能把单项成功当作自动批量授权或 UI 验证。

`plan-recents-reorder.py <图库快照> <目标项目JSON> <无有效日期项目JSON> <新输出JSON>` 用于只移动明确目标项目的添加时间。它把无有效日期项目排除出日期锚点，在所有其他项目位置固定的前提下，为每个目标选择使拍摄日期逆序最少的“最近项目”间隙；同一间隙的目标按拍摄日期稳定排序。计划必须证明非目标相对顺序完全不变，并报告仍由非目标自身造成的残余逆序。执行前仍需用 `prepare-assets` 生成最新计划和原件哈希，再合入 `targetAdded`，不能直接使用模拟输出写入。

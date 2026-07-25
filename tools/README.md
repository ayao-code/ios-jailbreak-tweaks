# Tools

本目录存放一次性运维脚本，不属于 jailbreak tweak 本体。

## `photos-reorder-added-date.sh`

用途：

- 连接指定 iPhone。
- 备份手机照片库数据库 `Photos.sqlite` / `Photos.sqlite-wal` / `Photos.sqlite-shm`。
- 按照片的 `ZDATECREATED` 重写 `ZADDEDDATE`，让依赖“加入时间”排序的相册展示更接近拍摄时间顺序。
- 回传修改后的数据库并做一次回读校验。

重要边界：

- 这是一次性修复脚本，不是常驻服务。
- 每次运行都会直接修改手机上的照片库数据库。
- 它不会长期接管 iOS 的相册排序逻辑；如果后续再次导入照片或系统重新写库，排序仍可能变化。
- 运行前必须确认设备 SSH 可连接，并接受对照片库数据库做直接修改的风险。

执行方式：

```sh
tools/photos-reorder-added-date.sh root@<device-ip>
```

如果不传设备参数，脚本会使用脚本内置的默认 SSH 目标。

运行结果：

- 每次执行都会在仓库根目录生成新的 `backups/photos-db-<timestamp>/` 目录作为当次备份和校验产物。
- 历史备份不是脚本运行依赖，不需要长期保留。

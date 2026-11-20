# 插件设置键客户端

用于用户明确授权的两台 RootHide iPhone 设置项对齐。不安装 App、不注入目标
进程、不迁移账号、不修改 RootHide 或 App 注入策略，不提供系统设置批量写入。

```sh
bash scripts/tools/settings-key-client/build.sh "$BUILD_DIR"
settings-key-client read <allowed-domain>
settings-key-client apply <allowed-domain> <canonical-patch.plist>
settings-key-client notify <allowed-domain>
```

`allowed-settings.h` 保存逐域、逐键白名单。`apply` 仅接受设置值字典，合并而
不删除已有键；不接受任意域、任意键、账号容器或运行时快照。补丁路径必须
来自当前 RootHide 规范路径，不能硬编码设备标识。

多数域使用 CFPreferencesSetMultiple / Synchronize，并返回当前域回读。
状态栏插件必须使用仓库 `SISettingsStore.m` 的原子存储：以
`SI_SETTINGS_TEST=1` 排除编译期固定 RootHide 库，并将其路径设置为运行时已
核对的 `NSHomeDirectory()` 下的插件文件；实际读写、文件锁、保留格式/权限、
last-good 和通知仍执行同一份存储源码。不得因此写入其他文件或声称测试宏
本身证明兼容。客户端只接受当前已核对 RootHide HOME、mobile 身份。

客户端本身**不自动备份、不核对插件安装、不判断跨机型数值是否合理、不等待
所有 CFPreferences 落盘**。调用方必须先验证已安装的同版本消费者、设置面板
及默认值；不要求双端备份或保存目标旧配置。源数据只读导出，助手只在目标
运行。返回后比对 API、磁盘、格式、权限与非目标键，
必要时保留原格式，再通知消费者。没有消费者的域不应写入。

项目恢复规则允许兼容的纯设置文件整体覆盖，但本客户端仍只合并白名单键，
不提供整文件替换；整文件覆盖须使用已核对的写入路径，不能放开任意域冒充该能力。

2026-11-18 已在 iPhone 12 mini / iOS 16.3.1 / RootHide 执行设置写入并原生/磁盘
回读。源码编译和本次持久化验证不代表任意设备、全部插件功能或 UI 布局已验收。
Crane 不由本客户端操作，使用单独的 `scripts/migration/crane-root-settings.m`
原生全局界面选项接口。实际连接、备份和回读日志留在被忽略的私有目录。

Bolders Reborn 的 `tweakEnabled` 是当前消费者读取的总开关，已纳入逐键白名单。
对齐外观参数时必须同时核对总开关，不能以其余尺寸／透明度数值相同代替启用状态。
旧配置中的未知字段只有确认当前消费者仍读取后才迁移，不复制失效字段或运行时快照。

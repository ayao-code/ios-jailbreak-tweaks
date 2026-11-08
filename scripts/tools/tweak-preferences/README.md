# 定向插件偏好接口

一次性命令行工具，使用 CFPreferences 读取或同步明确允许的插件偏好域，不注入 App、不附加进程、不刷新全局偏好缓存，也不修改 RootHide 或 Crane 配置。

`sh build.sh` 生成 iOS 16 arm64 工具；源码保留在本目录。构建产物不代表已在其他越狱环境验证。

- `tweak-preferences read <domain>` 输出当前用户、当前 HOME 的允许键，格式为 plist。
- `tweak-preferences apply <domain> <patch.plist>` 通过 CFPreferences 同步 `set` 字典及 `remove` 键数组，然后输出回读结果。
- `tweak-preferences container-read <domain> <container>` 读取明确指定 App 数据容器的插件专属键。
- `tweak-preferences container-apply <domain> <container> <patch.plist>` 使用容器限定的 NSUserDefaults 更新插件专属键并回读。
- `tweak-preferences notify <notification>` 发送指定插件的偏好变更通知，不重载桌面。

微信助手 MiYou 的普通功能开关位于微信主偏好域 `com.tencent.xin`，不是独立的 `com.25mao.miyou` 绑定文件。工具只允许源码逐项列出的 43 个功能键，不笼统允许 `M*`；账号映射、隐藏密码、联系人名单、初始化标记、自动消息内容及 AI 设置不在白名单中。源机没有保存的键不推断为关闭，也不据此清空目标值。

App 内偏好必须先确认实际数据容器并使用 `container-*` 命令。RootHide 会重写普通工具的 `CFFIXED_USER_HOME`，仅设置 HOME 不能证明读到了 App 设置。容器初始化使用运行时可用的 Foundation 私有接口，必须先将读取结果与磁盘插件键对比；接口缺失或结果不一致时停止。微信主偏好只允许 `DT*`、`DA_Voice*` 和 `DumpAppShow`；抖音只允许 `DYYY*`。聊天、登录和原生 App 设置不在写入范围。

目标 RootHide 设备需要平台签名和相应信任缓存才能执行工具；仅上传或签名成功不能作为运行证据。工具与信任缓存不属于 App 注入，工具退出后不常驻。使用后不应保留可执行的临时副本。

使用前遵守 `DEVICE_CONFIG_SAFETY.md`：双重备份、最小键差异、格式和属主保持、设备回读及非目标不变量验证。工具不会自动完成备份或允许跳过验证。

CFPreferences 可能延迟写盘并把 XML 偏好重新序列化为 binary。接口回读后仍需等待磁盘回读一致，检查原格式与属主；需要保留 XML 的文件，在缓存同步完成后以相同语义原子恢复原格式，并再次验证。不应因尚未落盘而重复应用补丁。

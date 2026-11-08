# 设备配置文件安全修改指南

本文约束本项目对 iPhone / iPad 上系统、越狱环境、插件和 App 配置文件的直接修改。默认优先使用官方界面或官方接口；直接写文件属于例外路径。

## 通用流程

1. **只读盘点**：确认目标设备、配置路径、生产者、消费者、文件格式、属主、权限、inode / 映射路径及关键业务不变量。
2. **双重备份**：修改前分别在设备和 Mac 保存带时间戳的原文件，记录格式、权限和语义摘要。备份不能与正式文件使用同一路径。
3. **最小修改**：只改变用户明确要求的键值；保持原序列化格式，不做无关排序、格式化、清理或字段迁移。
4. **本地预检**：验证文件语法、数据类型和关键不变量，并对修改前后解析结果做语义比较。除目标差异外必须完全一致。
5. **暂存写入**：先上传到正式文件同目录的临时路径，设置正确属主和权限；不要直接覆盖正在使用的正式文件。
6. **原子替换**：全部预检通过后使用同一文件系统内的原子重命名替换，确保不会留下半写文件。
7. **设备回读**：重新下载正式文件，验证格式、结构、目标值、非目标值、属主、权限和实际路径。
8. **运行验证**：验证真实消费者能够正常读取和写回；检查对应进程、功能和新崩溃报告。失败时立即使用设备备份原子回滚。

任何一步失败都应停止，不得继续扩大修改范围，也不得用“再写一次”覆盖现场证据。

## RootHideConfig.plist

目标路径：`/var/mobile/Library/RootHide/RootHideConfig.plist`。RootHide 环境中的 `/var/jb/var/mobile/Library/RootHide/RootHideConfig.plist` 可能映射到同一 inode，不能把它们当作两份独立配置分别修改。

### 格式要求

- 保持 XML 1.0 plist，与 RootHide Manager 的 `writeToFile:atomically:` 输出一致。
- 禁止使用 `plistlib.FMT_BINARY`、`plutil -convert binary1` 或其他 binary plist 生成方式覆盖正式文件。
- 不能仅以“`plutil` 可以读取”作为兼容证据。相同逻辑内容在 XML 和 binary plist 中可能被 Foundation 解析为不同的运行时对象类型。

当前官方 RootHide Manager 先通过 `NSDictionary dictionaryWithContentsOfFile:` 读取根字典，再把 `appconfig` 当作 `NSMutableDictionary` 调用 `setObject:forKey:`。在本机验证中：

- XML plist 的 `appconfig` 被解析为可变 `__NSDictionaryM`，原生黑名单开关可以写入。
- binary plist 的 `appconfig` 被解析为不可变 `__NSDictionaryI`，点击开关会在写入前触发 Objective-C 异常并以 `SIGABRT` 退出。

因此 binary plist 的值即使完全正确，仍不兼容当前 Manager 的写入实现。

### 修改前不变量

- 记录 `appconfig` 的键数量和所有键值。
- 单独记录阿里 / 蚂蚁、银行 / 支付 / 证券及京东系高敏 App 的值。
- 记录文件格式、属主、权限、inode、修改时间和语义摘要。
- 确认本次目标 Bundle ID，禁止顺带改变其他 App。

### 修改后验证

- Mac 侧 `plutil -lint` 通过，文件仍为 XML plist。
- 修改前后解析后的对象只存在目标键值差异。
- 正式文件权限及属主与官方写入路径一致。当前 setuid RootHide Manager 经原生开关写回后可生成 `root:mobile`、`0600` 文件，不能为方便 SSH 读取而擅自改回 `mobile:mobile`。
- 高敏 App 黑名单逐项回读符合预期。
- RootHide Manager 原生开关能够完成一次开关与回切，不闪退。
- 配置的修改时间和目标值发生预期变化，CrashReporter 没有新增 RootHide 崩溃报告。

### 回滚

发现语法错误、非目标差异、权限异常、Manager 闪退或黑名单行为异常时，停止继续修改，使用修改前的设备备份原子替换正式文件，再完成同样的回读和运行验证。不得删除最后一份已知可用备份。

## 白名单模式

当前官方 RootHide Manager 在 `SettingViewController` 中将白名单模式开关明确设置为禁用，同时当前 RootHide / Dopamine RootHide / Bootstrap 源码中没有找到读取 `whitelistMode` 并执行“新安装 App 自动加入黑名单”的消费者。

因此：

- 开关置灰、无法点击是当前官方版本的预期行为，不是配置损坏。
- 不得通过直接写入 `settings.whitelistMode` 强行开启；只有配置值而没有运行时消费者，不会实现该功能，还可能制造错误安全预期。
- 在官方真正实现并启用该功能前，新安装的高敏 App 必须逐项加入黑名单并回读验证。

## 禁止做法

- 未备份直接覆盖正式配置。
- 用 binary plist、JSON 等非原格式覆盖 RootHide 配置。
- 把“文件可解析”等同于“目标程序可安全读写”。
- 修改后只看 UI，不检查配置回读和 CrashReporter。
- 为解决配置问题直接安装未经审计的 tweak、helper 或替换版系统 App。
- 强行启用官方界面禁用且运行时未实现的选项。

## Crane 容器切换自动化

普通 App 的 Crane 容器切换使用 `scripts/crane-switch-container.sh`。脚本通过官方 `cranectl` 切换容器，自动识别 App 可执行文件、终止切换前的旧进程、重新启动 App，并验证新 PID 已替换旧 PID。非默认容器还必须在新进程环境中出现匹配的 `CRANE_CONTAINER_IDENTIFIER`；只有配置值变化、目录创建或新 PID 出现都不能作为容器接管成功的证据。

脚本不会读取 App 账号、Keychain 或沙盒内容，也不会创建、清空或删除容器。阿里 / 蚂蚁、银行 / 支付 / 证券及京东系高敏 App 会被脚本直接拒绝，不能为了多开而绕过 RootHide 隔离。

## Choicy 禁注入对照

- 优先官方设置界面，不直接编辑正式 plist。修改前用 `app/safe-domain-probe/scripts/snapshot-14pm-configs.py` 完成配置双端备份、原始字节、格式及属主权限核对；该脚本只适用于已授权的14PM，不是通用设备迁移工具。
- 自定义插件配置开启时，官方禁注入开关可能灰显。先通过官方 UI 关闭目标自定义配置，再启用禁注入；过渡期间不启动目标 App。Choicy 官方通知会结束配置发生变化的旧 App 进程，不能把该行为误判为系统崩溃。
- 扩展配置按自身 bundle ID 分项处理，不假定主程序策略覆盖所有扩展。每次修改前核对页面准确标题、前台和锁屏状态；新截图与已确认截图不一致或页面仍移动就停止输入。修改后完整语义比较只允许当前目标键改变，保留无关设置和原允许名单。
- 禁注入可能与 Crane 非默认容器冲突。看到“Crane.dylib 未加载”弹窗只能证明其启动检查报告缺失，不能称为淘宝越狱检测结论、进程所有镜像已纯净或业务已恢复。
- Crane 容器保护资源写明其通过 App Hook 防止默认容器启动时删除其他容器资料。对已启用保护且保留多个容器的 App，禁止为了测试禁注入而擅自关闭保护、切换默认容器或删除容器；先明确用户接受的账号/容器范围，并验证数据备份和保护语义。不得通过重新开启高敏 App 注入或停共享服务来绕过此冲突。
- 官方 `cranectl --switch` 也必须审计当前配置：14PM 的 Crane 1.3.17-2 在 `separateSystemAccountsEnabled=true` 且容器改变时会请求重启 `accountsd`，传 `reloadApplication:NO` 不能免除此副作用。仅有官方来源不是无副作用证明，禁止放宽现有高敏拒绝规则来执行它。
- 用户同意默认账号不同，不包含原多开数据丢失风险。默认进程可见数据根下的 `Library/___Crane_Containers`；禁注入后保留 `containerProtectionEnabled=true` 也不能证明 App 内保护 Hook 仍有效。配置双端备份不算容器数据备份，完整可恢复数据备份未验证前不继续默认容器启动。核查方法见 `research/safe-domain-2026-10-25/CRANE_DEFAULT_SAFETY.md`。

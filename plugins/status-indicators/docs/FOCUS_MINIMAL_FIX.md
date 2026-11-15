# Focus 最小修复研究（2026-11-14）

状态：已保留无 Focus 基线；`focus12` 已安装，用户确认响应变快，但个人/工作/游戏显示“其他”。`0.1.0+focus13` 候选仅修模式配置解析，本地构建/验证通过，未安装，不作正式发布。

## 新确认的证据

1. 当前手机仍为 `0.1.0+focus11`。现有代码在 SpringBoard 内以 `com.apple.FocusSettings` 创建 DND 查询服务。
2. 只读提取目标 iOS 16.3 SpringBoard 与 Preferences 的原签名：`com.apple.FocusSettings` 属于 Preferences 的 DND state request/updates 名单，不在 SpringBoard 对应名单中。SpringBoard 的名单同时包含 `com.apple.springboard.dndstatemonitor` 等自身客户端身份。
3. 因此当前查询身份与宿主进程权限不匹配；不是“调用方法存在就证明有权读取”。未扩大签名权限、注册信任或调用模式写入接口。
4. 旧会话外部探针返回 `state=null`、`mode_configurations=null`，不能当作关闭状态，也不能证明 SpringBoard 自身没有可用状态源。
5. 公开 RuntimeBrowser 头文件列出 `DNDStateService` 状态监听、`DNDState.activeModeIdentifiers` 和 `isActive`；当前实现只猜测单个字符串字段。该公开头文件未被确认对应目标 iOS 16.3，尚不能当作实际调用 ABI 证明。

公开发现来源：

- https://github.com/nst/iOS-Runtime-Headers/blob/master/PrivateFrameworks/DoNotDisturb.framework/DNDStateService.h
- https://github.com/nst/iOS-Runtime-Headers/blob/master/PrivateFrameworks/DoNotDisturb.framework/DNDState.h
- https://github.com/nst/iOS-Runtime-Headers/blob/master/protocols/DNDStateUpdateListener.h

只读权限证据及历史重建输出保存在本轮 Mac 临时研究目录；不把完整系统签名、设备标识或连接凭据放进仓库。

## 选定方向：独立事件状态，不重做显示层

- 优先确认并复用 SpringBoard 现有 DND 状态入口；若需独立监听，只使用原签名已授权的只读身份。运行时校验类、方法签名、初始查询及注册结果，不能只把客户端字符串换掉就宣布成功。
- 初始状态加实时状态回调；明确活动、关闭、未知/失败。先看活动标记，再从活动模式标识数组解析模式；模式识别使用已确认的标识/语义类型，不能用旧页面名称补全。
- 一个串行入口管理 Focus 状态及订阅代次，主线程仅接收有序渲染结果。关闭后不允许旧查询/旧订阅覆盖；停用后注销监听，迟到回调失效。不新增轮询、常驻诊断日志或主线程同步 IPC。
- `readStateForHost` 继续只管理 VPN；移除其中修改全局 Focus 的逻辑。Focus 事件不再走 `_deferredHostReadPending`，不重建窗口、不重置网速基线。
- VPN 恢复无 Focus 基线的独立更新入口，或保留按宿主的待更新集合；不能用一个全局标记吞掉其他宿主事件。具体入口取决于完整快照实际提交时机，不拍脑袋固定等 40 ms。
- 保留颜色、锚点、位置/尺寸、网速格式及动态居中算法。只补齐 Focus 图标/文字的显隐对称，不顺带修改导入/导出等无关功能。

## 不采用的修补

- 不继续加 40 ms、1 秒或 10 秒回读，不靠打开 App 触发布局。
- 不仅限制“当前宿主可以写 Focus”：当前宿主本身仍可能是旧快照。
- 不把查询失败视为模式关闭，不用旧状态栏快照恢复活动状态。
- 不给 SpringBoard 添加权限、不改 Focus 配置、不注入业务 App，不改变 RootHide 高敏 App 隔离。

## 落地门槛

1. 先确认目标系统真实 ABI、状态读取与订阅结果；没有证据不安装猜测版。读取系统签名仅证明权限名单，不证明状态查询和回调已成功。
2. 本地覆盖：四模式及其他模式、切换后关闭、旧回调到达、停用/重启、查询失败、多宿主 VPN 更新；确认 Focus 改变不影响静音/VPN状态或网速采样生命周期。
3. 本地通过后只准备一个明确版本，再集中一次实机检查桌面/App 切换、四模式及关闭、VPN/静音独立性、控制中心/锁屏及资源边界。
4. 失败时保留原 `centered2` 包回滚，不覆盖回滚源码或原包；本地实现及构建不意味着实机通过。

## focus12 本地实现

- 新增独立 `SIFocusMonitor`：一次加载框架、串行 utility 队列查询及注册监听、主线程有序交付。使用原 SpringBoard 已授权的 `com.apple.springboard.dndstatemonitor` 身份，检查私有方法 ABI 与注册/查询结果；未知与显式关闭分别保存，未知不显示活动图标。
- 新订阅注册后查询初值；若查询期间收到新事件，丢弃旧初值。订阅代次阻断停用/重启后的旧回调；停用与销毁注销监听。无额外轮询或持续日志。
- Focus 回调只调用内容渲染，不能改变 VPN 缓存或停止/重启网速采样。旧 `quietModeEntry` 解析及其诊断树、Darwin 提示后二次猜测查询已移除。
- VPN 用弱引用待更新宿主集合合并下一主队列读回；所有宿主都被消费，不再只捕获首个宿主，也无 40 ms 第二次回读。
- Focus 文字已加入统一隐藏、透明度及动画清理。颜色、宿主选择、固定锚点、动态居中和网速采样算法与修改前逐段一致；本轮不修配置导出/预览的其他缺陷。
- 状态标识只识别内建模式命名空间；自定义模式仍用“其他”。该映射与监听 ABI 通过本地假服务验证，但未读到目标系统实际返回对象，因此尚不能宣称四模式实机切换已成功。

可复跑的本地状态验证：`sh tests/run-focus-monitor.sh OUTPUT_DIRECTORY`。调用真实 monitor 源码；VPN/隐藏测试提取实际方法到 Foundation 假宿主/视图中执行，不假装验证了 UIKit 可见性或视觉动画。

## focus13：只补模式配置解析

- `focus12` 的单元测试使用预设模式字符串，遗漏了 iOS 16 当前模式配置中有模式/图标、但活动 ID 不匹配这些字符串的情况。依据公开 iOS16 运行时结构，合成配置用例可复现三模式都归为“其他”；目标手机的实际模式对象尚未读取，不能称为实机根因已完全证明。
- 先确认 `isActive`，关闭仍无条件隐藏；活动时以同一状态的 `activeModeConfiguration.mode` 为准，精确识别模式标识或 `symbolImageName`。个人对应 person 系列，工作对应 briefcase/person.lanyardcard，游戏对应 gamecontroller，勿扰对应 moon；不做模糊子串匹配，不猜 `semanticType` 的数字值。
- 当有效模式对象存在但图标未知时，保留“其他”，不让可能不一致的标识数组抢回勿扰；仅缺失模式对象或 getter 不可用时沿用原标识兼容路径。所有新增 getter 延续已有对象返回值 ABI 校验。
- 这是图标身份映射，不修改系统模式、图标或配置；若自定义模式复用这些系统图标，本版会显示相应图标，不能将其宣称为严格语义类型分类。未知符号仍为“其他”。
- 36 个新增配置用例覆盖图标、关闭、配置/标识冲突、字段缺失、错误类型/ABI及 getter 失败；另验证配置模式通过现有监听即时交付，不新增查询。ASan/UBSan 及原状态生命周期/VPN隔离测试通过。
- 运行逻辑仅新增解析 helper 和调用点；订阅、队列、初始查询竞争、停用/销毁及控制器/布局/采样源码均与 `focus12` 逐段一致。未增加服务、权限、轮询、日志或安装操作。

结构发现来源：https://github.com/qingralf/iOS16-Runtime-Headers/blob/main/PrivateFrameworks/DoNotDisturb.framework/DNDState.h 和 https://github.com/qingralf/iOS16-Runtime-Headers/blob/main/PrivateFrameworks/DoNotDisturb.framework/DNDMode.h 。公开头文件用于发现结构，不替代目标设备对象与视觉验证。

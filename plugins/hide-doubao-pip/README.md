# HideDoubaoPiP

> 2026-11-08 仓库整理说明：原始截图、设备导出、历史测试包及详细日志已按用户要求清理。下文旧 `research/`、`evidence/` 路径仅描述当时记录，不代表文件仍在；保留正式源码、资源和必要交付包。此次整理未重新执行功能验收。

适用于 iOS 16 的豆包输入法 PiP 插件。当前 1.0.31 仅构建和安装 RootHide 包；普通 Dopamine rootless 的历史包保留为 1.0.30。安装后仅针对豆包输入法创建的 PiP 悬浮窗隐藏 UI；冷启动必须短暂前台激活豆包时，通过双向 App-to-App 事务遮罩隐藏切换，并保留豆包原生语音识别、文字回传和松键停止链路。

## 功能

- PiP 隐藏模块只注入 SpringBoard；无跳转模块只注入豆包主 App 与键盘扩展。
- 只处理系统 `SBPictureInPictureWindow`。
- 优先通过豆包输入法 bundle id `com.bytedance.ios.doubaoime` 识别目标 PiP。
- bundle/process 信息尚未挂载时，用豆包 PiP 的 viewTree 特征兜底；不对明确识别出的非豆包 PiP 执行动作。
- Bundle ID 明确为豆包后，将整个 `SBPictureInPictureWindow` 的 CALayer 渲染设为透明，但不结束 PiP 会话、不调用系统 stash、不移动 PiP frame。
- 保留 `PGHitTestExtendableView` 作为系统可见的 PiP 命中容器，只将其 CALayer 渲染透明，并隐藏内部内容/控制层。
- 通过 PiP window 和少量内部 layout 触发点重新应用隐藏，处理系统 layout 后恢复显示的问题。
- 只在豆包主 App 和键盘扩展内启用原生 `PiP not ready` 恢复及跳转修复，不伪造就绪状态、不拦截其他 URL。
- 仅当键盘准备打开 `oime://start_asr_from_keyboard` 时请求 SpringBoard 准备整屏截图遮罩；确认准备完成后沿用豆包原始 URL 打开路径。
- 冷启动必须短暂前台激活豆包时，先显示当前界面截图遮罩一帧再放行跳转，减少豆包界面闪现。
- 本次语音转场中新创建且 bundle 尚未挂载的豆包特征 PiP 会提前隐藏整个 window layer，避免悬浮窗先出现再消失；非本次转场和明确非豆包 PiP 不受影响。
- 从 Spotlight 发起时不尝试恢复其临时搜索控制器，而是使用系统 Home 关闭路径回到桌面，避免只剩全屏模糊背景。
- 主 App 原生音频会话激活后，等待前向事务完成及 PiP 就绪或宽限结束，再返回原 App；不伪造录音成功，不新增执行断言或后台保活。
- 键盘准备确认超时 0.45 秒时仍放行原始 URL，语音识别、文字回传和松键停止沿用豆包原生链路。
- 完全事件驱动，不新增轮询或常驻后台任务；仅使用启动、回退和安全释放的一次性超时。
- 保留 `/var/mobile/Documents/PiPArrowHide.log` 低频运行日志，达到 256KB 后截断重写。

## 兼容环境

- iOS 16
- 1.0.31：RootHide，包架构 `iphoneos-arm64e`，本次 Mach-O 为 arm64e
- 1.0.30 历史包：普通 Dopamine rootless，包架构 `iphoneos-arm64`
- 需要 `mobilesubstrate`

## 安装

RootHide 设备使用 `packages/ayao.hidedoubaopip_1.0.31_iphoneos-arm64e.deb`；安装后重载 SpringBoard，并重新打开豆包输入法。

普通 Dopamine rootless 仍使用历史 `packages/ayao.hidedoubaopip_1.0.30_iphoneos-arm64.deb`，不要交叉安装。

> 如果设备上已经安装旧包 `com.dada.hidedoubaopip`，请先卸载旧包后再安装新版；新版 package id 为 `ayao.hidedoubaopip`。

## 构建

```sh
THEOS=/path/to/theos sh scripts/build-roothide.sh
```

本次只生成 RootHide 包。`scripts/install-roothide.py` 仅用于已确认身份的 12 mini，交互式读取 sudo 密码，不保存凭据；安装前双端备份并校验 Filter 范围和隔离配置。

## 版本说明

### 1.0.31（RootHide，移除诊断版）

- 保留 1.0.31~debug2 的整屏截图兼容修复、双向转场遮罩、PiP 隐藏和原生语音链路，不回退到 1.0.30。
- 移除窗口枚举、场景状态和单调时间等详细诊断代码；只保留有上限的低频功能日志，无轮询或常驻任务。
- 统一源码、control 和当前包版本为 1.0.31；不修改 14PM 及其他插件。
- 用户反馈消息编辑框基本正常，搜索框与编辑框表现不同。搜索框兼容性仍未全面验收，不能承诺所有场景无问题；GUI 平台明确拒绝本账号的 iOS 自动化权限，没有完整自动验收结果。
- debug1/debug2 的旧归档已按用户要求清理。活动插件目录保留正式源码、正式包和必要发布记录，不再保留旧诊断包。
- 当前构建已完成；正式版实机安装及加载结果记录在 `evidence/release-1.0.31/`，以实际回读为准。

### 1.0.30

- 监听 `SBAppToAppWorkspaceTransaction._didComplete`，只在豆包已成为前台且 App-to-App 事务完整结束后返回原 App。
- 返回条件为“音频已激活 + 前向事务已完成 + PiP 已就绪或 0.9 秒宽限已结束”，避免在第一次切换动画中途反向切换。
- 若系统未回调事务完成事件，音频激活 1.35 秒后按原稳定路径短兜底返回，避免静态遮罩持续到 6 秒总超时。
- 返回原 App 后继续等待反向 App-to-App 事务完成，再撤掉遮罩；不再按打开请求回调后的固定 0.18 秒提前撤罩。
- 若反向事务完成事件漏失，1 秒后自动撤罩，避免界面被长期遮挡。
- 继续使用高层截图遮罩和转场期 PiP 整窗预隐藏；不新增轮询、常驻任务或声音控制。
- 正式版固化已验证的 `1.0.30~test26` 行为，不包含后续键盘区域开孔实验。

### 1.0.30~test21

- Spotlight 语音完成后不再恢复已失效的搜索控制器，改为系统 Home 关闭路径返回桌面，避免全屏模糊。
- 遮罩显示后延迟 40ms 再启动豆包，使遮罩先完成一帧提交，降低冷启动界面瞬间闪现。
- 本次语音转场内，对 bundle 尚未挂载但已符合豆包结构的 PiP 提前隐藏整个 window layer，减少悬浮窗闪现。
- 音频激活但 PiP 回调延迟时的兜底等待由 1.2 秒缩短为 0.9 秒；未增加轮询、后台任务或音频控制。

### 1.0.29

- 修复 1.0.28 在主 App 确认路由后立即释放执行权，导致后续文字无法回传、松开空格无法停止的问题。
- 只有原生 `AVAudioSession` 成功激活后才向键盘确认接管，避免把“已调用路由”误判为“录音已可用”。
- 录音期间维持豆包主 App 的短时执行权，继续使用原生 `app2key.asrGetResult`、`key2app.sendFinishAudio` 和 `key2app.stopASR` 链路。
- 原生音频会话停用时立即通知 SpringBoard 释放执行权，并保留 120 秒安全上限，防止异常情况下长期持有。
- 保持无前台激活和事件驱动；不增加轮询、常驻定时器或永久后台保活。

### 1.0.28

- 修复豆包主进程被 RunningBoard 冻结后无法接收 Darwin 事件、最终仍回退前台跳转的问题。
- 键盘请求到达时，由 SpringBoard 在不激活界面的情况下启动或恢复豆包，再申请最长 5 秒的 `TransientWakeup` 执行断言。
- 通过 `prepare → ready → request → ack` 事件握手处理冷启动监听注册竞态，避免语音请求在主 App 初始化前丢失。
- 收到主 App确认或超时后立即释放断言；没有轮询、常驻定时器或长期后台保活。
- 仍只拦截 `oime://start_asr_from_keyboard`，唤醒或接管失败时在 5.5 秒后恢复豆包原始行为。

### 1.0.27

- 新增键盘扩展到后台豆包主进程的 Darwin 事件桥。
- 后台主进程直接复用豆包原生 `handleStartASRByOpenURL`，不依赖前台激活来启动语音。
- 只有收到主进程确认才取消 URL 跳转；500ms 无确认自动回退原始行为，避免语音不可用。
- 仅拦截语音启动 URL，不影响设置页、反馈页、用户主动打开豆包或其他 App。

### 1.0.26

- 增加豆包主 App/键盘扩展侧的原生无跳转恢复修复。
- 强制开启 `enablePiPNotReadyForceRecovery`，让失效 PiP 会话由豆包自身重建，而不是回退到前台拉起。
- 强制关闭 `disableJumpFix`，确保豆包自带的跳转修复持续生效。
- 不强制返回“PiP 已就绪”，避免真实会话失效时出现不跳转但无法录音。
- 不拦截用户主动打开豆包，也不影响其他 URL Scheme、应用或视频 PiP。

### 1.0.25

- 保留豆包对系统 PiP 会话的占用，只将明确识别出的豆包 PiP window 的 CALayer 渲染设为透明。
- 双 PiP window 交接期间忽略会被全局活动应用污染的身份，只使用窗口本地 bundle id 或豆包 viewTree 特征。
- 非豆包 window 如果复用了插件处理过的 window，则恢复 window layer 渲染。
- 移除临时 250ms 诊断采样和 `[DIAG]`、`[ALPHA]` 高频日志，只保留事件驱动的隐藏与恢复逻辑。

### 1.0.25~debug1

- 保持 1.0.24 的隐藏行为不变。
- 增加多 PiP 切换期间的 window、bundle id、关键子视图状态和 `setAlpha:` 请求日志，用于定位豆包抢占视频 PiP 后自身持续显示的问题；250ms 状态采样在 SpringBoard 重载 10 分钟后自动停止。

### 1.0.24

- 修复使用相机后系统恢复豆包 PiP 命中层透明度，导致悬浮窗重新出现的问题。
- 仅当 PiP window 的 bundle id 明确为 `com.bytedance.ios.doubaoime` 时拦截命中层 `setAlpha:`；其他应用及身份未知的 PiP 均原样放行。
- 移除临时轮询诊断，不增加常驻采样开销。

### 1.0.23

- 基于 1.0.22 的成功方案做 release 收敛，保留豆包 PiP 抢占能力并降低日志量。
- 继续保持 `SBPictureInPictureWindow` 可见、不禁用交互、不调用 stash、不移动 frame。
- 继续保持 `PGHitTestExtendableView` 作为系统可见的命中容器，只隐藏其 CALayer 渲染，并隐藏内部内容/控制层。
- 删除高频 `[CALL]`、`[MISS]`、`[SETALPHA-PASS]` 测试日志，只保留 `[INIT]` 和低频/状态变化 `[HIDE]` 日志。
- 日志文件上限从 512KB 降到 256KB。

### 1.0.22

- 修正 1.0.21 隐藏 `PGHitTestExtendableView.alpha` 后仍无法挤占微信 PiP 的问题。
- 保留 `PGHitTestExtendableView` 的 UIView 状态和交互状态，只将其 CALayer `opacity=0` 用于视觉隐藏。
- 继续隐藏内部内容/控制层，但不改 `SBPictureInPictureWindow`、不调用 stash、不移动 frame。
- 日志标记 `mode=hitLayerContent`，同时记录 hit view 的 UIView alpha、layer opacity、交互状态和 frame。

### 1.0.18

- 回到 1.0.2 旧版隐藏方式，并增加诊断日志定位“桌面仍可见”的原因。
- 保留旧版窗口层 `alpha=0`、禁用触摸和 `setAlpha:` 拦截逻辑。
- 增加 `[CALL]`、`[MISS]`、`[HIDE]`、`[SETALPHA-*]` 日志，记录每个 PiP window 的 bundle、alpha、hidden、关键 PG view frame、stash 目标和漏判原因。
- control 元数据增加 `Tag: role::enduser`，名称改为 `Hide Doubao PiP`，便于在 Sileo 已安装列表里显示和搜索。

### 1.0.17

- 按用户要求收敛为最小逻辑，只识别豆包 bundle 并移动豆包 PiP 到右侧边缘。
- 删除 viewTree 兜底识别、多 PiP 复杂判断、透明隐藏、stash 和手势模拟逻辑。
- 只通过 `com.bytedance.ios.doubaoime` 识别豆包 PiP；明确识别为其他 bundle 时直接跳过。

### 1.0.16

- 修正诊断版本标识，继续使用 1.0.15 的 pan-only 拖拽手势筛选。
- 初始化日志更新为 `v1.0.16 simulated-drag-pan-only`，避免和 1.0.14 日志混淆。

### 1.0.15

- 修正 1.0.14 误命中 PiP 缩放手势的问题，继续定位真正拖拽手势。
- 查找拖拽手势时过滤 `Pinch`，只接受 `UIPanGestureRecognizer` 或类名包含 `Pan` / `Drag` 的手势。
- 当找不到拖拽手势时，记录目标 view 到父级 view 链上的全部 gesture class。

### 1.0.14

- 只模拟人手把豆包输入法 PiP 拖到右侧边缘，让系统自己执行边缘收纳。
- 不再使用窗口透明隐藏，不调用系统 stash 接口，不直接改 PiP 内部 view 的 frame。
- 识别豆包 PiP 后，找到拖拽命中层上的 pan/drag 手势，构造 `UITouch`，发送 began/moved/ended。

### 1.0.13

- 回到旧版稳定的窗口层隐藏原理，解决纯拖动内部 view 后系统再次显示豆包浮窗的问题。
- 不再移动 PiP 内部 view，也不调用系统 stash 接口。
- 对识别出的豆包 PiP 在 `SBPictureInPictureWindow` 层设置 `alpha=0` 并禁用触摸，hook `setAlpha:` 防止系统重新显示。

### 1.0.12

- 验证豆包语音跳转是否由系统 stash 状态触发。
- 完全移除 `setStashed` / `_setStashed` 调用路径，只移动 `PGHitTestExtendableView` 到右侧边缘。
- 保留 1.0.11 的 PiP 窗口、bundle、active bundle 和 frame 诊断日志，并在日志中标记 `stashMode=disabled`。

### 1.0.11

- 保留 1.0.10 的停靠和 stash 行为，增加诊断日志用于确认豆包语音触发跳转的原因。
- 记录每次 PiP 触发时的窗口指针、识别 bundle、Pegasus 当前活跃 bundle、可见 PiP 列表、拖拽层 frame 和具体 stash 目标。

### 1.0.10

- 停靠动作改为移动 PiP 的拖拽命中层 `PGHitTestExtendableView`，不再移动内部内容容器。
- 同步调用 PiP controller 的系统 stash 接口，尽量接近人工拖到边缘后的收纳状态。

### 1.0.9

- 收敛为长期使用版本：只在明确识别到豆包输入法 bundle 后停靠。
- 删除递归扫描、详细测试日志、非豆包延迟重试和 viewTree 兜底执行。
- 固定按优先级选择一个 PiP 内容视图停靠到右侧边缘。

### 1.0.8

- 命中豆包后递归扫描 PiP root 下所有可停靠的 `PG*` 小视图并推到右侧边缘。
- 多 PiP 分支也支持通过豆包 bundle 直接命中，不再只依赖 viewTree。

### 1.0.7

- 将内容视图停靠方式从直接改 `frame` 改为叠加 `transform`，降低被系统 PiP layout 立即覆盖的概率。

### 1.0.6

- 增加 PiP 创建后的延迟重试，处理豆包 bundle 和内容视图晚挂载。
- 命中豆包后直接将实际 `PG*` PiP 内容视图停靠到屏幕右侧边缘，不只依赖系统 stash 接口。

### 1.0.5

- 增加 stash 目标类名和关键 `PG*` 视图 frame 诊断日志。
- 停靠时尝试 `_pipController`、adapter、Pegasus controller 和内部 PiP view controller，便于定位真正可拖拽对象。

### 1.0.4

- 增加测试日志，记录 PiP 触发原因、识别来源、viewTree 匹配、多 PiP 状态和 stash 结果。
- 日志继续写入 `/var/mobile/Documents/PiPArrowHide.log`，并对高频 layout 触发做节流。

### 1.0.3

- 行为从透明隐藏改为自动停靠到屏幕边缘。
- 保留豆包输入法 PiP 识别和 PiP 内部 layout 触发点。
- 移除 `window.alpha = 0` 和禁用触摸逻辑。

### 0.0.2

- package id 改为 `ayao.hidedoubaopip`。
- 恢复为 Downloads 下 `HideDoubaoPiP_release_v2.deb` 对应的 v8 源码逻辑。
- 保留豆包输入法 PiP 识别、透明化隐藏、禁用触摸和 PiP 内部 layout 触发点。
- 不包含右侧停靠、缩放、短时 re-hide burst 或常驻 watchdog。

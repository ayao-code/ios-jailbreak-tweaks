# HideDoubaoPiP

适用于 iOS 16 Dopamine rootless 越狱环境的 SpringBoard PiP 隐藏插件。安装后仅针对豆包输入法创建的 PiP 悬浮窗隐藏 UI，同时保留系统对该 PiP 的窗口和命中容器认知，让豆包 PiP 仍能正常抢占/挤掉微信等其他应用的视频 PiP。

## 功能

- 只注入 SpringBoard。
- 只处理系统 `SBPictureInPictureWindow`。
- 优先通过豆包输入法 bundle id `com.bytedance.ios.doubaoime` 识别目标 PiP。
- bundle/process 信息尚未挂载时，用豆包 PiP 的 viewTree 特征兜底；不对明确识别出的非豆包 PiP 执行动作。
- 不把 `SBPictureInPictureWindow` 设为透明，不禁用 window 交互，不调用系统 stash，不移动 PiP frame。
- 保留 `PGHitTestExtendableView` 作为系统可见的 PiP 命中容器，只将其 CALayer 渲染透明，并隐藏内部内容/控制层。
- 通过 PiP window 和少量内部 layout 触发点重新应用隐藏，处理系统 layout 后恢复显示的问题。
- 保留 `/var/mobile/Documents/PiPArrowHide.log` 低频运行日志，达到 256KB 后截断重写。

## 兼容环境

- iOS 16
- Dopamine rootless 越狱
- arm64 / arm64e 设备
- 需要 `mobilesubstrate`

## 安装

下载 `ayao.hidedoubaopip_1.0.23_iphoneos-arm64.deb` 后安装，安装完成后重载 SpringBoard。

仓库内对应安装包路径：`plugins/hide-doubao-pip/packages/ayao.hidedoubaopip_1.0.23_iphoneos-arm64.deb`。

> 如果设备上已经安装旧包 `com.dada.hidedoubaopip`，请先卸载旧包后再安装新版；新版 package id 为 `ayao.hidedoubaopip`。

## 构建

```sh
THEOS=/path/to/theos HDBP_DEBUG_LOGS=0 FINALPACKAGE=1 make clean package
```

## 版本说明

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

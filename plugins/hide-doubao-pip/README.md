# HideDoubaoPiP

适用于 iOS 16 Dopamine rootless 越狱环境的 SpringBoard PiP 隐藏插件。安装后仅针对豆包输入法创建的 PiP 悬浮窗进行透明化隐藏，并尽量保留 Bilibili、微信等正常视频 PiP。

## 功能

- 只注入 SpringBoard。
- 只处理系统 `SBPictureInPictureWindow`。
- 优先通过豆包输入法 bundle id `com.bytedance.ios.doubaoime` 识别目标 PiP。
- bundle/process 信息缺失时，使用保守的 PiP 视图结构和尺寸特征兜底识别。
- 对识别出的豆包输入法 PiP 执行 `window.alpha = 0`，并禁用触摸。
- 不使用 `hidden=YES`，避免破坏系统 PiP 状态机。
- 通过 PiP 内部 layout 触发点重新应用隐藏，处理 PiP 容器复用后再次出现的问题。
- 保留 `/var/mobile/Documents/PiPArrowHide.log` 低频诊断日志，达到 512KB 后截断重写，便于后续分析弹窗和耗电问题。

## 兼容环境

- iOS 16
- Dopamine rootless 越狱
- arm64 / arm64e 设备
- 需要 `mobilesubstrate`

## 安装

下载 `ayao.hidedoubaopip_1.0.0_iphoneos-arm64.deb` 后安装，安装完成后重载 SpringBoard。

仓库内对应安装包路径：`plugins/hide-doubao-pip/ayao.hidedoubaopip_1.0.0_iphoneos-arm64.deb`。

> 如果设备上已经安装旧包 `com.dada.hidedoubaopip`，请先卸载旧包后再安装新版；新版 package id 为 `ayao.hidedoubaopip`。

## 构建

```sh
THEOS=/path/to/theos HDBP_DEBUG_LOGS=0 FINALPACKAGE=1 make clean package
```

## 版本说明

### 0.0.2

- package id 改为 `ayao.hidedoubaopip`。
- 恢复为 Downloads 下 `HideDoubaoPiP_release_v2.deb` 对应的 v8 源码逻辑。
- 保留豆包输入法 PiP 识别、透明化隐藏、禁用触摸和 PiP 内部 layout 触发点。
- 不包含右侧停靠、缩放、短时 re-hide burst 或常驻 watchdog。

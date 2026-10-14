# AiPowerButton

适用于 iOS 16 Dopamine rootless 越狱环境的侧边键快捷插件。安装后可以在系统设置的 `AiPowerButton` 中选择长按关机键启动豆包或 DeepSeek 语音助手。

## 功能

- 长按关机键启动语音 AI 助手。
- 设置中可选择启动应用：豆包或 DeepSeek。
- 默认启动豆包。
- 豆包模式：长按关机键开始语音输入，松开关机键后结束录音并发送。
- DeepSeek 模式：长按关机键开始语音输入，松开关机键后结束录音并发送。
- 保留系统原始操作：音量键加关机键仍会触发 iOS 原生关机/SOS 界面。
- 正式版已关闭测试日志和自动验证逻辑。

## 兼容环境

- iOS 16
- Dopamine rootless 越狱
- arm64 / arm64e 设备
- 需要 `mobilesubstrate` 和 `preferenceloader`

## 安装

当前稳定版是 `packages/ayao.aipowerbutton_1.0.4_iphoneos-arm64.deb`。安装完成后需要重载 SpringBoard。

`packages/` 中的 1.0.2、1.0.3 和 1.0.4~test1 至 1.0.4~test10 均作为历史与诊断产物保留，不得删除或被正式包覆盖。

> 如果设备上已经安装旧包 `com.ayao.doubaopowerbutton`，请先卸载旧包后再安装新版；新版 package id 为 `ayao.aipowerbutton`。

## 使用方法

1. 打开系统设置。
2. 进入 `AiPowerButton`。
3. 开启插件。
4. 在「启动应用」中选择「豆包」或「DeepSeek」。
5. 单独长按关机键触发所选语音助手。
6. 如果需要使用系统关机/SOS，按音量键加关机键即可，插件会自动放行系统原始行为。

## 版本说明

### 1.0.4

- 修复 DeepSeek 已在前台且键盘展开时，长按关机键无法发起语音的问题。
- 使用 DeepSeek 自身 `VoiceGesture.__onLongPress:` 业务回调，并只在同步调用期间让目标手势读取到 `Began/Ended` 状态。
- 2026-10-14 已自动完成亮屏、正常 Face ID 解锁、拉起 DeepSeek、开始录音、持续约 3 秒和停止发送的实机验证；音频会话在停止前持续激活 2.85 秒。
- 正式包移除测试日志、自动唤醒、自测结果文件和 `AVAudioSession` 审计 Hook，仅保留运行所需的有限重试与通知链。

### 1.0.4~test10（单链自动验证包）

- 保留此前所有版本，不覆盖、不删除旧产物。
- 增加自测运行中互斥，避免构造回调和锁状态回调重复启动两条 start/stop 链。
- DeepSeek 在停止前记录音频会话是否仍激活、持续秒数和结束回调结果，并写入 `Documents/aipb_1.0.4_test10_result.plist`。
- 通过标准：一次开始、一次停止、音频会话激活成功并持续至少两秒至停止动作。

### 1.0.4~test9（自动唤醒验证包）

- 使用 test8 在设备上确认存在的 `SBLockScreenManager._wakeScreenForTapToWake`，仅模拟一次点亮屏幕并触发系统正常 Face ID，不提供或绕过密码。
- 若系统没有正常解锁，则继续等待锁状态事件；若正常解锁，则自动完成 DeepSeek 启动、录音开始、三秒等待、停止与音频会话验证。
- 保留 test7 的解锁后自动拉起 DeepSeek 与完整录音验证流程。

### 1.0.4~test8（自动唤醒探测包）

- 通过运行时方法审计确认当前设备可用 `_wakeScreenForTapToWake`，未执行解锁或密码相关 API。

### 1.0.4~test7（解锁后全自动验证包）

- 自动读取系统锁屏状态；锁屏时不强行绕过安全机制，而是监听系统锁状态通知，在下一次自然解锁后自行运行。
- 解锁后通过已验证的 `FBSOpenApplicationService` 拉起 DeepSeek，确认其真实处于前台后自动执行开始、等待三秒、停止流程。
- 使用 `/var/mobile/Documents/aipb_1.0.4_test7_self_test_completed` 标记防止成功流程重复运行。
- 在 DeepSeek 进程内记录 `AVAudioSession setActive`，用于判断业务回调是否真实启动录音会话。
- 日志路径为 `/var/mobile/Documents/aipb_1.0.4_test7_springboard.log` 和 DeepSeek 沙盒内的 `Documents/aipb_1.0.4_test7_deepseek.log`。

### 1.0.4~test6（锁屏态自动验证包）

- 证实 SpringBoard 内自动流程可以运行，但设备处于锁屏态时 App 启动请求不会产生 DeepSeek 进程。

### 1.0.4~test5（外部通知自动验证包）

- 验证了冷重启后 SpringBoard 插件可正常注入；外部 Darwin 通知工具在该设备上未能触发 observer，因此由 test6 改为构造后单次自运行。

### 1.0.4~test4（业务回调测试版）

- 直接调用 DeepSeek 自身 `VoiceGesture.__onLongPress:`，并仅在同步调用期间虚拟化目标对象读取到的 `Began/Ended` 状态。

### 1.0.4~test3（测试版，已知失败）

- UIKit 将强制设置的 `Began` 立即转为 `Failed(5)`，证实不能直接驱动识别器内部状态机。

### 1.0.4~test2（诊断包，已安装采集）

- 证实侧键与 Darwin 通知链正常，也能定位真实 `VoiceGesture`。
- 证实原伪造 `UITouch` 调用后手势仍停留在 `Possible`，这是无法发起语音的直接原因。

### 1.0.3（测试版，已知失败）

- 尝试处理 DeepSeek 已在前台及键盘展开时的语音手势定位。
- 2026-10-14 实机验证仍无法发起语音，仅保留用于问题定位，不作为稳定版本。

### 1.0.2

- 豆包模式接入与 DeepSeek 一致的长按录音、松开发送交互。
- 前台启动豆包后，在豆包进程内切换语音模式，并仅操作实机确认的 `BasicInputVoiceView.voiceInputGesture`。
- 语音控件查找仅在一次长按期间进行有限次数重试，不增加常驻轮询。

### 1.0.0

- 发布正式版。
- 支持豆包和 DeepSeek 双模式选择。
- 豆包支持语音页面唤起。
- DeepSeek 支持长按录音、松开发送。
- 保留音量键加关机键的系统关机/SOS 操作。
- 移除测试日志输出。

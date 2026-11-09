# AiPowerButton

## 当前发布包：1.0.6

已按用户确认工作的test10相机逻辑重建RootHide无诊断发布包，版本和Preferences字段同步1.0.6。
日志调用及参数构造、测试Hook编译排除；包/性能审计见RELEASE_1.0.6.md。
1.0.6已安装到用户12mini并重载，包文件/加载代码/偏好/4份隔离策略回读通过；尚未上传发布。
旧诊断日志在重载后未变化，发布版真实按键仍待用户复验。以下test8及更早内容是历史记录。
相机按键无闲置轮询；原AI录音期间仍有有限松键检查，不能称整插件零轮询或零耗电。

适用于 iOS 16 Dopamine rootless 与 RootHide 越狱环境的侧边键快捷插件。安装后可以在系统设置的 `AiPowerButton` 中选择长按关机键启动豆包或 DeepSeek 语音助手。

## 功能

- 长按关机键启动语音 AI 助手。
- 设置中可选择启动应用：豆包或 DeepSeek。
- 默认启动豆包。
- 豆包模式：长按关机键开始语音输入，松开关机键后结束录音并发送。
- DeepSeek 模式：长按关机键开始语音输入，松开关机键后结束录音并发送。
- 保留系统原始操作：音量键加关机键仍会触发 iOS 原生关机/SOS 界面。
- 正式版已关闭测试日志和自动验证逻辑。
- 新增候选功能：双击侧键或音量下键打开相机，独立开关默认关闭，设置放在 AiPowerButton 内而不是音量插件。

## 当前开发候选（1.0.6~test8）

- test8将实体Home选项替换为音量下键，移除Home hook；侧键相机与原长按AI链路保留。
- 音量下在0.45秒内完成两次短按松开，每次按住不超过0.25秒；原音量按下/松开事件全部放行。
- 不新增轮询或定时器；音量上、侧键、取消/锁状态/偏好变化、录音与未知接口会清除或拒绝识别。
- 旧cameraTrigger=home在内存中解释为替换后的volumeDown，不直接改写设备偏好文件。
- 实体Home原动作不再接管；不是静音音量键，两次按压仍会调低音量。
- test8构建/验证结果与安装状态见tests/VALIDATION.md；没有物理按压证据时不宣称实机通过。
- 2026-11-09用户授权后test8已安装并重载SpringBoard；包文件、加载代码和4份隐根隔离策略回读。
  现有cameraTrigger=side和其他偏好保持不变。要使用新按键，在触发按键里选择“音量下键”。

### test7历史记录（保留原文）

- 2026-11-09 当前安装 RootHide 候选 1.0.6~test7，关闭诊断输出；长按 AI/侧键双击相机已开启，DeepSeek 保留，锁屏相机保持关闭。1.0.5 稳定包保留回滚。安装回读一致，隔离配置未改变；最新包按键回归及锁屏安全未验收，不是正式发布。
- 新开关独立于 AI 长按开关。侧键双击与钱包冲突，实体 Home 双击与多任务切换冲突；启用即选择替代该双击行为，不能保证两种动作同时保留。
- 当前 iPhone 12 mini 没有实体 Home。`Home` 选项针对带实体 Home 的设备，不支持 AssistiveTouch 小白点；必须确认用户实际期望的按键。
- 使用原生双击事件，没有自行轮询按键/时间窗口定时器；关闭时立即放行，录音或音量+侧键保护时放行，重复触发在 0.7 秒内不再次派发。
- test3 将放行/发起相机/吞掉重复事件统一到运行代码真正使用的策略函数。配置更新清空旧防抖时间；9216 组条件组合及 8 个边界/保护优先级用例通过。
- test4 实机定位到原生 `_shouldWaitForDoublePress` 返回 false，双击执行回调未触发；test5 在相机快捷键启用且无电源/录音保护时请求原生等待双击。
- test6 定位并修复 SpringBoard 的 CFPreferences 与 RootHide 偏好文件读取不一致；按设置变化读取一次 jbroot 快照，不在按键回调反复读磁盘。实机已收到双击回调并派发相机，test7 将原长按 AI 也统一到相同快照。
- test7 默认编译关闭有限诊断输出；诊断构建需显式 `AYCAMERA_DIAGNOSTICS=1`。独立有限按键事件工具源码在 tests/camera_button_probe.m，仅在已解锁且密码关闭时运行，不自动解锁。
- 当前屏幕截图已证明经系统按键事件链双击后相机完整前台；这不等于所有硬件手势/锁屏隐私已验证。用户自行改回锁屏相机关闭，恢复时仅开启长按 AI/双击相机，未改变锁屏选项。
- 未锁定时请求系统打开相机；锁屏选项默认关闭，启用时只请求系统原生受限锁屏相机，不调用解锁/认证绕过 API。返回成功表示请求派发，不等于相机已经前台。
- 私有方法逐项检查签名，不匹配放行；没有在插件构造时创建锁屏管理单例。Home 的轻触两次（Reachability）不是按压双击，没有接管该手势。
- 已通过触发策略 C 测试及两目标环境构建。未实测真实双击、锁屏照片访问限制、三击/SOS 和原长按 AI 回归，所以保留 test 版本号。

构建同一套源码：

```sh
make THEOS="$HOME/theos" THEOS_PACKAGE_SCHEME=rootless clean package FINALPACKAGE=1
make THEOS="$ROOTHIDE_THEOS" THEOS_PACKAGE_SCHEME=roothide clean package FINALPACKAGE=1
```

RootHide 必须使用官方 roothide/theos 且已配置 SDK 16.5。本次工具链提交为 `958fea4f779943505b15b93c88bb4db8d97b346d`。

## 兼容环境

- iOS 16
- Dopamine rootless / RootHide 越狱
- arm64 / arm64e 设备
- 需要 `mobilesubstrate` 和 `preferenceloader`

## 安装

当前稳定版是 `packages/ayao.aipowerbutton_1.0.5_iphoneos-arm64.deb`。RootHide 设备使用 RootHide 官方 Theos 原生构建的 `iphoneos-arm64e` 包。安装完成后需要重载 SpringBoard。

`packages/` 保留 1.0.5 两种目标环境的包及 1.0.4 普通 rootless 回滚包。1.0.2、1.0.3 和 1.0.4~test1 至 test10 的旧包已按用户要求清理；下方历史记录不表示对应包仍保留。

> 如果设备上已经安装旧包 `com.ayao.doubaopowerbutton`，请先卸载旧包后再安装新版；新版 package id 为 `ayao.aipowerbutton`。

## 使用方法

1. 打开系统设置。
2. 进入 `AiPowerButton`。
3. 开启插件。
4. 在「启动应用」中选择「豆包」或「DeepSeek」。
5. 单独长按关机键触发所选语音助手。
6. 如果需要使用系统关机/SOS，按音量键加关机键即可，插件会自动放行系统原始行为。

## 版本说明

### 1.0.5

- 启动 App 改为由 SpringBoard 直接调用 FrontBoard 服务，不再依赖固定的 `/var/jb/usr/bin/uiopen` 路径。
- 保持原有 SpringBoard、豆包与 DeepSeek 三个精确 Filter，兼容 Dopamine rootless 与 RootHide 随机越狱根路径。

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

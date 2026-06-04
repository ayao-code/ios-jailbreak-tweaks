# AirPodsAutoNoise

AirPods Pro 系列自动降噪稳定版，适用于 iOS 16 Dopamine rootless 环境。

当前版本：v1.0.0

## 功能

- 只注入 SpringBoard。
- 识别当前输出设备是否支持主动降噪和通透。
- 默认戴上/连接 AirPods 不主动开启降噪。
- 播放开始后立即切主动降噪。
- 停止播放后立即切通透。

## 安全边界

- 不注入 `bluetoothd`、`mediaremoted`、`mediaserverd`。
- 不 hook MediaControls / MRU 深层对象。
- 不做高频轮询。
- 播放状态未知时不切通透。
- setter 失败后进入抑制窗口，遇到下一次播放/路由变化事件可提前重试，避免死等。

## 日志

日志路径：`/var/mobile/Library/Logs/AirPodsAutoNoise.log`

日志有大小上限，默认只记录关键状态迁移和错误。

## v1.0.0 Release

- 基于 v0.4.0 低日志正式候选版发布。
- 保留播放切 ANC、暂停后按设置行为处理、set 后 verify/retry、切歌/结尾抖动过滤、设置页和日志滚动。
- 仅保留正式插件目录；实验探针/CLI/一次性验证包均不作为发布内容。

## v0.4.0 变更

- 收敛为低日志正式版：默认不再打印每条 NowPlaying 详情和 reconcile 详情。
- 保留日志滚动：`AirPodsAutoNoise.log` 超过上限后转存为 `AirPodsAutoNoise.log.1`。
- 保留关键日志：启动、播放状态边沿、模式 set、失败、verify 失败/retry、target 出现/消失、切歌过滤。

## v0.3.9 变更

- 对被识别为切歌/结尾抖动的 Stopped 事件增加 1.5 秒二次确认。
- 如果二次确认时仍 Stopped 且最近 rate=0，再执行暂停后行为；如果期间恢复 Playing，则取消通透切换。

## v0.3.8 变更

- 停止确认执行时再次判断 `rate=1` / 接近结尾，避免 NowPlayingInfo 晚到导致假暂停漏判。
- 识别为切歌恢复的 Playing 时不再触发 ANC，避免自动下一首抢回手动通透。

## v0.3.7 变更

- 停止播放后增加 300ms 确认窗口；如果期间又出现 Playing，取消本次通透切换。
- 用同一机制缓解汽水音乐切歌假暂停、视频 App 抢占音乐导致的误切通透。
- 保留 v0.3.6 的切歌/结尾抖动过滤和 verify/retry。

## v0.3.6 变更

- 新增切歌/结尾抖动过滤：当收到 Stopped，但最近 NowPlaying 仍显示 `rate=1` 或已接近歌曲结尾时，不再按暂停处理为通透。
- 保留 set 后 verify/retry，用来确认 ANC/通透最终是否真的生效。

## v0.3.2 变更

- 自动逻辑改为播放/暂停边沿触发，不再在同一播放状态下持续压模式。
- 手动切换 AirPods 模式后，插件不会立即抢回；直到下一次真正播放或暂停事件才重新接管。
- route/pickable-routes 通知不再导致同一停止状态下重复切通透。

## v0.3.1 变更

- 新增设置页：启用插件、暂停后行为。
- 增加智能恢复：如果因为系统拒绝而进入 suppress，下一次播放开始或路由重新识别到目标设备时会提前解除 suppress 再试。

## 设置页

- 启用插件
- 暂停后行为：切到通透 / 切到普通 / 不处理

## v0.2.1 验证记录

已在 iPhone iOS 16 Dopamine rootless 上验证，重点覆盖汽水音乐：

- SpringBoard-only 注入稳定，连续采样 PID 无变化。
- 默认连接 AirPods 后不主动切降噪。
- 汽水音乐播放开始后立即切主动降噪成功。
- 汽水音乐暂停/停止后立即切通透成功。
- 快速连续播放/暂停时，反向切换不再被 cooldown 阻塞。
- 同向重复通知仍会被 same-direction cooldown 抑制。

## v0.2.0 验证记录

已在 iPhone iOS 16 Dopamine rootless 上验证：

- SpringBoard-only 注入稳定，连续采样 PID 无变化。
- 默认连接 AirPods 后不主动切降噪。
- 播放开始后立即切主动降噪成功。
- 停止播放约 1 秒确认后切通透成功。
- 多轮播放/停止切换均正常。
- 重复通知会被 cooldown 抑制。

## v0.1.4 验证记录

已在 iPhone iOS 16 Dopamine rootless 上验证：

- SpringBoard-only 注入稳定，连续采样 PID 无变化。
- AirPods `YAP2` 被识别为支持主动降噪/通透的目标设备。
- 连接/路由出现后可自动切到主动降噪。
- 快速播放/暂停抖动时不会立刻切通透。
- 停止播放超过 3 秒后切通透成功。
- 再次播放后切回主动降噪成功。
- 重复通知会被 cooldown 抑制。

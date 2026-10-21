# lap-diagnose

仅用于 LockAudioProfiles 实机验证，不包含在正式 deb 中，也不常驻后台。

- `state`：读取锁定状态、媒体/铃声音量、系统响铃/静音震动和插件开关。
- `configure-test`：写入“锁屏 60% 且震动开启、解锁全静音”的测试配置。
- `silence on|off`：切换控制中心总静音使用的同一偏好与 Darwin 通知。
- `lock`：调用一次系统锁屏，不执行或绕过解锁认证。
- `set-volume ringer|media value`：测试系统对应音量类别的写入和读回，`value` 范围为 0 到 1。

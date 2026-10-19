# llp-diagnose

仅用于 LockLowPower 实机验证，不包含在正式 deb 中，也不常驻后台。

- `state`：读取系统锁定状态和低电量状态。
- `lock`：调用一次系统锁屏动作。
- `wake`：调用一次系统亮屏动作，不执行或绕过解锁认证。

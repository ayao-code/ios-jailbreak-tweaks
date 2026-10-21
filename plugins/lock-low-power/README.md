# LockLowPower

锁屏完成后开启系统低电量模式，只有系统确认 UI 已解锁后才关闭低电量模式。

## 实现

- 仅注入 SpringBoard。
- 直接 Hook `SBLockScreenManager._reallySetUILocked:`，只响应系统最终提交的 UI 锁定状态事件。
- 每次事件读取一次 `SBLockScreenManager.isUILocked`，避免亮屏或 Face ID 过程中的原始通知瞬变被误判为已解锁。
- 通过 iOS 16 的 `LowPowerMode.framework` 调用 `_PMLowPowerMode`，只在目标状态变化时执行一次。
- Hook 回调直接使用当前 `SBLockScreenManager` 实例，不调用其 `sharedInstance`，避免单例初始化的 `dispatch_once` 重入导致 SpringBoard 崩溃。
- 设置首页直接提供“锁屏自动低电量”总开关，默认开启，不需要进入二级页面。
- 首页条目保留独立电池图标，不再在名称前显示闪电字符。
- 关闭开关只停止后续自动控制，不修改用户当前的低电量状态；重新开启后在下一次真实锁定状态变化时生效。
- 插件记录低电量模式的“所有权”：只有锁屏前低电量原本关闭、并由插件成功开启时，解锁后才由插件关闭。
- 如果锁屏前低电量模式已经由用户手动开启，插件不会取得所有权，解锁后保持开启。
- 仅为设置变更注册一个 Darwin 通知，没有定时器、轮询、常驻工作线程、文件 I/O 或网络请求。

锁屏密码页仍属于锁定状态，因此输入错误密码、只点亮屏幕或停留在锁屏界面都不会关闭低电量模式。只有 Face ID、Touch ID 或密码认证完成，系统锁定状态变为未锁定时才关闭。

## 旧插件参考结论

开发前从设备上导出并静态分析了 `com.hoangdus.lowpowersleep 0.0.1-1`。旧插件 Hook `SBSleepWakeHardwareButtonInteraction._playLockSound` 触发开启，并 Hook `SBCoverSheetPrimarySlidingViewController.viewWillDisappear:` 推断解锁。锁屏声音和界面消失都不是严格的锁定状态事件；它依赖的 `_CDBatterySaver` 在当前 iOS 16.3 SpringBoard 中也不存在。本实现不复用这些 Hook 或旧接口。

## 1.0.3 安全模式根因

`1.0.3` 在 SpringBoard 启动期间调用 `SBLockScreenManager.sharedInstance`。当系统正处于该单例自身的 `dispatch_once` 初始化过程时，这个调用形成同线程重入，最终触发 `_dispatch_once_wait.cold.1` 的 `EXC_BREAKPOINT / SIGTRAP`，导致 SpringBoard 连续崩溃并进入安全模式。

`1.0.4` 删除 SpringBoard 启动同步和全部 `SBLockScreenManager.sharedInstance` 调用。状态提交 Hook 只使用当前 `self`，因此不会进入该单例初始化路径。失效的 `1.0.3` 安装包不再保留，避免误装。

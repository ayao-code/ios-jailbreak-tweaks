# 一次性显示观察工具

用于用户授权的 14PM 自动验证，尝试通过 UIKit 截图接口读取当前显示。它不是 tweak，不注入或附加任何 App，不常驻，不监听网络，不模拟触控，不写设备文件，PNG 只输出标准输出。

构建使用 iPhoneOS SDK。默认 `minimal` 变体仅 ad-hoc 签名，没有额外 entitlement。无权限变体实机读取失败后，新增 `display` 变体只给独立工具加入 platform-application、IOSurfaceRootUserClient、QuartzCore.global-capture；没有 no-sandbox、task-port、调试、账号、容器或触控权限。这些是临时工具的签名内容，不修改系统 entitlement 文件。不得把该执行路径当成普通 App 沙盒验证。

截图 API 为私有接口，可能返回空图像或拒绝请求；UIKit 返回空图时，仅尝试一次向工具自己创建的 IOSurface 渲染 LCD，声明参考 CoolStar/RecordMyScreen 提交 `74fca3290542a1b4c7731c0e6715d37d574a2d36` 的 `CSScreenRecorder.m`。没有复制录制器、VNC 服务或触控代码。空白渲染不算成功截图。编译成功不代表当前 iOS 可用，不继续添加无关权限或 Hook 系统服务。远端只放入独立的临时测试目录，不替换已安装文件。

```sh
bash tools/screen-observe/build.sh
bash tools/screen-observe/build.sh display
```

调用者应设置 `_SafeMode=1`、`_MSSafeMode=1` 限制该工具的现有注入链，并对执行设置超时。截取结果只用于当次界面观察，不把账号或画面内容写入公开研究报告；出现无结果即保留失败事实，不盲点界面。

`--state` 只调用 `SBGetScreenLockStatus` 查询锁屏/密码是否启用，不尝试解锁、亮屏或读取密码。声明参考 Theos `SpringBoardServices.h`；查询无有效返回则失败，不默认认为手机已解锁。

`--wake` 只请求 `SBSUndimScreen` 唤醒显示，不解锁，不关闭自动锁定。返回成功只说明调用已发出，真实界面仍须截图确认；锁屏存在时不得绕过。

`--render` 用于显式比较 IOSurface 渲染和默认 UIKit 截图路径。实机强制渲染曾得到不完整画面，不能用于导航或视为新的可靠截图通道；默认 UIKit 路径可观察完整界面。两条路径的返回 0 都不能替代内容核对。界面会自行变化，调用者需对操作前的新图与已核对图做稳定性检查。

# 一次性 UI 输入工具

`SDP_INJECT_MANAGER_UI=1` 仅允许 `cn.zqbb.inject.manager` 前台点按和滑动，用于用户授权的进程注入开关设置。它不是 `com.roothide.manager` 黑名单界面；仍核对未锁定、精确前台及新截图，不直接写配置、不注入或附加进程、不操作业务 App。

`SDP_ALI_RESTORE_UI` 构建变体仅允许 App Store 和 RootHide Manager 前台点按、滑动，用于用户授权的阿里系正版 App 下载及原生黑名单开关操作。仍逐次检查锁屏、前台和新截图；不允许业务 App 点按、不输入凭据、不处理付费购买、不直接写 RootHide 配置、不 Hook 或注入 App。默认构建的允许名单保持不变。该变体尚需在当前设备验证，不因为旧版本能发送事件而推断兼容。

`SDP_COUPON_TEST_UI=1` 构建变体仅允许 Safari 的“在淘宝中打开”系统确认框及淘宝前台点按，用于用户明确授权的领券业务验收。每次输入前仍需核对实时截图、未锁定状态和精确前台 Bundle ID；不提供键盘输入，不操作购买、支付或订单，不向淘宝注入、Hook、附加调试器或写入其沙盒。验收结束必须通过 TrollStore 官方路径卸载一次性助手。

`build-coupon-helper.sh` 将该变体和只读截图工具封装为独立的 `com.ayao.couponuihelper`，避免覆盖 App Store/RootHide 恢复专用助手。它只用于验收期间关闭普通弹层、打开已核对入口和查看后续页面；真人滑块、验证码、登录、购买、支付及订单操作均不自动处理。

`SDP_QUNAR_TEST_UI=1` 与 `build-qunar-helper.sh` 只允许去哪儿旅行 `com.qunar.iphoneclient8` 前台的点按和滑动，用于复现机票搜索错误。每次输入前仍须确认未锁定、精确前台 Bundle ID 和最新截图；不提供键盘输入，不登录、不下单、不支付、不修改其沙盒，也不 Hook、注入或附加调试器。验收结束必须通过 TrollStore 官方路径卸载 `com.ayao.qunaruihelper`。

`SDP_SETTINGS_UI=1` 只允许系统设置 `com.apple.Preferences` 前台的点按和滑动，用于通过 Apple 原生设置界面执行已核对的临时系统开关对照。它不允许操作业务 App，也不直接修改任何配置文件。

`build-settings-helper.sh` 将该变体与只读截图工具封装为独立的 `com.ayao.settingsuihelper`。验收完成后应通过 TrollStore 官方路径卸载。

`SDP_DAMAI_TEST_UI=1` 与 `build-damai-helper.sh` 只允许大麦 `cn.damai.iphone` 前台的普通点按和滑动，用于复现登录跳转错误。它不提供键盘输入，不读取或写入大麦沙盒，不 Hook、注入、附加调试器，也不处理账号、验证码、购票或支付。验收完成后应通过 TrollStore 官方路径卸载 `com.ayao.damaiuihelper`。

`--network-status` 只读输出当前 IPv4/IPv6 接口名，以及 `CFNetworkCopySystemProxySettings()` 的顶层键和 `__SCOPED__` 接口键。`damai_vpn_matches` 精确复现大麦 `9.0.37` 的 `ALBBLoginUtils.useVPN` 对 `tap`、`tun`、`ppp` 的大小写敏感匹配；输出不包含 IP、代理地址、账号、Cookie 或业务 App 数据。

`--unlock-no-passcode` 只用于用户明确关闭系统锁屏密码后的无人值守验收。它必须实时读到“当前已锁定且 `passcode_enabled=false`”，随后在一次进程内短按侧边键、等待 0.6 秒、再次确认密码仍关闭并发送一次系统正常上滑，最后读取锁定状态确认结果；只要密码开启、状态不可读或状态中途变化，就拒绝发送输入。亮屏与上滑保持在同一原子操作内，避免短自动锁定时间让分步操作重新熄屏。它不输入、猜测或绕过任何密码，也不处理 Face ID、Touch ID、验证码或其他身份认证。

`--wake-power-button-no-passcode` 使用同一实时门槛，只在“当前已锁定且 `passcode_enabled=false`”时模拟一次短按侧边键，用于 `SBSUndimScreen` 无法实际点亮显示的设备；它只请求点亮屏幕，不执行上滑或解锁。调用前后仍须用只读截图和锁定状态分别验证，禁止连续盲发侧边键事件。

`ali-helper-info.plist` 是该变体的临时 TrollStore 封装元信息。主可执行文件来自本目录 `main.m`，附带截图可执行文件来自 `../screen-observe/main.m`；没有后台任务和网络服务。普通临时二进制被当前 RootHide 拒绝执行时，才尝试用目标已有的 TrollStore 签名安装这个独立助手；不放入任何目标 App 沙盒。操作结束通过 TrollStore 官方卸载路径移除助手，保留源码和本次记录。

用户授权自动测试 14PM 后，仅用于截图已核对的系统设置导航及淘宝普通界面。它不 Hook、不向目标进程注入、不读取账号、不提供键盘输入或解锁功能，没有常驻或网络服务。

用户改用大麦进行对照后，`--check cn.damai.iphone` 仅用于只读确认前台与未锁定状态。它不发送输入，未将大麦加入点按/滑动允许名单；大麦策略调整仍只在系统设置官方界面进行。

一次运行发送一个点按或有限 12 步滑动，坐标范围为 0 到 1；必须先用只读 `SBGetScreenLockStatus` 确认设备未锁定，再独立确认前台 bundle 为 `com.apple.Preferences` 或 `com.taobao.taobao4iphone`，否则不发送输入。锁屏接口缺失、无服务端口或未回写未锁定状态均拒绝操作。它不提供解锁能力，设备锁定时必须由用户完成正常系统认证。不能因为前台确认就点击未核对的按钮，更不能操作购买、支付、领券提交、删除或账户变更。

签名仅包含 platform-application、HID event-dispatch 和 `com.apple.frontboardservices.display-layout-monitor`。最后一项由目标设备系统设置可执行文件的原始签名核对，仅为临时工具获取前台布局添加，不修改任何系统签名文件。IOHID digitizer 声明及流程参考 julioverne/screendump 提交 `c0cb872905358b1955533b1d3bfb3fd95b4c0294` 的 `main.mm` 和 iolate/SimulateTouch 提交 `91267d6b9b37be0ee8ec5b6426d636220f7caecb` 的 `SimulateTouch.mm`；现代 hand transducer 为 3。不复制它们的 Hook、VNC 或后台循环。

返回 0 只说明发送了请求，必须重新截图证明控件响应；不能把事件 API 返回当作成功操作证据。坐标验证失败、前台无法确认或任何截图失效时停止，不盲重试。

旧 SpringBoardServices 前台接口在本机返回空值，不代表没有前台 App。fallback 使用 FBSDisplayLayoutMonitor 的默认主显示器配置，要求恰好一个 UIKit 应用具有键盘焦点，且其 bundle 与期望一致；0 个、多个、非目标或无布局都拒绝输入。订阅只存活约半秒，取回布局即 invalidate。禁止用旧 `setHandler:`：本机它触发临时工具 SIGTRAP，崩溃栈已定位；修复为 configuration 的 transitionHandler 后未再产生该工具崩溃。声明参考 MTACS iOS-17-Runtime-Headers 中对应类，只使用运行时存在的方法，头文件不是兼容证明。

本机 arm64 / iOS 16.0 编译和精确签名检查通过。实机已验证非法坐标、非允许目标、参数数量与操作不匹配及锁屏均拒绝发送事件；设置前台正例和淘宝前台负例只输出布尔值、不泄露其他前台 App 标识。有效滑动、点按、官方 Choicy 导航及禁注入开关写回已由新截图与配置回读证明，不代表任意 App 自动化已验证。

Host `screen-text.swift` 使用 Vision 离线识别页面标题和目标行，仅传本机截图；原始截图/识别结果不上传。`ui-action-14pm.py` 发事件前比对最后已查看截图与两张新截图的主体区域，排除会变化的状态栏和滚动条，界面变化/不稳定即拒绝。`choicy-text-navigation-14pm.py` 只允许固定 Choicy 导航目的，精确标题和行文本两次确认；扩展长英文名称 OCR confidence 可能为 0.5，仍需精确匹配已盘点可执行名、稳定坐标和点击后标题核对。

`disable-choicy-extension-14pm.py` 只处理已盘点的7个淘宝扩展；每项操作前验证最新双端备份与所有已落地目标差异、精确页面标题，操作后对整个 Choicy 对象做语义比较。正文中的位置常量仅适用于已验证的14PM/iOS16设置布局，不作为其他设备的通用坐标，也不提供直接写 plist 的后备路径。OCR失败、页面变化或非目标差异即停止，不能自动放宽匹配。

此前有滚动继续移动和界面自行返回桌面的现象，少量导航进入相邻项；这些页面没有修改开关，随后完整配置语义核对证实非目标键未变。不得以单次截图中的坐标对后续画面盲点；需要新图、前台、锁屏、稳定性与目标标题共同确认。检测到画面变动后只更新截图，不自动重试事件。

```sh
bash app/safe-domain-probe/tools/ui-input/build.sh
xcrun swiftc app/safe-domain-probe/tools/ui-input/screen-text.swift -O -o app/safe-domain-probe/build/screen-text
SSH_CONTROL_SOCKET=<existing-authorized-socket> python3 app/safe-domain-probe/scripts/ui-action-14pm.py capture
```

`SDP_HZ_TEST_UI` / `build-hz-helper.sh` builds an independent SMS/WeChat-only
console helper for authorized frame-rate tests. It never injects into either
application. The normal variants' allowlists are unchanged. `swipe-slow` and
`swipe-fast` traverse the same distance over about 1.8 or 0.18 requested seconds,
with 4-ms pacing; measured elapsed time includes dispatch/scheduling overhead.
Only this variant emits monotonic touch start/end times and event counts. Each
input still requires a confirmed unlocked device and exact foreground bundle;
the host must confirm a fresh stable list view, not a conversation or action
screen. Actual synthetic touch behavior is not equivalent to human input.

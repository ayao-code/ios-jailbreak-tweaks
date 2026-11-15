# Easy VPN 外部连接可行性检查

## 结论

2026-11-14，iPhone15,3 / iOS 16.3 / RootHide，Easy VPN 2.1.0（14）：

- 最初系统直接启动目标 VPN 配置：实测 2 次，均未连接成功。
- 这不是“Easy VPN 完全不能做一键连接”的结论，也不是控制中心真实触控验收。
- 用户后续确认 App 原生手动连接可用，但没有取得该次手动操作的系统实时
  成功 readback。原生入口适配、控制中心长按菜单及网络业务访问均未验证。

## 手动连接确认后的补充检查

- 用户原话：“没问题，可以连上。”
- 08:23 回读时两份 VPN 均已断开，Easy VPN 的 enabled 从 0 变为 1，
  飞连从 1 变为 0；本轮没有主动修改这两个配置选择值。
- 相同独立工具第一次系统直连：约 0.020 秒观察到 connected=1，经历短暂
  状态变动，15 秒最终仍 connected=1。没有通过工具打开 App 界面。
- 随后调用目标断开成功，再次直接连接时，15 秒后仍 status=2 / connected=0。
  因此第一次观察不能证明稳定一键连接，也不能排除既有会话、异步状态加载
  或用户操作时序影响；“选择 Easy VPN 即可解决”尚未成立。
- 两次目标断开请求最终都达到断开状态；08:26 最终独立回读确认 Easy VPN
  和飞连均 connected=0，选择值仍为 1 / 0，临时工具已移除。
- 本轮网络请求未执行成功：手机无 curl 等现成工具；未安装依赖，不把
  connected=1 当成网络业务访问通过。未验证 App 前后台变化或弹窗状态。
- 当前可用结论是“App 手动连接可用（用户确认），系统直接连接不稳定
  （独立探测）”。建议后续验证 App 原生连接准备流程，而非直接发布系统开关。

## 已确认事实

1. 目标 App 为 `com.qdtiktok.easyvpn`；系统中只有一份对应 VPN 配置，
   `isProviderAvailable=1`。测试前后 Easy VPN 和飞连均为断开状态。
2. App 的 Info.plist 未声明 CFBundleURLTypes、NSUserActivityTypes 或
   INIntentsSupported。仅说明本版本没有这些声明，不证明不存在其他入口。
3. App 有 tunnel、tunnel2、tunnel3 三个 packet-tunnel 扩展。
4. 独立诊断工具通过 VPNConnectionStore 精确匹配目标，调用 `connect`；
   使用系统状态通知及固定 15 秒观察窗口，不运行持续状态轮询。
5. 第一次连接中事件在约 0.028 秒出现，约 0.030 秒回到断开；第二次分别
   约 0.029 秒和 0.031 秒。两次最终 `connected=0`、`target_reached=0`。
6. 静态分析发现 ViewController 原生连接流程涉及 prepareManager、
   switchVPNState、节点选择、refreshAndStartVPN 和 enableVPN；
   最终调用 `startTunnelWithOptions:andReturnError:`。系统直连失败与缺少
   App 准备步骤或启动参数有关是待验证假设，不是已查明根因。
7. 当日 07:59 有目标 tunnel 扩展的 EXC_BAD_ACCESS / SIGSEGV 报告，
   早于本次 08:13 起的连接试验；本次检查未发现新增目标扩展或
   SpringBoard 崩溃报告。既有崩溃不能归因于本次测试。

## 边界与后续

- 无插件安装、App 注入、沙盒写入、凭据读取、RootHide 配置修改或认证绕过。
- 其他活动 VPN 存在、目标匹配不唯一或未确认解锁时，诊断工具拒绝连接。
  本次仅执行已解锁、无活动 VPN 的场景，其他拒绝场景未实机测试。
- Easy VPN 配置的 enabled 值原为 0，本次未改动；未验证通过系统选择或
  启用配置后行为是否不同。不要把本次 `connect` 失败外推为所有系统路径失败。
- Mobile GUI 自动化前置检查返回 mobile_not_authorized，未执行 App UI 测试，
  未绕过该门禁；本记录不宣称标准 SDT 或 GUI 全流程验收通过。
- 下一步取得 App 原生手动连接的独立系统成功基线，再验证明确的原生
  入口适配。若需新增 App 专用辅助注入或安装，应先取得用户确认；
  不得跳过 App 自身的登录、权限或付费判断。

## 可重建诊断工具

源码为 `tools/easy-vpn-probe.m`，不加入正式控制中心 bundle 或 tweak：

```sh
xcrun clang -target arm64-apple-ios16.0 \
  -isysroot "$HOME/theos/sdks/iPhoneOS16.5.sdk" \
  -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-unused-parameter \
  -framework Foundation plugins/feilian-control-center/tools/easy-vpn-probe.m \
  -o /tmp/easy-vpn-probe
ldid -Splugins/feilian-control-center/tools/background-entitlements.plist \
  /tmp/easy-vpn-probe
```

`--read` 只读状态；`--connect` / `--disconnect` 会操作目标 VPN，必须在获得
用户授权并核对当前状态后使用。测试后移除设备上的独立临时工具。
原始 App 文件和含设备标识的日志仅保留在 Mac 私有临时目录，不进入仓库。

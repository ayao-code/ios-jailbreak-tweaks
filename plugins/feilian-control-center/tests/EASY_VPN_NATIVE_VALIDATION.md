# Easy VPN 原生外部触发实测

## 结论

2026-11-14，iPhone13,1 / iOS 16.3.1 / RootHide / Easy VPN 2.1.0：
**可以通过一次外部请求调用原生连接流程，且已验证重复连接与断开。**
这证明控制中心可复用的连接后端主路径，不是控制中心按钮或长按菜单已交付。

## 有效证据

用户通过官方 App List 开启 easyvpn 注入，辅助 Filter 只有
com.qdtiktok.easyvpn。本轮未修改 RootHide 策略、目标 App 文件或配置，
未使用 opainject、trustcache、调试标记或 GUI 输入。

| 检查 | 原生请求耗时 | 系统与网络结果 |
| --- | --- | --- |
| 完整断开 1 | 0.406 秒 | 已连接变为断开，辅助与系统一致 |
| 完整重连 1 | 4.229 秒 | connected=1；HTTPS 200 / Success；15 秒后仍连接 |
| 完整断开 2 | 0.406 秒 | 已连接变为断开，辅助与系统一致 |
| 完整重连 2 | 4.252 秒 | connected=1；HTTPS 200 / Success；15 秒后仍连接 |
| 冷启动后台连接 | 5.727 秒 | 目标 App 退出后重新后台启动，connected=1；HTTPS 200 / Success；15 秒后仍连接 |
| 后台断开 | 0.406 秒 | connected=0；飞连保持断开 |
| 后台重连 | 4.291 秒 | connected=1；HTTPS 200 / Success；15 秒后仍连接 |
| 最终后台断开 | 0.613 秒 | connected=0；飞连保持断开 |

计时从启动请求派发后的等待阶段起算，不包含约 6 秒诊断预热或完整界面
过渡开销，不能当作真实控制中心触控延迟。
HTTPS 检查为 Apple success 页面；只证明连接期间设备请求可用，未验证
VPN 出口或特定企业/区域资源，也不证明该请求必定由 VPN 转发。

## 探测修正与未验证范围

- 系统 VPNConnectionStore 在首次枚举后异步刷新对象。早期探测曾因仅等待
  框架初始化、不预热枚举而出现假断开。已修正为有限预热后再读取；上表
  两轮完整循环仅使用修正后结果，早期成功不计为有效完整循环。
- 所有连接调用原生 startButtonClick:，没有直接跳过前置判断调用 startVPN，
  不复制或构造 tunnel options。原生提示正常转发。真实认证过期、付费拒绝、
  权限弹窗、锁屏中途变化、其他活动 VPN 正例未实测。
- 后台启动选项生效且连接成功；旧前台查询和新增显示布局查询均未给出
  可靠前台结果，因此“完全不切前台、不弹界面”尚未验收。
- 此版本仍是短时试验辅助。请求超时后的 App 原生异步任务取消、长期
  CPU/内存/耗电、跨 App/iOS 版本、安全失败恢复均未验收，不直接发布。
- Mobile GUI 权限门禁尚未满足，没有操作真实控制中心或绕过 GUI 门禁。
  SDT Custom 发现缺少注册配置，未完成标准目标/策略/报告流水线；独立实测
  不冒充完整 SDT 通过。

## 清理及隔离回读

- ayao.easyvpnnativehelper 卸载成功，目标 dylib、Filter、临时包和独立
  probe 均不存在，目标 App 退出以卸载进程内辅助。
- 最终独立查询 Easy VPN、飞连均 status=1 / connected=0 / active=0。
- RootHideConfig.plist、cn.zqbb.inject.plist、cn.zqbb.inject.system.plist、
  cn.zqbb.inject.wantsblacklist.plist 与本轮开始时字节一致。
- 用户新开启的 easyvpn 允许项保留，不恢复到旧轮次未开启状态。
- 目标 App 主可执行文件与本轮前已下载原文件字节一致，未观察到本轮
  新增 Easy VPN、tunnel 或 SpringBoard 命名崩溃报告。
- 本轮没有新增信任缓存操作；之前轮次 trustcache add 的副作用未重新审计，
  不将本轮清理误写为整个设备零残留。四份策略备份保留。

## 下一步

在现有飞连项目中加入 Easy VPN 连接适配，保持一个控制中心模块：默认
Easy VPN，长按选择目标。接入时复用事件状态与异步请求，不在 UI 回调同步
等待约 4-6 秒连接；不允许无确认替换其他活动 VPN。
该功能尚未实现，本次没有改动飞连正式 bundle/tweak 或其安装包。

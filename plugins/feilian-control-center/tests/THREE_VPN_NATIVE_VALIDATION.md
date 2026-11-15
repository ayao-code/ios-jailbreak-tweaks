# 三个新增 VPN 原生入口独立验证

日期：2026-11-14。目标：iPhone13,1 / iOS 16.3.1 / RootHide。
**Hotspot 主路径已测通；GOFast / Jump 尚未完成连接验证，未接入正式菜单。**

## 目标与最新前提

| App | Bundle | 版本 | 原生配置 |
| --- | --- | --- | --- |
| Hotspot VPN | co.hotspot.vpn.security | 2.0.2 | 唯一 VPN 配置，扩展可用 |
| GOFast VPN | com.bestapp.gofast.vpn | 1.4.0 | 唯一 VPN 配置，扩展可用 |
| Jump VPN | com.zenith.jump | 1.1.0 | 唯一 VPN 配置，扩展可用 |

用户通过官方 App List 开启三个 App 注入，本轮回读准确 executable 允许值
均为 1。测试开始五份系统 VPN 均断开。本轮没有改 RootHide 策略，没有
使用 opainject、trustcache、调试标记或 GUI 点击；独立测试包只匹配三个
明确 Bundle，不包含高敏 App、SpringBoard 或隧道扩展。

## Hotspot 有效结果

- 真实 ViewController 的 UIButton 绑定 startBtnClick / stopBtnClick；原生
  连接入口保留 doStart / prepareStartVPN 的原有提示、付费和节点判断。
- 两次独立原生连接请求均在 20 秒观察末尾由 App manager 返回 status=3。
  独立系统查询确认 Hotspot connected=1，其他四份 VPN 均断开。
- 两次连接期间 HTTPS 200 / 正文包含 Success / errorCode=0。
  只证明连接期间网络请求可用，不证明请求的具体出口或必经隧道。
- 单纯系统 disconnect 约 0.46 秒变为断开，但约 4.69 秒又自动连接，
  20 秒末尾仍 connected=1，不能采用系统停止作为这个 App 的关闭入口。
- 改用原生 stopBtnClick 后两次均返回 status=1；后续独立系统查询均
  connected=0，最后测试清理前仍断开。停止观察为 10 秒，未做长期掉线测试。
- 完成的是前台启动后原生连接/停止，后台冷启动、无切前台、取消安全、
  认证失败、长期稳定性和正式控制中心输入未验收。

## GOFast 未完成项

- 系统 connect 20 秒末尾停在连接中；已停止失败请求，未采用该路径。
- 静态主页面为 HomeScreenViewController，暴露 connectButton。运行时
  当前仍处于 SplashViewController，展示 PaywallOnboardViewController，
  随后展示 UMPConsentViewController。尚未到达连接主页面。
- 只准备了读取原生 closeButton 可用状态并发送其关闭动作的测试能力；
  实际该轮返回 main_controller_unavailable，没有成功关闭页面。
- 隐私/广告同意内容和选择必须由用户处理；不自动接受、不购买、不改会员
  状态、不通过构造主页面或直调连接服务跳过正常准备流程。
- 需要用户进入 GOFast，按自己的意愿处理这些页面，确认能够正常手动
  连接后再验证 connectButton 的原生动作；当前未声称 GOFast 已适配。

## Jump 未完成项

- 系统 connect 短暂连接中后断开；没有采用该路径。
- 已从 SceneDelegate 调用链与运行时交叉确认主页面 ToPreapredListVC。
  storyboard 的 ViewController 不能用作真实主入口。
- skewerBtn → LbaseService.recommenOffset → openURL 是推广链路，已排除。
- 原生连接链路候选为 rewardbarNode: → hideConsumersView:/
  carbonClickConfirmBtn: → TradesService.nikonTarget → 隧道启动。尚未证明
  当前页面哪个原始控件完整进入此链路，connect 测试仍明确拒绝 Jump。
- 运行时页面提供 Get Key / ADD SERVERS；只读 TradesService.adsourceData
  确认当前没有选中节点（hasSelectedNode=0）。没有读节点内容、账号或凭据；
  lines getter 未返回可判定数量，不能断言全库节点数为 0。
- 需要用户在 Jump 内完成正常准备/选择可连接节点并确认手动连接可用。
  不自动购买、获取密钥、填节点或读取凭据，不直调末端网络方法绕过检查。

## 独立测试通道与修正

App 沙盒拒绝 proc_pidpath 对端查询，csops 对端查询也被拒绝。未放宽
隔离或取消身份检查，改为本机 root 监督工具校验内核 audit token / pid
及测试客户端的 CDHash，发布 35 秒有效、root 属主、0644 的短时 permit。
App helper 只读取自身 tmp/vpa1.permit，比较 kernel peer audit token。
permit 是测试 IPC 数据，不是修改 App 设置；退出测试已精确删除。

RootHide 第一次执行会重签名测试客户端。核对设备客户端 __text、
__cstring 和 __objc_methname 与本地构建一致后，监督工具采用设备执行后
稳定的签名哈希作为独立构建输入，不写入正式源码。后续修改客户端须重新
核验并构建监督工具，不能跳过 hash mismatch。此前工具路径判定、
短帧写入、RootHide 文件视角造成的失败不计为 VPN 连接失败。

测试接收端回复采用有限 worker 完整写出帧，不在 App UI 主线程等待 I/O。
状态延迟回调按 peer generation 校验，不能污染下一次请求。原生 App 的
异步网络任务取消仍未验证，此 test 包不可直接作为正式适配器发布。

## 清理与最终状态

- ayao.vpnadapterprobe 已卸载，dylib/Filter、独立客户端、监督工具和临时
  deb 均不存在；三 App 已退出卸载进程内辅助。
- 三 App 的 tmp/vpa1.sock、vpa1.permit 均精确删除并回读不存在。
- 四份 RootHide 策略与本轮开始时字节一致，用户开启的三个注入项保留。
- 五份 VPN 最终均 status=1 / connected=0 / active=0；控制中心 dpkg 回读
  仍为 1.2.0。用户原先那轮 GOFast 连接未恢复，不能称其网络恢复到更早基线。
- 观测窗口未发现新增 Hotspot、GOFast、Jump 或 SpringBoard 命名崩溃；
  本轮有一次独立 authorize 工具崩溃（读取空输入），已增加 nil 防护并
  修正 RootHide 读取路径。不能声称本轮“没有任何崩溃”。

## 剩余交付

GOFast 完成原生隐私准备、Jump 完成节点选择并能手动连接后，分别验证
原生连接、原生停止、至少两轮重连及网络请求。三份适配全部通过才接入
统一控制中心，维持 Easy VPN 默认、飞连和三个新增目标的完整范围。
当前正式候选只支持 Easy VPN / 飞连，三个新增适配和整体功能未完成。
GUI 门禁仍未开放，没有操作真实控制中心，不冒充完整 SDT / GUI 通过。

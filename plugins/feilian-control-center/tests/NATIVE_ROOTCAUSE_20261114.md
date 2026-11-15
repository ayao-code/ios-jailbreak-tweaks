# VPN 原生失败根因诊断：2026-11-14

承接原会话和 NATIVE_RETEST_20261114.md，由代理独立执行。
目标仍为 iPhone13,1 / iOS 16.3.1 / RootHide，正式控制中心保持 1.2.0。

## GOFast：已定位原生 OpenVPN 协商失败

- 正常启动并关闭 App 自己展示的付费引导后，原生连接控件触发成功。
- 独立系统状态仍为 status=2 / connected=0，不计连接成功。
- 系统日志确认 TunnelProvider 扩展成功启动，调用 startTunnelWithOptions，
  创建虚拟接口；因此不能归因于“控制中心没有触发”或“扩展没有加载”。
- App 自有日志确认 OpenVPN core 3.6.1，联系服务器 UDP 1194，已经收到
  Peer Info，证书链 depth=1、depth=0 均 VERIFY OK。
- 随后原生日志明确返回 `Session invalidated: KEV_NEGOTIATE_ERROR`，
  并记录 `Client terminated, restarting in 2000 ms...`。
- NEVPNConnection 的 fetchLastDisconnectError 回调返回空 domain、code=0，
  不能当作没有错误；原生 OpenVPN 日志是本轮有效失败证据。
- 当前只确认失败阶段为 OpenVPN 会话协商。尚未证明具体是协议、密钥协商、
  服务器兼容、选中节点还是 App 客户端缺陷，不修改证书校验、凭据或协议。

## Jump：纠正“没有节点”的早期判断

- 冷启动早期原生 lines 为 nil、hasSelectedNode=0。
- 等待 App 自己完成加载后，lines 为字典，nodeCount=70、hasSelectedNode=1。
- 没有代理填写节点、获取密钥或修改选中项；变化来自 App 原生异步准备。
- 这说明只观察启动前几秒不足以判定永久缺少节点，不再要求用户代做填节点。
- 节点就绪后系统直接 connect 仍短暂 status=2，随后约 0.03 秒回到 status=1；
  20 秒末尾仍断开，REACHED=0，不作为正式连接路径。
- 静态调用链和运行时按钮 block 偏移交叉核对，明确排除推广 URL 控件。
  一个原生导航动作实际发出，但最终仍停在主页、显示 Premium 推广层。
  不能据此认定必须购买，也不能把该导航动作当作原生连接入口。
- 实验导航命令已从最终 test8 源码移除；Jump connect 仍明确拒绝未验证入口。
- Jump 的完整原生连接、停止、重复连接尚未验收；不得直调末端网络方法
  或隐藏推广/付费页面来冒充正常连接。

## 诊断源码和构建

本轮修改仅在 tools/native-onboarding：helper.m 增加有界错误元数据读取、
节点集合类型/数量、已显示推广提示及原生 block 相对偏移；不输出节点、
凭据或 NSError.userInfo。build.sh 支持外部 PROBE_VERSION，默认 test8，
避免覆盖旧 test1 包。源码、control 和对应包均保留在插件项目内。

- arm64 / arm64e 两个 slice 均编译成功并打包。
- test8 是最终诊断源码构建，不是正式多 VPN 适配器；设备实测使用过 test2、
  test3、test5、test6，最终 test8 未重新安装，不将其标记为实机已验收。
- 本轮 superseded test2–test7 包已精确移除；旧 test1 和最终 test8 保留。
- 早期实验导航请求因接收端动作范围检查被拒绝，无回执不计成功；修正后
  才取得原生动作派发回执，仍不等于目的页面或连接验收通过。

## 验证与清理边界

- GUI bootstrap 仍返回 mobile_not_authorized；USB screenshotr 服务不可用，
  没有绕过门禁，也没有真实控制中心点击、长按或视觉验收。
- 独立客户端代码段与设备重签名后代码一致，监督工具绑定设备实际签名，
  未取消 IPC 身份检查，未新增信任缓存操作。
- GOFast 失败请求在退出 App 后停止，最终回读稳定断开。
- 独立测试包已卸载；dylib、Filter、客户端、监督工具、三份 socket 与
  permit 均回读不存在，设备临时包及独立系统探测工具已删除。
- 四份 RootHide 策略与本轮开始时字节一致，目标注入许可未修改。
- 最终五份 VPN 均 status=1 / connected=0 / active=0，正式模块仍为 1.2.0。
- 最近 30 分钟 CrashReporter 顶层匹配 GOFast、Orderidtext、SpringBoard 的
  报告数量为 0；不是完整系统崩溃审计，不宣称无任何崩溃。
- 私有系统/原生日志保存在仓库外、权限 0600；公开记录仅保留错误类型和
  计数，不提交真实节点地址、凭据、设备或容器唯一标识。

## 剩余事项

GOFast 需继续确认 KEV_NEGOTIATE_ERROR 的具体协商失败原因；Jump 需继续
确认正常连接控件及其前置条件。两者尚未测通，多 VPN 正式交付未完成。

# Jump 原生连接与停止续测

日期：2026-11-14；目标 iPhone13,1 / iOS 16.3.1 / RootHide / Jump VPN 1.1.0。
由代理独立操作，正式控制中心仍保持 1.2.0，整体多 VPN 交付未完成。

## 原生入口定位

- 只读真实 UIButton 的 RACPassthroughSubscriber 内部 next 回调，匹配
  App 原生 block 偏移 0x2d898。静态代码确认该 block 调用 toolslRecording，
  后者执行原生节点/状态检查和准备，不直接跳到末端隧道启动方法。
- 连接动作发送原按钮的 TouchUpInside，保留原生广告、权限、节点及付费
  决策。没有填写节点、取得密钥或更改会员、证书、凭据。
- 最初两次原生连接都成功，HTTPS 都返回 200。但第二次用同一按钮停止时
  仍连接，有限重试也无效。因此不能把连接按钮的 toggle 当作可靠停止。
- 静态代码确认按钮会经过广告 completion，已连接分支最终调用
  TradesService.theVersionOpinionatedChanged。该原生方法停止隧道、清理
  原有请求并同步状态，不修改会员或绕过连接授权。
- 独立停止仅在系统 manager 处于 connecting/connected/reasserting 时调用，
  校验准确 App 版本和无参数 void 方法签名；不是强行调用连接末端方法。
- App 原生 clearSringStatus 在某些轮次与系统已连接状态不一致，因此
  不能只信 App 模型。验收始终独立回读 VPNPreferences。

## 独立停止适配后的三轮

| 轮次 | 原生连接/系统回读 | HTTPS | 原生停止/系统回读 |
| --- | --- | --- | --- |
| 1 | status=3 / connected=1 | 200 / Success / REACHED=1 | status=1 / connected=0 / active=0 |
| 2 | status=3 / connected=1 | 超时；有限重试仍 error_code=-1001 / REACHED=0 | status=1 / connected=0 / active=0 |
| 3 | status=3 / connected=1 | 200 / Success / REACHED=1 | status=1 / connected=0 / active=0 |

连接与停止 3/3，网络检查 2/3。只证明原生连接/停止主路径及这段时间的
网络结果，不掩盖第二轮超时，不证明长期稳定、具体出口或请求必经隧道。
最初 toggle 停止失败的两轮不混入上述独立停止适配结果。

## GOFast 续查

- 已正常打开 LocationSelectionViewController，看到原生节点选择控件。
- 只尝试已有 FastestLocationView 的原生最快节点按钮；当前没有可用
  匹配控件，返回 native_fastest_control_unavailable，没有修改所选节点。
- 未猜选其他付费节点、未购买、未修改协议或凭据。本轮未重复其协商失败
  连接，上一轮 KEV_NEGOTIATE_ERROR 仍是当前已知证据，具体修复未完成。

## 源码与未验证范围

- 修改只限 tools/native-onboarding：精确按钮定位、原生停止、只读 callback
  偏移/状态、GOFast 原生导航，以及超大诊断回复去除 views 的有界降级。
- test9 为只读绑定研究，test10 为 toggle 原型，test11 增加原生状态读取，
  test12 改独立停止，test13–test15 增加 GOFast 诊断；最终源码包为 test16。
- test16 编译/打包完成，未安装到手机；不得把此前实测直接写为该包已验收。
- GUI bootstrap 仍返回 mobile_not_authorized，没有真实控制中心点击、长按、
  视觉验收、后台冷启动或长期耗电测试；独立测试不冒充完整 SDT 通过。

## 最终收尾

本轮临时包/工具与三个 App 的 socket/permit 已精确清理，四份 RootHide
策略与本轮开始时字节一致；五份 VPN 最终断开，正式模块仍为 1.2.0。
私有审计和设备路径保留在仓库外，公开记录不包含节点、账号、凭据或唯一标识。

当前可继续复用的是 Jump 原生连接与独立停止实现，仍需处理网络波动并
完成正式模块接入及实际 UI 验收；GOFast 协商问题仍未解决。

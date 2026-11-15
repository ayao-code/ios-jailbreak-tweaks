# 原生连接复测：2026-11-14

本轮承接会话 `01a1d75a-02ed-78e3-853a-4af21cf9978c`，由代理独立连接设备、
执行原生测试及清理，不要求用户代做连接测试。目标核对为 iPhone13,1、
iOS 16.3.1、RootHide。开始和结束时五份 VPN 均断开，控制中心保持 1.2.0。

## 本轮结果

| 目标 | 实际操作 | 独立结果 |
| --- | --- | --- |
| Hotspot VPN | 两轮原生连接、HTTPS 请求、原生停止 | 两轮均 status=3 / connected=1；HTTPS 200、Success、error_code=0；停止后均 status=1 / connected=0 / active=0 |
| GOFast VPN | 正常启动后调用已展示且可用的付费引导关闭按钮，再触发真实 connectButton | 两次有效原生连接均停在 status=2 / connected=0；第二次触发后观察约 50 秒仍未连接 |
| Jump VPN | 读取真实主页面和原生节点准备状态 | 主页面为 ToPreapredListVC，hasSelectedNode=0；没有执行未验证连接入口、填入节点或取得密钥 |

GOFast 本轮原生关闭返回 nativeCloseDispatched=true，随后实际进入
HomeScreenViewController，未购买、未修改会员状态、未接受隐私条款。
因此本轮 GOFast 的阻塞不再只能描述为“没有进入连接主页”：已能进入主页，
但原生连接本身未成功，具体原因尚未确认。

一次 GOFast 冷启动期间的 connect 返回 main_controller_unavailable，
不计为有效连接尝试。等待原生启动、关闭原生付费引导并确认主页后，
才执行第二次有效尝试。

GOFast 第一次系统停止返回失败且仍连接中，不算停止成功；退出目标 App
再停止本次请求后，回读稳定断开。第二次失败请求使用同样的有限清理路径，
最终稳定断开。没有通过停止其他 VPN 来强行替换连接。

## 证据与未验证范围

- Hotspot 使用 App 原有 startBtnClick / stopBtnClick，GOFast 使用原有
  connectButton 控件事件。测试 IPC 校验内核审计身份和精确客户端签名。
- 客户端设备代码的 __text、__cstring、__objc_methname 与本地一致；
  监督工具按设备实际稳定签名构建，没有放宽身份校验或新增信任缓存操作。
- 独立 VPNPreferences 回读与 App manager 状态交叉核对；HTTPS 成功只证明
  连接期间设备访问可用，不证明请求必经隧道或特定出口。
- GUI bootstrap 实际返回 mobile_not_authorized；没有执行真实控制中心
  点击、长按或视觉验收，不宣称完整 GUI / SDT 流水线通过。
- Easy VPN、飞连本轮仅核对断开状态，没有重新连接验证。
- 没有重新验证长期稳定性、无切前台、耗电、认证/付费失败或崩溃增量。

## 清理与回读

- ayao.vpnadapterprobe 已卸载；dylib、Filter、独立客户端和监督工具回读不存在。
- 三个目标 App 已退出；各自 vpa1.sock、vpa1.permit 精确删除并回读不存在。
- 本轮临时设备安装包、许可请求、许可二进制和独立系统探测工具已删除。
- 四份 RootHide 策略与本轮开始时字节一致，既有目标注入许可保留。
- 最终五份 VPN 均 status=1 / connected=0 / active=0，控制中心仍为 1.2.0。
- 原始设备路径及审计数据仅保留在仓库外私有临时日志；本记录不包含凭据。

## 剩余事项

1. GOFast 已具备可测原生主页，后续应诊断原生连接卡住的实际错误，不再让
   用户代做手动连接，也不能把 status=2 当作连接成功。
2. Jump 需继续核对正常节点获取/选择流程和真实连接控件，不猜选混淆方法，
   不跳过授权、订阅或节点准备流程。
3. 所有目标通过独立验证后才接入统一菜单；目前多 VPN 正式交付仍未完成。

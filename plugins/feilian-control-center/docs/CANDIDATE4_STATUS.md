# Candidate4：受限本机认证服务

2026-11-15；iPhone13,1 / iOS 16.3.1 / RootHide。
源码、包与安装版本为 1.3.0~candidate4，仍是候选，不宣称全面交付。

## 认证链路

1. App socket 接收连接，只读取内核 peer audit 身份，并产生 128-bit 随机 nonce。
2. SpringBoard 核对目标 App 元数据后，向本机 root broker 申请该挑战许可。
3. broker 在有权限的进程中校验内核 audit token、准确 SpringBoard 路径及
   platform 标志；仅接受五个固定 provider，不接收 VPN 命令、凭据或任意路径。
4. 通过系统 App registry 取得准确 App 容器，发布固定 vcc1.permit 文件；
   permit 包含挑战、内核 audit token、20 秒过期时间，root 属主，0644。
5. App 独立核对固定许可文件类型、属主、权限、大小、当前挑战/audit 和
   有限有效期；只在核对通过后确认 socket，删除已消费许可并接收命令。
6. 同一连接 nonce 唯一，下一连接不复用；命令 generation 防重放仍保留。

RootHide 限制 broker 直接打开 App tmp，固定 root shell 发布器只接受
本机 root 临时许可源和准确容器 tmp；使用 root-only 临时目录与固定 permit
叶子原子替换，不解释任意命令。该路径是当前环境兼容实现，不关闭沙盒。
launchd 管理 broker，postinst 启动、prerm 停止；idle 阻塞 accept，无空转。
授权发布异步，App 最多有限等待许可，不在 broker 等待 shell 完成造成堵塞。

## 额外共因修复

- ActivateSuspended 会让 App 主队列不能及时处理挑战，改为正常 App 启动。
  因此 candidate4 不承诺完全后台静默、不切前台。
- 增加明确 handshake ACK，避免 TCP/Unix stream 中挑战回传和 probe 命令
  粘连被误判为非法帧；半包按实际协议长度等待，错误长度失败关闭。
- 许可窗口从早期过短值调整为观测到的系统启动时延下的有限 20 秒。
- Easy 断开调用原生 stopButtonClick，不能只停系统隧道而留下 App 重连意图。
- 飞连先调用原生 disconnect，再回读其 manager 断开；不会把派发当作完成。
- 每个提供方诊断 token 独立，客户端与服务端阶段分离。

## 正式宿主已观察结果

以下为 launchd 自动启动下、受限认证和原生停止适配完成后的宿主序列：

| 提供方 | 认证 | 原生连接/系统状态 | HTTPS | 原生断开/系统状态 |
| --- | --- | --- | --- | --- |
| Easy VPN | 通过 | connected=1 | 200 / Success | active=none |
| 飞连 | 通过 | connected=1 | 200 / Success | active=none |
| Hotspot VPN | 通过 | connected=1 | 200 / Success | active=none |
| GOFast VPN | 通过 | 原生失败，active=none | 未执行 | 无活动连接 |
| Jump VPN | 通过 | connected=1 | 最终加固包 200 / Success；此前轮次曾超时 | active=none |

最终加固包认证 5/5、实际连接 4/5、网络成功 4/5；GOFast 原生失败未计通过。
宿主序列完整结束，最后恢复 preferredProvider=easy。独立 VPNPreferences
回读五份 VPN 全断开。GOFast 仍未测通；Jump 当前网络通过不代表此前
超时已根治，尚需多轮和长期稳定性验收。

## 安全及验收边界

- standalone 非 SpringBoard broker 请求已实际拒绝，code=2、退出码0。
- 旧 IPC boundary 工具假设 open 成功后 probe 才拒绝，与新的握手拒绝行为
  不兼容；其本轮结果不作为五 App 负向全部通过。部分命令超时保留缺口。
- 本轮仅真实宿主直接调用同一模块控制器，不是实际手指点击/长按。
  GUI 工具门禁仍为 mobile_not_authorized，不冒充完整 GUI/SDT 验收。
- 源码/包 strings 敏感信息及 Filter 范围筛查通过；高敏 App 未加入任何 Filter。
- 尚需完整 nonce 重放、过期/伪造许可、半包、并发、锁屏中途变化、App
  异步启动取消、长期 CPU/耗电及 uninstall 生命周期验收。
- 早期手工启动成功不替代 launchd 自动管理；最终包安装后需再次按实际
  回读确定，不以 HTTP 200、dpkg 成功或 service running 单独宣称交付。

## 安装/清理

保留 candidate4 模块、五 App helper、认证服务与固定许可发布器。
一次性宿主自动测试和解锁文件收尾移除；解锁映射在下次宿主重启时退出。
四份 RootHide 策略与本轮开始时字节一致；旧 candidate3 和 1.2.0 包可回滚。
原始设备容器、audit 数据只保留仓库外私有日志，不提交真实标识或凭据。

本轮未提交、推送或宣称发布正式版本。剩余 GOFast 原生连接、Jump 网络、
真实 UI 和完整安全回归仍需完成。

最终包安装后，launchd 自动服务 running；非 SpringBoard broker 请求
code=2 明确拒绝。一次性宿主测试文件删除后已刷新卸载，解锁文件随后删除；
保留正式服务并再次回读 unlocked=1、所有 VPN 断开，默认 Easy 已恢复。

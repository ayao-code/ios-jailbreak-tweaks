# 1.3.0~candidate1 实现进展

2026-11-14。**源码和候选包已生成，正式发布验收未完成。**
目标 iPhone13,1 / iOS 16.3.1 / RootHide；手机最终已回滚为 1.2.0。

## 已实现

- 一个原模块：标识和 1×1 位置不变，显示名“VPN 控制中心”。
- VPNModuleViewController 基于本机已核对的 CCUIMenuModuleViewController。
  轻点操作真实活动连接，长按原生面板选择 Easy VPN / 飞连，带切换确认。
- VPNController 串行管理系统状态、配置身份、事务 generation 和选择记忆。
  初次默认 Easy，保留用户选择；初始化未知状态不派发连接。
- 有旧活动连接时先后台探测目标辅助；确认断开旧目标后才连接新目标，
  外部/多连接拒绝替换。保存新选择只发生在切换连接成功后。
- EasyVPNConnectionHelper 从 startButtonClick: 原始入口启动，给已识别的
  异步准备/节点测试/回调传播 generation；被取消的回调不执行后续启动。
  无本模块 generation 的手动路径完整调用原方法。
- FeilianConnectionHelper 复用 TopGoModel / FLTunnelManager 正常登录检查
  和原生连接，独立于保留的 1.2.0 源码。
- 每个 App 一个 0600 Unix-domain socket，在它自己的临时目录中创建；
  精确目标注册路径、内核 peer audit token / PID、uid 和 executable 检查。
  非 SpringBoard 请求不执行；公开通知只提供无敏感字段的诊断 stage。
- 稳定数据只存独立 CFPreferences domain 的 preferredProvider / schemaVersion。
  不存地址、profile UUID、会话或凭据，不修改 RootHide 隔离设置。
- 候选包包含模块和两个精确 App 辅助，不包含 standalone 探测或一次性
  SpringBoard 宿主诊断组件；与试验辅助包冲突以避免重复 Hook。

## 本轮实机结果

| 检查 | 结果与边界 |
| --- | --- |
| 构建 | arm64/arm64e 源码构建、合并、签名及 RootHide deb 生成完成；仅构建通过不等于功能通过 |
| 系统接口 | 本机菜单控制器及所用 selector 存在，VPN configurations 属性存在；dirty 标志不能用作就绪判据 |
| 独立模块构造 | ready=1 / preferred=easy / active=none，视图可加载、支持展开，展开高度约 266.3 点 |
| Easy IPC | App 临时目录 socket 建立；独立非 SpringBoard 工具可连接但探测被拒绝，服务诊断 stage=201 |
| 飞连 IPC | 退出旧飞连进程后冷启动，socket 可连接；独立工具未获得执行权限 |
| SpringBoard 宿主构造 | 一次性精确 SpringBoard 诊断组件调用同一控制器，状态最终就绪，无新增 SpringBoard 命名崩溃 |
| SpringBoard 连接 | 手机锁屏，选择/连接请求被拒绝；没有本候选连接成功证据，也未验证解锁正例 |
| 清理 | 降级 dpkg 回读 1.2.0；候选及诊断 dylib/Filter 删除，两 App 进程退出；两个 IPC socket 精确清理 |
| 隔离 | 四份 RootHide 策略字节不变，未调用 trustcache、调试标记或直接改 App 设置 |

安装验证过程中仅使用可恢复候选，旧 1.2.0 包和正式源码均保留。
早期公共临时目录 socket 被沙盒禁止，已改为原生 App 自有临时目录。
早期 standalone bundle 加载失败来自 RootHide 路径视角，核对实际路径后
模块构造成功；这些诊断不作为真实触控结果。
本轮没有通过 GUI 自动化门禁，不声称真实控制中心点击或长按通过。

## 必须补齐才能发布

1. 手机保持解锁后，真正 SpringBoard 发出身份校验正例请求，完成两 App
   各两轮连接/断开，连接期间网络请求及状态回读一致。
2. 真正控制中心长按/收起、选择记忆、确认/取消、横竖屏、VoiceOver 和
   UI 回调耗时。菜单动作刷新是否会提前关闭面板需实测。
3. 两方向完整切换：准备失败保持旧连接；旧连接断不开不启动新连接；
   新连接失败提示网络已无旧 VPN，取消确认不改状态；并发外部连接保护。
4. Easy 的异步 generation 传播来自 2.1.0 静态调用链，仍须实测异常与迟到
   回调、手动连接并发、取消后其他 Session 不受影响。旧回调丢弃不能替代
   已启动 native task 全部释放的证明。
5. 飞连原生 connect: 取消后的内部迟到任务尚未证明安全；新 helper 的
   认证/权限 UI 边界还未完成与旧严格静默版的等价验收，不能保证完全不切前台。
6. socket 绑定服务与调用方身份已做部分负向检查，正例、replay、半包、
   锁屏中途变化、客户端断开、服务端退出与长时间资源使用仍未验证。
7. 全部零配置的就绪、已有 store 重新打开、App 手动状态同步、系统接口
   不可用、权限拒绝/多配置，以及正式卸载后的 socket 生命周期需补验。

候选不是 1.3.0 正式版。上述安全阻塞未解决前不发布；不退回公开通知命令
或放开 Filter 来换取成功。无需用户提供新的产品设计，但实机正例需解锁。

## 文件

- UI：FeilianControlCenter.m、VPNModuleViewController.h/.m、CCUIMenuModuleViewController.h。
- 控制器：VPNController.h/.m；旧 FeilianVPNController.h/.m 保留用于历史重建。
- 通信：Shared/VPNIPC.h/.m。
- 专用辅助：EasyVPNConnectionHelper.m/.plist、FeilianConnectionHelper.m/.plist。
- 构建：Makefile、scripts/build-package.sh、Resources/Info.plist、control。
- 诊断源码：tools/module-api-inspect.m、candidate-smoke.m、ipc-boundary-probe.m、
  candidate-host-probe.m。均不进入正式包。

候选：`packages/ayao.feiliancontrolcenter_1.3.0~candidate1_iphoneos-arm64e.deb`。
原始带容器身份/配置的日志仅存本机私有临时目录，不进入版本控制。

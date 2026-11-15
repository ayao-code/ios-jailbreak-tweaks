# 正式宿主 IPC 拒绝根因

2026-11-14；iPhone13,1 / iOS 16.3.1 / RootHide。
用户已授权原生解锁，设备无口令保护；测试时 unlocked=1。

## 结论

五目标正式宿主连接失败的共同原因不是 App List、锁屏或全部 VPN 服务
不可用，而是 App 沙盒不允许查询 SpringBoard 的进程路径。
当前代码对此失败关闭，连接命令没有进入 App 原生连接入口。

## 五目标真实宿主证据

| 目标 | 客户端身份阶段 | 服务端路径检查 | 服务端签名查询 | 内核 socket UUID | 连接 |
| --- | --- | --- | --- | --- | --- |
| Easy VPN | 410 | 401 | 601 | 710 | 失败 |
| 飞连 | 410 | 401 | 601 | 710 | 超时 |
| Hotspot | 410 | 401 | 601 | 710 | 失败 |
| GOFast | 410 | 401 | 601 | 710 | 失败 |
| Jump | 410 | 401 | 601 | 710 | 失败 |

- 410：SpringBoard 已连到 socket，并以 App 的真实元数据确认对端身份。
- 401：App 端 proc_pidpath 对 SpringBoard 查询返回 EPERM，拒绝请求。
- 601：App 端绑定 kernel audit token 的 csops_audittoken 同样返回 EPERM。
- 710：LOCAL_PEEREUUID 可取得 16 字节 UUID。仅可读不等于已经证明其
  唯一绑定可信 SpringBoard 身份，不能直接替代路径/签名验证放行。
- HOST_VIEW_LOADED=1、providers=5、HOST_SEQUENCE_DONE=1；测试完成，连接 0/5。

最初共用单个诊断 token 导致提供方和客户端/服务端阶段相互覆盖，本轮
已按提供方注册 token，并把 server/signature/uuid 阶段分离，不影响授权。

## 当前变更

- 未删除或放宽身份校验；仅增加无标识的阶段/errno 诊断。
- 模块可把阶段 401 显示为“App 沙盒禁止校验宿主身份，IPC 请求被安全拒绝”，
  不再误导用户反复检查 App List。公开通知只作错误文案，不承载命令或授权。
- 安装并回读 1.3.0~candidate3+ipcdiag1；源码和独立包保留，敏感信息筛查通过。
- 五份 VPN 最终均断开；四份 RootHide 策略与开始时字节一致。
- 一次性宿主测试文件已移除并刷新；一次性解锁文件随后删除，为保持当前
  解锁状态不再重启，已加载的解锁映射会在下次宿主正常重启后退出。
- 仍未完成真实点击、长按及完整 GUI/SDT 验收，不把诊断成功说成修复成功。

## 修复决策边界

不能去掉 peer 检查、仅按 PID/uid 放行、采用公共通知执行命令或关闭沙盒。
优先考虑由受限本机服务在具有查询权限的位置核验 socket kernel audit
identity，再通过有界、不可重放的通道授权明确 VPN 请求；或先证明系统
提供的 peer UUID 可以严格绑定可信 SpringBoard 后采用该原生接口。
两者需要独立安全及兼容验收，当前尚未实现，不宣称已经解决。

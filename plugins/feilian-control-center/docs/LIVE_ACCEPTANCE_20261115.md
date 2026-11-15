# 手机新一轮复测：发现崩溃，验收未通过

日期：2026-11-15。目标 iPhone13,1 / iOS 16.3.1 / RootHide。
起始安装版本 1.3.0~silent1；五份 VPN 均断开。

## 实际执行方式

GUI bootstrap 仍返回 mobile_not_authorized，没有使用 HID/触摸通道绕过门禁。
使用有限 SpringBoard-only 验收组件加载手机已安装模块，调用其实际
buttonTapped 和 select 方法，同时独立查询 VPNPreferences 和系统生命周期。
验收工具未修改插件业务方法，不注入高敏 App，不访问 App 凭据。
模块视图实际加载，五提供方展开高度为 393.3 点；这不是长按触摸视觉验收。

## silent1 本轮结果

| 场景 | 结果 |
| --- | --- |
| Easy 连接/HTTPS/断开 | 通过，HTTPS 200 |
| 飞连连接/HTTPS/断开 | 通过，HTTPS 200 |
| Hotspot 连接/HTTPS/断开 | 通过，HTTPS 200 |
| GOFast 后台连接 | 失败，显示未完成、不跳 App，系统无活动连接 |
| Jump 后台连接 | 失败，显示未完成、不跳 App，系统无活动连接 |
| 重新连接 Easy | 通过，HTTPS 200 |
| Easy → 飞连 | 通过，系统唯一活动目标为飞连，HTTPS 200 |
| 后续连续切换 | SpringBoard 崩溃一次，测试中断，没有完整结束回执 |

本轮已采集目标 App 前台激活事件为 0，但存在崩溃，不能说“没有问题”。
初期一次性工具 Filter 权限为 0600 导致未执行；修正为 0644 后才有上述
真实结果，不把未执行窗口计作功能通过。

## 新增崩溃证据与修复候选

11:45:45 SpringBoard EXC_BAD_ACCESS / KERN_INVALID_ADDRESS 0x24。
faulting thread 的 queue 为 ayao.vpn.controller，主要调用链：

```text
objc_msgSend
BKSAssertion._invalidateSynchronously:
BKSProcessAssertion.invalidate
FeilianControlCenter
dispatch source / controller timeout queue
```

Shared/VPNIPC 的 close 在 controller timeout 与 IPC worker 路径均可能调用，
原执行断言没有同步取出/释放保护，且 invalidate 不在宿主主队列。
本轮 silent2 将断言在同步块中单次取出置空，创建与失效在主队列执行，
保留身份校验及有限后台生命周期。不从单份崩溃断言所有根因已排除。

silent2 arm64/arm64e 编译打包、敏感信息筛查、安装及版本回读成功。
但 silent1 崩溃后设备出现 ElleKit 的 .eksafemode 标记，SpringBoard 不再
加载普通 tweak 或一次性验收工具；silent2 没有实际运行验收通过的证据。
未删除安全模式标记或关闭保护以强行取得通过，未继续重复发连接。

## 最终状态和交付门禁

- 手机 dpkg 回读 1.3.0~silent2，但处于安全模式，不保证插件当前已加载。
- 五份 VPN 最终均 status=1 / connected=0 / active=0，手机锁屏。
- 一次性验收与解锁 dylib/Filter、临时包和客户端已删除，所有日志采样停止。
- 四份 RootHide 隔离配置与起始时字节一致，高敏 App 未注入。
- 原始崩溃和设备路径存仓库外私有目录，公开记录不含标识或凭据。
- iCloud 本轮零写入；原 silent1 安装包哈希保持不变。
- 保留源码、silent2 包和历史回滚包，不提交或推送。

下一步需先通过受控正常流程恢复安全模式，再验证 silent2 的连续切换、
重复停止/超时释放和真实 UI。当前结论必须为“验收未通过”，不覆盖 iCloud。

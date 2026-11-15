# 不跳转与直接切换修复

日期：2026-11-15。版本：1.3.0~silent1；目标：iPhone13,1 / iOS 16.3.1 / RootHide。

## 本次明确范围

- 普通点击只后台连接/断开，不自动打开 VPN App 前台；后台失败明确提示。
- 只有用户主动选择菜单“打开 App”才使用前台启动。
- A 已活动时长按选 B，选择就是切换意图，不再二次确认或要求再次轻点。
- 尽量原生停止 A 的重连意图，但 8 秒后仍未完成也请求 B，由系统仲裁。
- B 没成功不显示已切换；回读 A 或 B 的真实状态，不关闭列表外 VPN。
- 这不是要求修复所有 VPN 服务、登录或订阅，不绕过原生权限/付费判断。

## 实现

VPNController 将 connect/disconnect 的 openApplication 改为
ActivateSuspended，唯一保留 foreground open 在 openPreferredApp。
VPNModuleViewController 直接提交已核对的选择意图，移除确认/取消子面板。

后台 App 会因主队列被挂起而不能响应 socket。VPNIPCClient 在验证准确
App kernel peer PID 后，由真实 SpringBoard 持有有限 FinishTask 执行断言，
只设置 PreventSuspend，不要求前台优先级。断言随 client.close/dealloc 释放。
没有让 App 持续保活，未使用 location/audio 伪装；一次性启动保活试验已移除。

切换旧连接停止独立执行，8 秒软窗口超时关闭旧客户端并继续请求 B；
generation/phase 检查阻止迟到旧回调干扰 B，不重复派发。优先复用 B 已
通过认证的 socket，过期才重新认证，避免立即重连触发单 peer 忙碌拒绝。
外部/多个活动 VPN、变更配置和锁屏仍受保护，新请求不影响不明连接。

## 已实测

| 验证 | 结果 |
| --- | --- |
| Easy 独立后台连接、HTTPS、停止 | 通过，HTTPS 200 |
| 飞连独立后台连接、HTTPS、停止 | 通过，HTTPS 200 |
| Hotspot 独立后台连接、HTTPS、停止 | 通过，HTTPS 200 |
| Jump 后台连接 | 未完成；不自动跳转，失败后显示真实仍连接的源或无连接 |
| GOFast 后台连接 | 未完成；不自动跳转，原生服务问题未修复 |
| 菜单直接 Easy → 飞连 | 系统 active=feilian、preferred=feilian、connected=1 |
| 菜单直接飞连 → Easy | 系统 active=easy、preferred=easy、connected=1 |
| 菜单直接 Easy → Hotspot → Easy | 两方向通过 |
| 故意不给飞连 native-stop 回调，再选 Easy | 8 秒软窗口后实际连接 Easy，不以 A 停止回调为硬条件 |
| 最终包前台激活日志 | 目标 VPN Foreground 激活事件 0 |
| 停止后任务生命周期 | 观测到目标回到 running-suspended，不持续占用执行断言 |
| 非 SpringBoard 请求认证服务 | 实际拒绝，code=2、退出码0 |

软停止故障只注入测试宿主的本地方法，不进入插件安装包，不向目标 App
附加调试器；五个固定 helper Filter 不变，高敏 App 未加入或访问。
最终包测试完整日志为 SWITCH_SEQUENCE_DONE=1，默认 Easy、全部 VPN 断开。

## 失败边界与未验收

Jump 与 GOFast 在前台候选和后台候选不是同一验证条件；不承诺这两个 App
静默连通。失败场景不偷偷改用前台，也不以模拟点击跳过原生准备。
Jump 从 Easy 切换失败时，系统仍有 Easy 连接、preferred 仍为 Easy，
failed=1，未冒充已切换到 Jump。网络失败和实际活动状态是不同信息。

真实手指点击/长按、横竖屏菜单及完整 GUI/SDT 流水线仍未验收；工具门禁
返回 mobile_not_authorized。当前证明的是实际 SpringBoard 的同一菜单
选择方法、同一控制器和系统生命周期，不称作视觉自动化通过。
长期稳定性、耗电、多个企业 VPN 共存及原生迟到异步任务仍需独立验收。

## 交付与收尾

保留正式源码及对应 RootHide 包：
packages/ayao.feiliancontrolcenter_1.3.0~silent1_iphoneos-arm64e.deb。
安装并回读 silent1，旧 candidate4/1.2.0 回滚包保留；未提交或推送。
本轮一次性测试/解锁文件删除、日志采样停止；四份 RootHide 策略字节不变。
正式认证服务和五 helper 为插件组件，保留安装，不是测试残留。
本轮不再操作高德，不改变其定位/后台设置。

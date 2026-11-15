# 退出安全模式后的 silent2 手机回归

日期：2026-11-15。目标 iPhone13,1 / iOS 16.3.1 / RootHide。
开始实际检查安全模式标记不存在，已安装版本为 1.3.0~silent2。
五份 VPN 均断开，无口令保护；按既有授权正常原生解锁后执行。

## 本轮方法与范围

在真实 SpringBoard 通过一次性验收组件加载手机已安装模块，调用其
buttonTapped 和 select 方法，未替换业务方法。每次连接/断开都从
VPNPreferences 独立回读全部五份配置，并执行有界 HTTPS 请求。
模块视图加载及展开回调通过，provider_count=5、expanded_height=393.3。

GUI bootstrap 仍返回 mobile_not_authorized，未绕过触摸门禁。此为
真机宿主功能测试，不等于手指点击、长按触摸或菜单视觉验收通过。

## 完整宿主序列：12:38:09–12:41:51

| 场景 | 结果 |
| --- | --- |
| Easy 后台连接 / HTTPS / 原生停止 | 通过，200 / Success / error=0，最终断开 |
| 飞连后台连接 / HTTPS / 原生停止 | 通过，200 / Success / error=0，最终断开 |
| Hotspot 后台连接 / HTTPS / 原生停止 | 通过，200 / Success / error=0，最终断开 |
| GOFast 后台连接 | 失败，系统断开、failed=1，明确提示未跳 App |
| Jump 后台连接 | 失败，系统断开、failed=1，明确提示未跳 App |
| 切换序列初次连接 Easy | 通过，HTTPS 200 |
| Easy → 飞连 → Hotspot → Easy | 三次切换全部通过，每个目标 HTTPS 200，前一目标不活动 |
| 最终停止及恢复选择 | 默认 Easy，全部 VPN 断开，PREFERENCE_RESTORED=1、LIVE_ACCEPTANCE_DONE=1 |

单项连接 3/5 通过、2/5 原生后台失败。包括切换序列初始连接在内的
4 个目标连接检查及 7 次 HTTPS 检查均通过，但不得计算为全部五目标通过。

## 执行断言并发释放回归

只使用手机已安装模块里的 VPNIPCClient，后台唤醒 Easy 后进行 probe，
不发送连接/断开命令。每轮完成认证后从两个 worker 同时调用同一 client
的 close，等待主队列断言失效排空再进入下一轮。

- 有效认证 10/10；同一 client 双线程 close 完成 10/10，共 20 次 close。
- ASSERTION_CLOSE_STRESS_DONE=1、ready_count=10，完整回归结束。
- 初次未唤醒 App 的 probe 全失败，不算执行断言回归；修正测试前提后
  才取得上述 10/10 有效结果，未改插件业务源码。
- 本轮开始/结束 CrashReporter 中 SpringBoard 报告集合完全一致，新增 0。
- 安全模式标记始终未再出现；当前观察窗口支持修复回归通过，不证明
  任意长期运行、所有异常或跨版本场景永远不会崩溃。

## 不跳转与收尾

目标 VPN 前台激活事件 0；观察到请求结束后恢复 running-suspended。
四份 RootHide 配置字节不变，未注入高敏 App，也未操作高德定位/后台配置。
一次性验收/并发工具及解锁文件精确删除；宿主测试组件已刷新卸载。
解锁文件在最后一次刷新后删除，其映射在下次宿主重启时退出；不宣称
已卸载所有驻留映射。所有日志采样均停止，正式插件和认证服务保留安装。
最终 dpkg 回读 silent2、unlocked=1、五份 VPN 全断开，认证服务 running。

原始设备路径、audit 和崩溃信息仅保留仓库外私有日志。本轮新增的
tools/live-acceptance/host.m 和 assertion-close-stress.m 不进入正式安装包，
源码保留供后续重现。未提交或推送。

## iCloud 门禁

iCloud 本轮零写入，已有 silent1 包哈希保持不变，silent2 未上传。
Jump/GOFast 后台未通过、真实触摸/长按视觉及全面安全回归未完成；不能
把并发释放修复通过扩大为“插件全部没问题”，暂不覆盖云盘交付文件。

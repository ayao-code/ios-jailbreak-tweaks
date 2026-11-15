# 五提供方候选安装状态

2026-11-14。源码和包版本 1.3.0~candidate2 已安装到 iPhone13,1 /
iOS 16.3.1 / RootHide。任务未完成，不作为已验收正式版发布。

## 明确范围

目标为五个 App：Easy VPN、飞连、Hotspot VPN、GOFast VPN、Jump VPN。
共用一个模块和长按菜单，默认 Easy，沿用模块标识和原排列位置。

| 提供方 | 连接方式 | 停止方式/边界 |
| --- | --- | --- |
| Easy VPN | 原有 startButtonClick 原生流程 | 现有系统目标配置停止，正式候选未验收 |
| 飞连 | TopGoModel 的 FLTunnelManager 原生 connect | 系统唯一目标配置停止，正式候选未验收 |
| Hotspot | 原生 startBtnClick | 原生 stopBtnClick；避免只停系统后自动重连 |
| GOFast | connectButton 原控件事件 | App 自身 manager 停止；具体协商失败仍未解决 |
| Jump | 实际 UIButton 的已核验 RAC 回调 0x2d898 | 已核验原生 theVersionOpinionatedChanged 清理/停止 |

MultiVPNConnectionHelper 限定准确三个 Bundle 和既定 App 版本；没有添加
高敏 App。只读查找实际控件绑定，不猜调连接末端、不复制节点或凭据。
候选仅活动请求期间有限状态检查，完成/失败/超时后释放定时器和后台任务。
切换旧连接时，原生停止提供方必须收到停止确认并独立回读断开，才连新目标。

## 本轮实际证据

- arm64/arm64e 编译、合并、签名与 RootHide deb 打包成功。
- 源码/包内 strings 敏感信息检查和精确 Filter 检查通过。
- dpkg 安装并回读 1.3.0~candidate2，包内模块及三个 helper 文件实际存在。
- 五 App IPC 服务均可达，非 SpringBoard 探测均被拒绝，5/5。
- 真正 SpringBoard 诊断日志返回 HOST_VIEW_LOADED=1、providers=5。
- 刷新后手机锁屏，独立系统 read 返回 unlocked=0；未绕过锁屏。正式
  SpringBoard 连接正例未完成，不能用临时独立测试结果替代。
- 初期 standalone 构造受 RootHide 路径视角影响；真实宿主加载结果才是有效
  模块加载证据，不把失败 standalone 检查写成通过。
- 五份 VPN 最终均 status=1 / connected=0 / active=0；四份 RootHide 策略
  与本轮开始时字节一致。

## 当前设备状态及回滚

- 保留安装 candidate2，不自动降级为旧模块；旧 1.2.0 包仍在 packages。
- 安装前设备端备份旧 bundle 和 CCSupport 排列；未重排控制中心。
- 一次性 SpringBoard 诊断组件、临时包和工具已移除并刷新卸载。
- 五个正式 App helper 保留，这是候选本身的一部分，不是测试残留。
- 真实用户解锁是当前正式连接验收前提，不要求用户代做任何 VPN 操作。

## 仍需完成

1. 解锁后以真正 SpringBoard 身份验证五目标连接、原生停止与状态回读；
   GOFast 原生服务协商失败需真实错误反馈，不把调用成功算隧道成功。
2. 真实点击、长按展开高度、全部五项可达性、选择记忆、确认/取消和双向切换。
3. 新三目标原生异步连接取消及迟到启动目前仅有有限请求/停止保护，尚未
   完成异常验收；不能宣称在线安全或任意后台环境均可连接。
4. Jump 曾有 HTTPS 波动，需再次独立验证网络而不只看已连接标志。
5. GUI 通道仍返回 mobile_not_authorized，未执行标准 GUI/SDT 完整验收。
6. IPC 部分写、锁屏中途变化、重放、进程退出和长期资源/耗电仍未完整验收。

候选包：packages/ayao.feiliancontrolcenter_1.3.0~candidate2_iphoneos-arm64e.deb。
源码、测试及历史正式包均保留；未提交或推送本轮变更。

## 用户授权原生解锁后的真实宿主续测

用户明确表示已删除锁屏密码并授权代理正常解锁。配对设备接口连续回读
PasswordProtected=false。调用目标 iOS 实际存在的
SBLockScreenManager.lockScreenViewControllerRequestsUnlock 原生 UI 请求后，
宿主回读 LOCKED=0，独立系统回读 unlocked=1。没有修改密码设置或绕过
口令认证；旧头文件 unlockUIFromSource 的签名与现场不一致，未据此宣称成功。

随后真正 SpringBoard 有界顺序测试五提供方：Easy、Hotspot、GOFast、Jump
返回连接辅助未响应；飞连请求超时。连接成功 0/5，HOST_SEQUENCE_DONE=1。
因此当前候选的正式宿主通道未通过，解锁已不再是阻塞。不能把独立临时
连接后端成功当作 candidate2 已通过，也不能仅凭五服务可达宣称可用。
下一步应优先诊断真实 SpringBoard 到 App 的 IPC/后台准备通道。

五份 VPN 最终断开，candidate2 保留安装。一次性解锁及宿主诊断文件已
删除，定时测试已结束；为保持当前解锁状态未再刷新 SpringBoard，已加载
的一次性 dylib 映射会在宿主下次正常重启后退出，不声称已经卸载内存映射。
原生解锁源码仅为设备已明确无口令时的临时工具，不随正式插件包安装。

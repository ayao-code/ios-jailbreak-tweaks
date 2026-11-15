# VPN 控制中心

## 当前发布：1.3.1（无独立认证后台，保留已知限制）

用户选择本机开放调用；当前构建不再安装认证broker、许可发布脚本或后台
启动任务。固定App私有通信和开关范围保持；新连接的请求编号独立，防止
其它本机调用者的大编号影响后续控制中心请求。87项通信回归通过。
GOFast超时、Jump/GOFast Beta及真实GUI未验证继续保留，不能称全部验收通过。
发布说明、验证边界和安装包哈希见 `docs/RELEASE_1_3_1.md`。

## 已安装实测预览：1.3.1~localopen1

取消独立认证后台和SpringBoard来源认证，保留App内本机开关与请求边界。
用户随后允许注销，已安装12 mini并核对实际新版加载。Easy/飞连/Hotspot/Jump
后台开关与联网、三目标全部六方向切换通过；GOFast超时，真实GUI受权限阻塞。
保持预览状态，不宣称全部验收通过。见 `docs/LOCAL_OPEN_PREVIEW.md`。

## 历史发布：1.3.0（RootHide，保留已知限制）

用户确认飞连切换超时暂不处理，按当前修复源码发布并安装，不追加切换
优化或网络测试。Easy/飞连/Hotspot 独立后台开关已在12 mini通过；同版
候选的Easy→飞连切换超时仍保留，其他方向本轮未完整验证。Jump/GOFast
仍为Beta。发布版本号不代表全部路径稳定100%，不代表14PM功能已验证。
此次仅改版本元数据，运行逻辑与bfirst7-reviewfix1相同。
发布、安装及提交范围见 `docs/RELEASE_1_3_0.md`。

## bfirst7-reviewfix1 修复与实测记录

已修 Easy 请求归属、空 Session 回读、root 许可发布父目录竞态与清理、
陈旧 socket 检测及测试成功判据；本地针对性验证和候选构建通过。
本候选已安装；握手双线程close10/10、opening取消10/10、断言到期2/2、
三目标独立开关联网通过，Easy原生连接中取消样本通过。但六方向回归
第一项Easy→飞连超时，后续未执行，不能发布稳定版，iCloud未覆盖。
最新实测及清理见 `docs/REVIEWFIX_LIVE_20261115.md`；上一阶段见
`docs/REVIEW_FIX_STATUS_20261115.md`。以下为历史版本记录。

## bfirst6-coldready1 历史记录

在bfirst5同名类隔离修复上，补充飞连冷启动通信端口就绪重试：准备阶段
在8秒尝试窗口内就绪即继续，非固定等待；正常已就绪操作不额外延迟。
首次握手本身仍受原有超时/取消约束，8秒不是整个连接操作的硬超时。
bfirst6飞连初连和飞连→Easy补测均已连接且HTTPS通过；同版本完整六方向
6/6通过，范围8.989–13.995秒、中位11.492秒，不宣称实测提速或稳定100%。
最终收尾及边界见 `docs/COLDREADY_RETEST_20261115.md`。
本版本已安装，前三个独立后台开/关及网络也通过；最终并发close回归出现
重复启动记录，未完成10轮，原因未定，已停止并移除临时测试。
Jump/GOFast仍Beta，实际触摸/展开视觉未验收，iCloud发布门禁仍未通过。

## bfirst5-classguard1 历史记录

已修复临时测试宿主误取系统同名 VPNController 的问题：正式类命名为
AYAVPNController，回归工具从已安装模块取对象并核对所属二进制和方法签名。
真机取消握手10/10、获权客户端双线程close 10/10通过；20次相同状态回读
没有重复界面回调。普通切换无新增等待、无缓存、无旧A停止命令。
最新网络回归有一次飞连HTTPS超时，不能宣称六方向全通过或稳定100%；
圆形进度位置真机布局回读居中，实际触摸及展开视觉未验收。
本版本已安装，iCloud未覆盖。最新证据与未解决边界见
`docs/CLASSGUARD_RETEST_20261115.md`。以下版本结论均为历史记录。

## bfirst3 历史记录

切换只后台准备/认证 B 后立即请求连接 B，不向 A 发停止命令，没有
旧 8 秒等待阶段。Easy/飞连/Hotspot 最后一轮六方向切换及网络检查通过，
耗时约 8–14 秒；本轮另一追加回归中飞连有一次失败，不能宣称稳定率100%。
Jump/GOFast 标为 Beta，未纳入主要六方向验收；真实触摸仍未验证。
圆形进度与居中修复保留，已安装 bfirst3，iCloud 未覆盖。
当前设计及实测见 `docs/BFIRST_STATUS.md`；以下内容为历史记录。

silent5 在测试中发生新的空对象崩溃，本轮已移除不兼容的动态断言子类，
恢复系统断言并增加创建失败关闭、主队列单次释放、15 秒主动到期及
客户端生命周期校验。手机已安装 silent6-safety1；10 轮双线程 close 和
2 轮主动到期回归通过，本轮无新增 SpringBoard 崩溃。
15 秒安全预算可能使较慢 VPN 请求失败，本轮没有重测五 App 的网络闭环，
不得把历史成功直接写成当前版本支持全部五目标。iCloud 未覆盖。
最新记录见 `docs/SAFETY_RECOVERY_20261115.md`。下文仅为历史结果。

最新手机复测发现 silent1 连续切换时发生 SpringBoard 崩溃，堆栈位于
BKSProcessAssertion.invalidate。用户退出安全模式后，silent2 已在真正
SpringBoard 完整重测：Easy、飞连、Hotspot 主路径及连续切换通过，
10 轮获权客户端双线程 close 回归完成，无新增 SpringBoard 崩溃。
Jump/GOFast 后台仍失败、真实触摸未验收，iCloud 本轮未覆盖。
最新详情见 `docs/SILENT2_RETEST_20261115.md`；首次崩溃见
`docs/LIVE_ACCEPTANCE_20261115.md`。下文 silent1 通过项是历史局部结果。

已实现默认 Easy VPN、原生长按选择面板、选择记忆、真实连接状态、
确认后顺序断开/连接，以及 Easy VPN / 飞连 / Hotspot / GOFast / Jump 的连接辅助。
包与模块标识保持不变；候选包在 `packages/`，完整源码在本项目。

普通点按只后台唤醒，不跳转 App，也没有自动前台兜底；用户主动点
“打开 App”才切前台。长按选择另一 VPN 直接切换，不再弹第二次确认。
旧连接原生停止最多等待 8 秒；未完成也尝试新目标，由系统仲裁，以回读为准。

当前 **不能作为五 VPN 全功能通过的正式版本发布**。受限本机认证服务解决了
App 无权反查 SpringBoard 的问题；正常启动 App 后完成 nonce/audit 许可握手。
本轮在真正 SpringBoard 验证 Easy、飞连、Hotspot 的后台连接及相互直接切换。
Jump/GOFast 本轮后台准备未通过，失败不自动跳转，不能套用 candidate4
前台唤醒的成功记录；真实触摸/长按视觉验收仍未完成。
本轮目标手机保留安装 silent1；一次性 SpringBoard 自动测试组件收尾移除。
旧 1.2.0 安装包及设备端模块/控制中心排列备份保留可供回滚。

最新交互修复与实测见 `docs/SILENT_SWITCH_STATUS.md`；
认证实现与历史实测见 `docs/CANDIDATE4_STATUS.md`；旧失败根因见 `docs/IPC_ROOTCAUSE.md`；
安装历史见 `docs/CANDIDATE2_STATUS.md`；
旧轮细节见 `docs/CANDIDATE1_STATUS.md`；
交互设计见 `docs/MULTI_VPN_DESIGN.md`。下文为 **1.2.0 历史使用与验证记录**，
不代表 1.3.0 候选同样通过。不能把临时 EasyVPNHelper 的连接成功替代
候选新 IPC 和任务取消机制的验收。

构建候选：

```sh
bash plugins/feilian-control-center/scripts/build-package.sh
```

默认仅按当前 RootHide 包装约定生成 iphoneos-arm64e；不承诺普通 rootless。
正式辅助仅分别匹配 com.qdtiktok.easyvpn / com.volcengine.corplink。
不修改 App List，目标注入需由用户通过官方管理器启用。

正式辅助通过 App 临时目录的 `vcc1.sock` 接收内核 peer audit token / PID
校验后的 SpringBoard 请求；不使用公开 Darwin 通知执行连接。
诊断 stage 通知只记录整数、不承载命令、不代表来源认证。
IPC 路径由运行时 App 注册信息获取，不硬编码设备容器或局域网地址。

## 1.2.0 历史记录

> 2026-11-08 仓库整理说明：原始截图、设备导出、历史测试包及详细日志已按用户要求清理。下文旧 `research/`、`evidence/` 路径仅描述当时记录，不代表文件仍在；保留正式源码、资源和必要交付包。此次整理未重新执行功能验收。

当前版本：**1.2.0，后台静默版，已安装到本次 14 Pro Max**。

2026-11-08 同版本也已安装到 iPhone 12 mini（iPhone13,1 / iOS16.3.1 /
RootHide / 飞连3.3.26），新增控制中心模块并刷新桌面，包版本和配置回读通过。
该设备锁屏，尚未取得连接成功或真实点按证据；安装记录见
`evidence/12mini-20261108/`，不把14PM成功代替12mini验收。

## 使用

控制中心最底部左侧的盾牌按钮为“飞连 VPN”。

- 点击开启：按需后台唤醒飞连，调用其原生 `FLTunnelManager connect:`。
  **不打开飞连界面、不切换前台、不弹出普通开启确认框**。
- 点击关闭：系统接口停止唯一的飞连 VPN，同样不打开 App。
- 蓝色表示连接中/已连接/重连，暗色表示未连接，感叹号盾牌表示上次失败。
  蓝色不单独证明网络已经可用，仍需 connected 状态及实际业务访问核对。
- 登录过期、身份验证、权限或交互要求：本次停止，保持不跳转；用户手动
  打开飞连处理后再点击。插件不绕过认证、不输入验证码、不复制连接凭据。

## 实机验证

本次 iPhone15,3 / iOS16.3 / RootHide / 飞连3.3.26：

- 最终安装文件冷启动：飞连旧进程退出后后台新启动，请求约 **2.0秒**
  达到 `connected=1`，回调约 **0.012ms**返回。
- 后台已运行时重连约 **1.5秒**；断开约 **0.013–0.015秒**。
- 关闭后等待35秒背景空闲再连接，约 **1.4秒**达到connected1；这不证明
  操作系统一定已将进程暂停，只证明等待后的后台连接成功。
- 开始/结束前台均不是飞连，前后截图主体像素差异均值 **0.0**。
  截图保存在Mac临时目录，不把个人画面或原始账号信息放入仓库。
- 冷启动和重复启动结果 `silent_result code=1`；生命周期代码在完成、失败、
  系统到期及单次超时时结束后台任务，未增加永久保活或循环轮询。
- 后续最后一次回读为connected0且飞连进程已退出，原因未确认；不能据此前
  成功连接宣称最终仍连接或长期保持。最新状态记录在1.2.0-final-readback.log。
- dpkg回读1.2.0并刷新控制中心，刷新后connected1保持，无新SpringBoard/飞连
  崩溃报告。手机刷新后锁定，**1.2.0真实控制中心触控关→开尚未补验**。
- 独立工具共用正式控制器，不把这些测试伪称真实CC点击或标准SDT全通过。

证据在 `evidence/1.2.0-*.log` 与 `evidence/1.2.0-verification.md`。
未验证：认证过期真实对照、其他活动VPN正例、长期CPU/耗电、跨飞连版本。
VPN状态连通不等于所有企业内网资源已验收。

## 实现与边界

正式源码为 `FeilianControlCenter.m`、`FeilianVPNController.m`、`VPNPrivate.h`、
`FeilianConnectHelper.m`、`FeilianRequest.h` 及精确Filter。

1. 控制中心仅匹配 com.volcengine.corplink，多个匹配/其他活动VPN时拒绝替换。
2. SpringBoard调用系统 `__ActivateSuspended` 后台启动，不传前台URL。
3. 一个带毫秒级到期标识的15秒请求，经版本化Darwin通知传到飞连。
4. 辅助仅注入 com.volcengine.corplink，检查受保护数据可用、App未在前台、
   原生isLogin为真，才调用TopGoModel.share.tunnel的原生connect流程。
5. 保留飞连会话生成与认证逻辑。静默操作期间若原生尝试presentViewController
   或UIApplication.openURL，整项请求失败并停止连接，不调用弹窗确认、不伪造认证。
   无请求时这些方法完全调用原实现，不改变飞连普通操作。
6. 每次请求最多一个15秒后台任务及单次超时；完成/失败即释放，不常驻保活。
   状态使用系统事件通知更新，资源初始化尽量延迟到用户实际请求。
7. 单次后台任务期间的UI保护Hook作用于飞连进程，不注入其他App或系统认证进程。
   认证失败/过期的负向边界主要由源码限定，目前未实机人为过期账号验证。

没有后台daemon、不读取动态口令/Keychain、不写飞连沙盒、不改系统签名或
RootHide黑名单；阿里/蚂蚁/金融/京东系均不在Filter中。

## 构建和包

```sh
bash plugins/feilian-control-center/scripts/build-package.sh
bash plugins/feilian-control-center/scripts/build-test-tools.sh /tmp/feilian-test-tools
```

- 包：`packages/ayao.feiliancontrolcenter_1.2.0_iphoneos-arm64e.deb`。
- 目标仅本次RootHide，依赖现有CCSupport与MobileSubstrate兼容接口。
- 安装在RootHide映射的 `/Library/ControlCenter/Bundles/` 和
  `/Library/MobileSubstrate/DynamicLibraries/`，不写stock系统目录。
- 普通Dopamine rootless未打包或测试，不承诺兼容。
- 辅助Filter只有飞连，无SpringBoard辅助注入。
- 测试工具所需后台启动权限 `com.apple.frontboard.launchapplications` 由目标
  SpringBoard原始签名核对，仅签在独立临时工具；正式模块继承SpringBoard宿主
  原有权限，不修改系统entitlement文件。缺权限时即使root也被FBS拒绝后台启动。

## 历史版本

- 1.0.0失败提示调用不支持的contentViewController，曾导致两次SpringBoard
  SIGABRT；包只留事故定位，**不能安装回滚**。
- 1.0.1移除失败弹窗，但直接启动系统配置缺少飞连会话，重连失败。
- 1.1.0官方URL+普通启动确认自动处理已连通，但会跳飞连界面。
- 1.2.0后台调用原生连接，替代前台URL及自动确认逻辑。

## 配置与停用

控制中心19→20只新增飞连模块，原顺序和其他键保留；XML /
mobile:mobile /0644，Mac与设备留有备份。后续安装不重写控制中心配置。
SDT规划在 `flux/changes/20261107-232822_feilian-cc/`，缺执行工具/Gate，
独立实测不冒充标准SDT全部通过。

设置→控制中心移除“飞连VPN”，再由Sileo卸载ayao.feiliancontrolcenter。
必要时正常关闭/重新打开飞连以卸载辅助。不恢复整份旧配置或删除无关模块。

## 诊断工具

`tools/vpn-test.m` 共用正式控制器，初始1秒预热避免异步状态尚未返回误判。
`tools/inspect.m` 只读最小标识/状态、方法签名及测试官方/后台入口；
`--silent-result`只输出结果码，不输出请求或会话内容。
`tools/module-test.m` 独立加载同一bundle，不冒充真实CC触控。
`tools/ui-input.m` 源于本仓有限HID工具，限飞连/设置/控制中心，无解锁或凭据输入。
`tools/enable-module.m` 仅通过系统CC配置API加入目标模块，先备份后要求语义精确。

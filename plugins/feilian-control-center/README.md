# 飞连 VPN 控制中心

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

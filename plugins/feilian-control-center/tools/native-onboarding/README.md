# 三个新增 VPN 的独立原生入口探测

目标为 Hotspot VPN 2.0.2、GOFast VPN 1.4.0、Jump VPN 1.1.0，
不是 Surge 或 Shadowrocket。仅这些三个 Bundle 在本试验 Filter 内。

## 最新状态：用户开启注入后的实测

最新续测见 `../../tests/JUMP_NATIVE_VALIDATION_20261114.md`。Jump 原生连接
按钮已通过 ReactiveObjC 回调与静态链路交叉确认，连接两次成功后又补测
停止方法；独立原生停止适配的三轮中，连接/停止 3/3，HTTPS 2/3（失败轮
重试仍超时）。不能忽略网络波动或宣称完整验收。GOFast 仍未测通。
以下 test8 和“Jump 入口未验证”说明是历史记录。

当前 test16 保留精确原生连接按钮、独立原生停止、只读 RAC 回调绑定与
状态诊断。`locations` 仅打开 GOFast 原生节点选择页，`fastest` 只触发
原生可用最快节点控件；本次该控件不可用，未改变节点或购买。

后续根因诊断见 `../../tests/NATIVE_ROOTCAUSE_20261114.md`：GOFast 原生
OpenVPN 返回 KEV_NEGOTIATE_ERROR；Jump 冷启动早期 nil 不是最终节点状态，
等待原生加载后有 70 个节点及选中项。两者仍未完成原生连接验收。
当前 test8 只增加断开错误元数据、节点数量/类型及原生按钮绑定偏移读取，
没有启用 Jump connect。实验导航命令已移除，不发布未知目的地动作。

Hotspot 两次原生连接、网络请求和原生停止通过，GOFast 因原生隐私同意页
未进入主页面，Jump 原生模型未选中节点且完整连接控件尚未确认。
独立测试包已卸载、工具与三份 socket/短时 permit 已清理，手机控制中心
仍为 1.2.0。详细证据和未验证边界见 `../../tests/THREE_VPN_NATIVE_VALIDATION.md`。
下文旧“注入未开启/未安装”是早期历史，不是最新状态。

本工具不加入正式控制中心包，先验证每个原生入口，再决定如何接入。
测试源码和包均保留；未经成功实测的入口不能声明为可用适配。

## 2026-11-14 当前结果

- 三 App 安装时间均在 09:48-09:49，系统各有唯一对应配置。
- 测试前 GOFast 已连接；独立系统断开成功，但重新连接 20 秒后仍为
  connecting。已经停止未完成请求；尚未恢复 GOFast 原始连接。
- Hotspot / Jump 系统 connect 后短暂 connecting，随后断开，均未通过。
- 仅正常启动 GOFast App 没有自动恢复连接。
- 三 App 的官方 executable 注入允许项尚未启用；未写 App List、未向
  三 App 加载 dylib、未绕过签名/沙盒、未执行 GUI 点击。
- 需要用户在官方 App List 为 hotspotvpn、GOFast VPN、Orderidtext
  开启注入。不得顺带开启其他 App。

## 原生候选入口与证据

Hotspot 的 ViewController.startBtnClick 为原生按钮入口，调用 doStart，
包含原生提示/付费检查，后续 prepareStartVPN/prepareManager 启动。
GOFast 的 HomeScreenViewController.connectButton 可取得实际 UIControl，
候选方案发送它绑定的 TouchUpInside 动作，保留原始流程；动作尚未实测。
Jump 的混淆方法不能按名字推断，当前只允许 discovery/status，connect
明确返回 jump_entry_not_verified。需通过实际主控件绑定和原生调用链
确认，不绕过准备/认证流程直调网络 API。

### 第二轮静态核对

- Jump 的 SceneDelegate 原生启动明确创建 ToPreapredListVC 为导航根页面；
  storyboard 里的 ViewController 不是可直接采用的运行时主页面依据。
- ToPreapredListVC.skewerBtn 的原生 actionBlock 调用 LbaseService.recommenOffset，
  后者打开 URL，是推广路径，不是 VPN 连接入口，已明确排除。
- ToPreapredListVC.rewardbarNode: 的原生分支调用 hideConsumersView: 或
  carbonClickConfirmBtn:，后续 TradesService.hideConsumersView: 调用 nikonTarget，
  最终 startVPNTunnelWithOptions:andReturnError:。这是静态调用链证据，
  不代表可跳过前置检查直调这几个方法，尚需运行时找到原始连接控件绑定。
- discovery 已增加真实控制器树/控件绑定，按已识别的三 App 主页面定位。
  helper 校验准确 App 版本；Hotspot 无参数按钮入口也检查原始方法签名。
- 探测回调增加 peer generation，旧延迟状态回调不得写入新测试请求。
- 本轮再次回读三 App 注入允许项仍不存在，未安装原生辅助、未发连接命令。

静态工具 `../static-analysis/objc-methods.py` 只输出方法名、签名和代码
偏移，支持授权的无加密 Mach-O 及部分 chained 指针。解析失败的类跳过，
不能把空结果当成不存在方法；须用运行时对象和原始方法签名交叉核验。

## 构建与运行

```sh
bash plugins/feilian-control-center/tools/native-onboarding/build.sh /tmp/vpn-adapter-build
```

独立 test deb 在项目 packages 内；probe 可执行文件不随包安装。
辅助 IPC 位于各 App 的 tmp/vpa1.sock，0600，检查内核 peer uid/audit PID
和明确测试工具路径，公开通知不发送命令。只接受一次 25 秒内请求。
独立工具放入越狱 /var/tmp/vpn-adapter-native-probe 后，获得授权且手机解锁，
可运行 `BUNDLE discover`、`BUNDLE status`。`BUNDLE connect` 为网络变更，
仅允许无活动 VPN 时测试，不得用于替换用户其他连接。

discover 仅返回控制器类、是否有已展示控制器、控件绑定 target/selector。
不返回画面文字、URL、节点、配置、账号或凭据。原生弹窗原样保留，
不点击、不压制。status 仅返回 App 自身已加载 manager 的状态码。

probe 资源具有有限存活期，但原生 App 自己的异步任务取消仍须独立确认。
失败/超时后从系统 readback 检查并只停止本次目标请求，结束目标 App、
卸载 test package、精确删除三个 App tmp/vpa1.sock 以及独立工具。
开始时活动连接必须最终恢复或明确报告无法恢复；不能假称全部回滚。

本轮只生成工具，未安装未运行原生 helper；三目标适配和控制中心组装
均未完成。正式候选目前仍仅支持 Easy VPN / 飞连。

### 当前工具调用说明

客户端首次执行可能被 RootHide 重签名；先比对设备实际代码段与本地
构建，再用设备稳定 CDHash 重建 authorize.m。build.sh 的本地 CDHash
默认值用于普通构建，不承诺 RootHide 第一次运行直接兼容。
客户端输出的 PERMIT_REQUEST 由监督程序核验其 audit token 与 CDHash，
root 监督通道将有效载荷原子发布到 App tmp/vpa1.permit，stdin 确认后
客户端才连接 socket。原始审计令牌/容器路径只保留在私有临时日志。
公开整数 stage 通知只作诊断，不是命令或授权。

工具 discover 返回少量控制器/控件/手势类型，以及 UIButton 标题以区分
原生连接和推广入口；不得抓取文本输入内容、节点、账号或凭据。
close-onboarding 仅可触发 GOFast 真实可用的原生关闭按钮；有嵌套隐私
同意控制器时必须拒绝，不进行任何同意选择。
Jump connect 仍拒绝未验证入口；不因为观察到 manager 就跳过主页面流程。

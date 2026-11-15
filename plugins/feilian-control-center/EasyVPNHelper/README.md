# Easy VPN 原生连接辅助：已完成连接主路径实测的试验源码

此目录不是正式控制中心版本，不加入原 FeilianControlCenter 或
FeilianConnectHelper 的构建。临时包已验证连接主路径，**不是正式发布版本**；
控制中心菜单、认证边界及长期资源使用尚未验收。

## 最新结果：官方开启目标注入后

2026-11-14 09:03 起，iPhone13,1 / iOS 16.3.1 / RootHide / Easy VPN 2.1.0：

- 用户在官方 App List 开启 easyvpn 注入后，临时包正常加载。未再使用
  opainject、trustcache 或直接配置写入。
- 独立外部请求调用原生按钮，两轮完整“已连接→断开→重连”通过。
  两次重连约 4.229 / 4.252 秒，断开各约 0.406 秒。
- 冷启动后台连接约 5.727 秒，后台热重连约 4.291 秒。
- 上述四次连接的设备端 HTTPS 请求均为 200，正文包含 Success，15 秒后
  系统仍 connected=1，非目标飞连始终断开。只证明连接期间 HTTPS 可用，
  未独立验证出口或每个请求确实穿过 tunnel。
- 原生辅助回报与系统独立查询一致，不把 launch_error=0 当成连接成功。
- 显示布局查询仍返回未知，未证明前台界面完全不变。后台启动选项及
  后台连接成功已验证，不等于真实控制中心点击或静默 UI 验收。
- 早期 standalone 首次枚举会启动异步状态加载，曾出现假断开；native-probe
  已增加有限预热枚举，上述完整循环仅使用修正后证据。
- 最终 Easy VPN 与飞连均断开，临时包及独立工具已移除。用户新开启的
  easyvpn 注入保留；四份 RootHide 策略与本轮开始时字节一致，目标可执行
  文件不变，未观察到本轮新增目标 App/扩展或 SpringBoard 命名崩溃报告。

详细记录见 `../tests/EASY_VPN_NATIVE_VALIDATION.md`。以下旧记录保留加载
失败过程，不代表最新状态。

## 目的与实现

用户授权验证 Easy VPN 单次外部触发连接。目标仅为
`com.qdtiktok.easyvpn` / Easy VPN 2.1.0。

- `EasyVPNNativeHelper.m`：接收最多 30 秒有效的 Darwin 通知，调用
  ViewController 原始 `startButtonClick:` / `stopButtonClick:`，不跳过
  prepareStartVPN 前的 App 提示或付费判断。
- 接收者只读取目标 tunnel/tunnel2/tunnel3 的状态；不复制节点、协议配置、
  会话、账号或凭据，不创建或改写 VPN 配置。
- 原生 presentViewController 完整转发，并将当前请求标记为需要交互。
  不选择弹窗按钮、不绕过认证、锁屏或系统权限。
- `native-probe.m`：独立进程发送请求；调用前核对唯一目标、无其他活动 VPN、
  已解锁，使用系统 VPN 状态检查结果。默认前台启动，`--background` 是未验收
  的候选路径；`--stop` 仅用于本轮目标连接清理。
- 背景任务有有效期，状态使用事件通知。App 原生异步任务无法保证全部取消，
  前台观测和请求超时后的行为未验收，不应直接发布。

## 构建

```sh
bash plugins/feilian-control-center/EasyVPNHelper/build.sh /tmp/easy-native-build
```

仅按当前 RootHide 约定生成 iphoneos-arm64e 包，内含 arm64/arm64e 两个
代码切片及 RootHide 对应 rpath；不承诺普通 rootless 兼容。
输出在父项目 `packages/`，保留完整源码和构建脚本。

## 2026-11-14 实测边界

目标设备 iPhone13,1 / iOS 16.3.1 / RootHide，目标 App 已有唯一系统配置，
测试前后目标及飞连均断开。

1. 独立临时包安装和包/Filter 回读成功。第一次依赖为 stock 绝对路径，
   修正为 RootHide rpath 后仍没有收到 helper 加载反馈。
2. 独立请求正常启动 App，但 stage 未更新、helper result 为 0、VPN 未连接。
   不能计为原生连接逻辑失败，因为 helper 未实际执行。
3. 系统 opainject 精确定位 Easy VPN 主进程。RootHide 映射路径修正后，
   dlopen 先返回 code signature invalid；仅对辅助文件调用官方 trustcache add
   后，变为 file system sandbox blocked mmap。没有关闭签名或沙盒校验，
   没有调用 proc_set_debugged，没有写入 App 沙盒。
4. 当前 `cn.zqbb.inject.plist` 未允许目标 executable。只读检查官方管理器，
   没有找到可用的允许注入 CLI；没有直接改配置或向管理器注入辅助。
5. Mobile GUI 自动化工具前置检查返回 mobile_not_authorized；未绕过该门禁，
   未进行 UI 点按或真实控制中心触控验收。
6. 已卸载 ayao.easyvpnnativehelper，确认 dylib/Filter 不存在，退出目标 App，
   删除设备独立工具、临时包及公共测试文件。目标 App 可执行文件双端
   字节一致；RootHideConfig.plist 和 cn.zqbb.inject.plist 均字节不变；
   本次窗口未观察到新增 Easy VPN、tunnel 或 SpringBoard 命名崩溃报告。
7. 调用了 trustcache add，未调用全局 clear。最终 trustcache info 中未找到
   本地最终包两切片的精确 CDHash，但这不足以证明信任缓存完全回滚；
   登记副作用保留为未确认项，不声称零残留。设备配置备份保留。

## 早期阻塞与后续验收

要验证辅助，必须先通过手机官方注入管理器 App List，仅对 Easy VPN
开启注入。不得同时开启其他 App，不得向阿里/蚂蚁/金融/京东 App 注入。
用户授权不等于工具运行时权限已满足；现有自动化通道受限时应披露阻塞，
不使用直接配置覆盖或更强沙盒绕过作为替代。

之后仍需重新验证：helper 确实加载、一次请求原生连接、真实 connected
和网络请求、断开与至少两轮重连、后台/冷启动、弹窗/认证失败以及清理。
早期只完成构建与安装/加载诊断。最新连接主路径见上文；仍不宣称完整
SDT 或 GUI 全流程通过，后续正式接入前应补齐未验证边界。

# 专注模式只读查询工具

通过系统 DoNotDisturb.framework 的状态和模式配置查询接口读取名称、时段、星期和活动状态。
不创建断言、不切换模式、不改定时规则、不修改配置或目录权限，不读取允许联系人、位置或设备标识。
权限键取自本次 iOS 16.3.1 设置 App 的原始签名，仅保留 state/request 与 modeconfiguration/request。
公开 iOS 17 runtime header 仅用于发现查询方法，实际调用仍要求目标运行时存在对应方法。

构建：`sh scripts/tools/focus-state-readonly/build.sh /tmp/focus-12mini-readonly/build`。
工具没有定时器、后台任务和网络服务；调用者必须对执行设置超时。
RootHide 执行可能需要临时信任注册；必须单独取得用户许可，不自动注册或注入其他进程。
当前只在 Mac 构建，尚未上传、信任注册或在手机执行，不构成规则或运行状态证据。

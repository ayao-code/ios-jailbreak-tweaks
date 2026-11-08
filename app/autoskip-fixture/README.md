# AutoSkipFixture

> 2026-11-08 仓库整理说明：原始截图、设备导出、历史测试包及详细日志已按用户要求清理。下文旧 `research/`、`evidence/` 路径仅描述当时记录，不代表文件仍在；保留正式源码、资源和必要交付包。此次整理未重新执行功能验收。

受控 UIKit 场景 App，直接编译仓库中 AutoSkipGuard 同一套正式源码；不是第三方 App 注入验证的替代品。

11 个入口：标准按钮、标签手势、禁用倒计时、关闭倒计时、箭头弹层、600ms 慢关闭、全屏图片 OCR、根页面按钮、双目标歧义、正常登录关闭反例、8秒后到广告。

`make -C app/autoskip-fixture` 构建 `dist/AutoSkipFixture_0.4.0.tipa`。测试构建才包含 `ASGFixtureStart`，正式 dylib 不包含。场景记录自己的 callback 到自身 Documents/fixture-action.plist，不自行生成插件提示。必须同时观察 callback、广告退出、顶部真实 Tips，不能仅凭 action 记录宣称通过。

2026-11-08 经用户明确授权本地真机操作，已在TrollStore安装并执行。企业Mobile GUI能力拒绝未被绕过，采用用户允许的本地手动操作。9种正向场景已同源实现及实际交付dylib两种形式验证退出和真实顶部提示；双目标存在原版覆盖差异，整体验收未通过。完整事实与限制见 research/autoskip-acceptance-local-20261108/ACCEPTANCE.md 。

`make original` 构建独立原版对照App，只打包用户原始dylib，签名可能被TrollStore改变但代码段回读一致。`make payload` 构建直接加载交付dylib的App，不包含ASGFixtureStart测试入口。URL场景入口仅在宿主内选择场景，callback自身不生成Tips。新增no-effect、natural-expiry、提示穿透检查。只读进程采样不是插件CPU增量基准。

## 0.4.5调度测试

新增empty-window与late-image-6场景；late场景保存实际展示uptime/runID到scene-presented.plist。验收必须先核对重新安装后是否仍是旧进程，正常结束独立测试进程再启动才能加载新文件，不能用安装文件hash代替运行版本。实际dylib退避记录已在本机iPhone验证，详见 research/autoskip-backoff-20261108/RESULT.md 。

隐私整理：原版对照安装包含上游个人编译路径，已移出公开仓库；原版对照源码保留，构建时需显式提供 AUTOSKIP_ORIGINAL_DYLIB。

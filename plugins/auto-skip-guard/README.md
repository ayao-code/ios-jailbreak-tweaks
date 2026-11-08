# AutoSkipGuard 0.4.6

用户授权发布的个人使用版本。TrollFools（巨魔注入器）应用内加载，arm64 / iOS 15+。正式包默认关闭诊断日志，不再使用 Dev 文件名。

## 使用

正式包：`dist/AutoSkipGuard_0.4.6_arm64.dylib`。

iCloud交付位置：`iCloud 云盘/AutoSkipGuard/AutoSkipGuard_0.4.6_arm64.dylib`。注入前在TrollFools停用或移除同App里的旧AutoSkipGuard，不要同时加载两版；启用后核对加载，正常重开App。App更新可能需要重新启用。实际注入目标仍以用户授权和项目RootHide隔离规则为准，不修改RootHide白名单。

## 行为

- 原生控件优先，识别跳过/skip/关闭广告及广告倒计时；不按App名称写特殊分支。
- 每次App进入活动状态，8秒总窗口，涵盖发现、点击与结果确认。OCR失败完成后等待0.25/0.5/1秒，后续封顶1秒，单请求在途，不固定第6次停止。
- 文字与真实目标绑定；普通弹层不只靠面积授权；OCR局部复读检查候选冲突，点击前检查局部画面变化。不确定时放弃并重新发现。
- 确认关闭后显示顶部“AutoSkipGuard · 已关闭广告”约1.5秒。发出动作但无效果、推广导航、近自然到期或证据不足不提示、不缓存。
- 成功、用户触摸、失活、期限结束提前停止识别。dylib驻留到App进程退出；系统截图/OCR不能硬中断，尾部回调可能超过逻辑期限。

## 资源

截图最大960x1600（RGBA像素约5.86MiB，不是插件/Vision总峰值），局部证据摘要8KiB临时持有。Vision模型/系统allocator可能缓存内存。没有daemon或无限识别队列。

正式构建`DIAGNOSTICS=0`不产生新诊断日志；定位缓存仍关闭。旧版已经留下的日志/文件不自动删除。发布构建仅移除诊断统计，不更改本轮功能逻辑。

## 发布验证与边界

- 同一功能逻辑的0.4.6-dev2诊断构建在独立iPhone受控App上12场景通过：正常广告与Tips，普通图片/重叠业务按钮/换图/OCR冲突反例，推广页不冒报成功。
- 正式0.4.6发布构建重新进行严格警告交叉编译、签名校验、本地策略/退避/Matcher/回调/缓存恢复/诊断模块测试、Clang analyzer。正式DIAGNOSTICS=0产物尚未单独真机复验，不沿用为“正式包已在所有App通过”。
- 局部像素摘要与广告类识别是近似证据，不能保证准确率100%；动态复读冲突、动图、特殊Web/canvas和真实第三方App仍有未验证边界。
- 没有充分CPU/phys_footprint/耗电增量基准，不能保证零开销。8秒后才出现的广告和连续后置弹窗不处理，瓜子特殊生命周期未更改。

## 源码与归档

正式可维护源码位于本目录的`.m/.h/.c`、`Makefile`、`scripts/`、`tests/`，不是只保留二进制。与本次正式包匹配的冻结快照及manifest：`releases/0.4.6/`。

仓库整理已移除旧 iCloud 重复归档、未使用调试输出和原始证据。`dist/` 保留正式包及手机仍使用的诊断版本，`versions/` 保留历史源码快照。源码和正式发布记录可提交；本次整理不更新手机插件或系统配置。

## 重建

```sh
make -C plugins/auto-skip-guard VERSION=0.4.6 DIAGNOSTICS=0
make -C plugins/auto-skip-guard check VERSION=0.4.6 DIAGNOSTICS=0
```

默认SDK为本机Theos iPhoneOS16.5。默认`make`已指向0.4.6/DIAGNOSTICS=0。若显式更改同版本的诊断开关，须移开该构建目标后再构建，避免Make复用同名已存在产物；发布产物及冻结快照不要覆盖。

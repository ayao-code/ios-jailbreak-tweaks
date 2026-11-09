# AiPowerButton 1.0.6 发布包与性能审计

## 交付状态

- RootHide发布包：packages/ayao.aipowerbutton_1.0.6_iphoneos-arm64e.deb。
- 版本、Preferences两个版本字段均1.0.6，无test/debug后缀；诊断宏均关闭。
- 保留全部正式源码。仅构建本次RootHide目标，未声称普通rootless 1.0.6已构建或验收。
- 用户确认test10+volumedebug3黑屏音量下双击可用；随后授权换装1.0.6。
- 1.0.6已安装并重载，SpringBoard PID 8323 -> 8556，包文件/加载代码校验通过，无新增相关崩溃。
- 偏好及4份RootHide隔离策略逐字节保留，音量下/锁屏相机保持开启；旧诊断日志重载后未变化。
- 安装证据：backups/aipb-release-1.0.6-20261109-104021/installation-readback.json。
- 未提交/推送或上传发布；发布版真实按键需用户复验。
- 生成可发布安装包不等于已完成所有验收；完整SDT仍因缺flux-sdt.yaml未初始化。

## 本轮变更

仅关闭诊断调用/字典参数构造、测试按钮Hook和诊断启动审计，同步发布版本。
没有变更已验证的音量双击时间、相机派发、黑屏点亮流程、AI录音实现或用户设置。
Filter继续仅SpringBoard、豆包、DeepSeek，未添加任何高敏App。

## 实际开销与解释

- 使用独立只读proc_pid_rusage采样器，12个样本/33.057秒，完整SpringBoard单核平均CPU约0.00528%。
- 全SpringBoard驻留内存106.656-106.672MiB，物理footprint 103.799-103.846MiB。
- 本窗口进程idle wakeups增加3次，累计磁盘写入增加0字节。
- 上述是整个SpringBoard且没有插件禁用对照，不能归因插件独占内存或插件单独CPU，也不能推出长期耗电为零。
- 不使用返回0的ps结果当依据：RootHide下普通/提权ps的CPU/RSS字段均不可用，原输出留在本地。
- 测试采样器12次后退出，设备文件已移除，没有附加调试器/任务端口/常驻服务，不进入发布包。

## 生命周期与设计

- 相机按键状态是固定大小的内存结构；闲置不轮询、不读偏好文件。偏好只在加载/通知时读取快照。
- 只有黑屏双击才建立一个最长1.5秒的单次超时；收到屏幕亮起事件后取消，超时/取消/设置变化同样释放。
- 显示Hook仅在存在待处理请求时投递主队列任务；每个有效请求按代次核对，旧异步请求不能重入新任务。
- 日志证据：wake_requested到wake_display_ready约61.919毫秒，后续锁屏相机派发；用户现场确认显示成功。
- 原AI链仍存在触发后的有限任务：DeepSeek侧键松开检查每0.1秒最多约60秒；豆包控件查找最多约4秒，DeepSeek最多约2.8秒；没有闲置循环。
- 录音、网络AI调用、屏幕和相机传感器本身会耗电；不能将这些系统/App业务能耗都记为按键识别器开销。
- 原AI有限重试、本轮未改；其私有手势/触摸实现是历史兼容风险，未宣称已经完成全链业务回归。
- 启用侧键双击相机替代钱包双击，音量下仍保留调音量事件；关机/SOS、三击、锁屏照片隐私完整验收未完成。

## 日志

- 当前诊断版实测64条约16116字节（15.74KiB），每个SpringBoard进程条数上限64、文件预算32KiB，不持续增长。
- 发布版AYCameraDiagnostic宏不求值任何参数，没有日志字典/NSNumber构造，没有日志文件路径和fopen/fwrite/NSLog导入。
- 两语音helper无新增日志；DeepSeek的业务偏好写入不是诊断日志，原样保留。
- 不自动删除手机旧诊断日志；已保存回滚/审计证据，发布版不会再写它们。

## 验证

- Sanitizer：9216相机矩阵+8边界、40音量时序、8侧键门控、128唤醒门控通过。
- 实际诊断头文件关闭模式编译验证：参数副作用为0，见tests/diagnostics_disabled_test.m。
- 包审计：版本一致、设置及Filter与成功诊断版相同，两个语音helper指令不变，日志字符串/IO导入/测试Hook不存在。
- 证据：tests/release-audit-1.0.6.json、tests/resource-sample-20261109.json及历史设备备份。

## 构建

```sh
THEOS="$ROOTHIDE_THEOS" make -C plugins/ai-power-button package FINALPACKAGE=1 \
  THEOS_PACKAGE_SCHEME=roothide AYCAMERA_DIAGNOSTICS=0 AYVOLUME_DIAGNOSTICS=0 \
  _THEOS_RELATIVE_DATA_DIR=.theos-release
```

不能仅凭无调试日志或包版本去掉test后缀就宣称所有功能稳定。正式安装后需用户正常解锁并复验黑屏/亮屏相机及AI长按，耗电百分比需要长时间同条件启用/禁用对照。

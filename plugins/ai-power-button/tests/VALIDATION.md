# 相机快捷键验证记录（2026-11-08）

## 1.0.6无诊断发布包（2026-11-09）

- 用户确认test10黑屏音量下可用；实际wake_requested -> 61.919ms -> wake_display_ready -> locked相机请求日志已保存。
- 本轮仅编译排除日志调用及参数构造、额外测试Hook/启动审计并同步版本，不改触发或相机/AI逻辑。
- 1.0.6 RootHide发布包已构建；Preferences/控制版本一致，设置/Filter保持、语音helper指令不变。
- 用户授权后已安装并重载，SpringBoard PID 8323 -> 8556；包文件/加载代码/偏好/4份隔离策略回读通过，无新增相关崩溃，旧日志未变化；未推送或上传发布。
- 安装证据backups/aipb-release-1.0.6-20261109-104021/installation-readback.json；发布版真实按键待用户复验。
- 12个只读原生样本33.057s，整个SpringBoard平均0.00528%单核CPU/RSS约106.656-106.672MiB，无插件归因/禁用基线，未测长时能耗。
- 原相机/音量/唤醒Sanitizer检查与实际关闭诊断参数不求值检查通过。包审计tests/release-audit-1.0.6.json。
- 仍需发布版安装后硬件回归，原AI业务链、系统组合键及锁屏隐私完整验收不因用户相机成功而视为全通过。

## 黑屏锁屏入口补齐候选（2026-11-09）

- 用户进一步确认：亮屏（含锁屏）音量下双击可用，仅黑屏锁屏无效；上一轮日志已有locked=true相机请求，但屏幕显示没有证据。
- test10+volumedebug3仅补音量下黑屏路径：经签名检查读取已有SBBacklightController.screenIsOn，确认屏幕关才请求SBSUndimScreen。
- 等待CoverSheet显示/背光事件，并再次确认screenIsOn、仍锁定、同请求/同偏好代次及按键/录音保护条件后，使用原受限锁屏相机入口。
- 不调用解锁、不修改认证/照片权限；自然解锁时取消，不回退普通相机启动。亮屏调用路径和双击时间不改。
- 一个最长1.5秒的单次超时，完成/取消后释放；无轮询或常驻任务，设置/锁状态/组合键变化取消，旧代次不能激活新请求。
- Address/Undefined Sanitizer下：原9216相机矩阵+8边界、40音量时序及8种侧键门控、新128组唤醒激活门控通过。
- RootHide候选构建、Filter/设置和语音helper指令比较通过，package-audit-volumedebug3.json；只构建此次目标RootHide包。
- 用户确认后test10+volumedebug3已安装并重载，SpringBoard PID 7926 -> 8049且短时稳定；包文件/加载指令/RootHide标记校验通过，4份隔离策略和偏好未变，无新增相关崩溃。
- 启动回读screenIsOn为B16@0:8、setBacklightLevel:为v24@0:8d16、CoverSheet显示/视图回调存在；volumeDown和锁屏相机保持开启。
- 安装证据：backups/aipb-dark-wake-20261109-091448/installation-readback.json。
- 黑屏物理双击、唤醒符号实际调用与事件就绪/取消行为、受限相机前台尚待用户复验，不标完整修复。

## 锁屏后音量触发被拦诊断（2026-11-09）

- 用户反馈解锁可以、锁屏不打开。诊断记录2次locked=false相机派发，随后侧键交互后的2次音量按下均sideDown=true/permitted=false，没有进入锁屏相机分支。
- 64条日志已达到本轮上限，不将未记录的后续尝试当作失败/成功证据；记录见已安装诊断备份目录after-user-unlocked-locked.jsonl。
- 已构建test9+volumedebug2候选：保留侧键按下对象弱引用，在音量判定时读取经ABI检查的原生isButtonDown；系统确认up才清除本地标志，未知/仍down保持保护。
- 不改双击窗口、原音量事件、语音helper、相机派发或锁屏认证；只修复依赖最终up回调导致的过期侧键标志。
- 9216相机矩阵+8边界、40音量时序、8种原生状态门控及缺最终up的松开恢复回归通过，Address/Undefined Sanitizer开启。
- package-audit-volumedebug2.json已核对；设置/Filter原样，两个语音helper指令与上版一致。新日志aipb-volume-test9.jsonl，避免旧轮日志上限。
- 用户确认后test9+volumedebug2已安装并重载，SpringBoard PID 7028 -> 7186。安装文件/加载指令/RootHide标记校验通过，4份隔离策略和偏好不变，无新增相关崩溃。
- 启动诊断确认isButtonDown为B16@0:8、initial/final up接口存在，hooksReady/permitted均true；音量下与锁屏相机选项保留开启。
- 安装证据：backups/aipb-volume-lockfix-20261109-021028/installation-readback.json。锁屏物理双击和原生受限相机前台待用户复验，不声称完整修复。

## 音量下失败诊断准备（2026-11-09）

- 用户报告test8音量下无效；不能以编译、策略测试或安装成功推断真实硬件可用。
- 用户确认选好后，当前偏好已回读cameraTrigger=volumeDown，enabled/相机开关均开启。
- test8诊断关闭，旧日志不包含本次事件；实际音量Hook ABI、modifier和cancel时序未观察。
- 已构建1.0.6~test8+volumedebug1；仅补有界日志，不改识别逻辑、不屏蔽媒体事件，不安装额外侧键诊断Hook。
- 最多64条/32KiB本地日志，路径aipb-volume-test8.jsonl；设置和Filter与test8一致，3份其他重新编译程序指令不变。
- 用户确认后诊断包已安装，SpringBoard PID 6840 -> 7028；全部包文件、加载指令与RootHide标记校验通过，4份隔离策略和偏好未变。
- 当前启动日志确认volumeDown已读取、hooksReady=true、permitted=true；iOS16.3.1实际音量down/up/cancel接口编码匹配。
- 诊断包审计见package-audit-volumedebug1.json；安装证据见backups/aipb-volume-diagnostic-20261109-015642。
- 尚未取得用户本次物理双击事件流，等待一次按键后回读；门禁不通过与配置未读取已排除，媒体冲突仍未证实。
- 当前设置问题已排除；媒体冲突、双击窗口过紧、门禁或取消事件均未确定为真实首因。

## test8：实体Home替换为音量下（2026-11-09）

- 已先读取手机test7安装状态、全部当前按钮/相机源码；本轮不改侧键AI与相机派发逻辑。
- 移除SBHomeHardwareButtonActions相机Hook；选项为side/volumeDown。旧home值仅在内存中映射，未写设备偏好。
- 新状态识别第二次短按松开：每次<=0.25秒、首按到第二松开<=0.45秒；重复down拒绝整次按压。
- 音量下按下/松开全部放行，音量上/侧键/取消/锁状态/偏好变化重置，录音或组合保护不派发。
- 无新增轮询、定时器、后台服务；未知私有ABI不启用新Hook，状态只在主线程处理。
- AddressSanitizer/UndefinedBehaviorSanitizer：原相机9216矩阵+8边界、新音量40矩阵与复位/长按/重复/非有限时间边界通过。
- 仅为已确认RootHide手机构建iphoneos-arm64e包；未构建普通rootless test8包。
- 包内版本、设置和Filter回读通过；原两语音helper代码与test7一致；审计在package-audit-test8.json。
- 用户随后明确授权重新安装和SpringBoard重载；test8已安装，包内文件逐项回读一致。
- 已有偏好逐字节保留，cameraTrigger仍为side；没有自动替用户切换到volumeDown。
- SpringBoard重载后PID 6539 -> 6634；三份dylib只出现RootHide段名填充/对应首代码页哈希标记，
  指令字节一致、全部代码页哈希有效。四份隔离策略和偏好重载后不变，无新增相关崩溃报告。
- 安装证据位于backups/aipb-volume-down-20261109-013756/installation-readback.json。
- 公开iOS17头文件用于发现接口；当前iOS16.3.1实际运行ABI由安装后门禁检查，尚未验收音量下物理事件。
- 待实际接口/物理按键验收：相机前台、音量调节、原侧键AI、侧键相机、音量+侧键/SOS。
- 双击音量下仍会正常调低音量，不是静音替代键；真实按压、锁屏隐私、耗电没有验证结论。

下文test3-test7为历史记录，不当作test8已安装或已验证。

当前候选：1.0.6~test3。2026-11-08 用户明确允许安装后，已替换设备上的 1.0.5；回滚包与双端原文件备份保留。

## 已执行

- 真实运行路径使用 AYCameraDecide 三态策略：放行、发起相机、吞掉重复事件。
- 9216 组参数组合及 8 个边界/保护优先级用例通过，开启 AddressSanitizer、UndefinedBehaviorSanitizer。
- 组合包含禁用、侧键/实体 Home/无效触发配置、未知锁状态、锁屏允许/禁止、录音、电源保护、无历史/重复/过期/无效时间。
- 配置更新清除旧防抖，重复事件不再次派发，禁用/锁屏限制/录音/电源保护优先于重复吞掉。
- 两环境构建、包内版本/Filter/plist、RootHide dylib 安装名检查通过，包审计保存在 package-audit-test3.json。

## 待完成的实机验收

- 用户确认实体按键；当前 iPhone 12 mini 没有实体 Home，按其侧键准备测试，AssistiveTouch 未实现。
- 已获安装授权并完成安装及 SpringBoard 重载，PID 2654 -> 3786；文件逐项回读一致，4 份隔离配置与偏好字节未变。
- 当前查询到锁屏且密码开启，UI 验收等待用户正常解锁；新增相机开关仍默认关闭，未擅自改变钱包双击行为。
- 私有方法实际存在、双击真实触发、相机到前台、系统钱包/多任务不重叠、受限锁屏相机及认证。
- 原长按 AI、录音发送、单击、三击、音量加侧键关机/SOS 回归。
- 实际 CPU/内存；策略函数没有轮询或新增定时器，但不等于整插件零耗电。

重载后回读发现 DoubaoPowerButton arm64e 切片仅有 8 字节节名称填充元数据及对应 32 字节签名页哈希变化；可执行代码与包一致，所有代码页哈希有效，依赖链接正常。该证据不能替代真实双击触发或相机前台验收。

因手机持续锁屏，暂时停止 GUI 验收并移除一次性验收工具；AiPowerButton 1.0.6~test3 和原偏好保留，相机开关仍默认关闭。等待用户正常解锁后续接，不自行输入或绕过密码。

## 正常解锁后续接

- 用户回复已解锁后，独立验收工具重新安装，实时查询确认设备未锁定。没有修改密码或认证设置。
- 通过系统设置打开 AiPowerButton，新相机设置分组可见、侧键选项正确、两个新开关关闭，页面正常渲染。
- 准备开启相机开关前，前台自行切到分身工坊；再次进入设置后又切到已解密文件页面。输入工具两次拒绝发送点按，未修改任何业务 App。
- 完整回读确认 AI 原偏好逐字节未变，相机开关仍关闭，四份隔离策略未变。真实双击尚未执行，当前阻塞是无法保持稳定的独占验收现场，不再归因于锁屏。

## test4-test7 根因与后续证据

- 后来用户打开了相机/锁屏相机设置；test4 实机记录已正确读值，iOS 16.3.1 的按键、锁状态和 CoverSheet 相机接口实际存在。
- 独立有限 HID 双击工具触发初次/第二次按下，但 `_shouldWaitForDoublePress=false`，未收到双击执行回调；test5 补齐启用时原生等待双击门控。
- test5 重载时偏好文件开启而 CFPreferences 读为关闭；test6 通过 RootHide `jbroot` 读取一次偏好快照修复，记录完整 double_received -> decision=launch -> camera_dispatched。
- 用户要求暂时关闭时保存配置并关闭长按 AI/相机；再次要求开启时，只开启这两个开关，保留 DeepSeek、侧键及锁屏相机关闭状态。
- 再次运行有限按键事件工具后，当前截图显示完整相机前台。该工具不调用打开相机 API，只发四个侧键 HID 事件；不拍摄、不访问照片、不自动解锁。
- test7 关闭诊断写入，并让 AI/相机从同一偏好快照取值；源码和构建与手机安装情况需分别标识。
- 尚未验证真实按压、原 AI 录音发送回归、三击/SOS 及有密码锁屏相机隐私。不得称正式完成。

test7 已安装、重载及回读，新开关保持开启、锁屏相机关闭，四份隔离策略未变、未新增崩溃报告。重载后手机锁屏且密码开启，最新包运行回归未完成；临时验收工具已移除，不保留后台测试服务。

本地测试不证明真实硬件事件、系统 API 或锁屏隐私已验收。

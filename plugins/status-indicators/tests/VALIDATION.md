# 本轮验证记录（2026-11-08）

## 通过

- StatusIndicators 0.1.0~test2、AiPowerButton 1.0.6~test2 均完成普通 rootless 及官方 RootHide Theos 构建。
- 包内 plist 语法检查、control/Preferences 构建版本一致性、精确 Filter、RootHide dylib 安装名检查通过。
- 流量及相机策略 C 测试通过，开启 AddressSanitizer/UndefinedBehaviorSanitizer；包含 64 位跨 4 GiB、计数重置、接口替换、异常时间间隔、未知锁状态、录音/电源保护、禁用及无效按键配置。
- Mac 三轮真实网卡读取：1 个物理接口，首次只建基线；后两轮有效差值。该证据只证明 Darwin 采样路径可运行，不是 iPhone 测量。

## 早期失败与当前待执行

- iPhone 12 mini、iOS 16.3.1、RootHide 上 /tmp 采样探针执行退出 137，arm64/arm64e 及重新签名亦无结果。后续查到官方文档禁止加载越狱根 /tmp、/var 下 Mach-O，当前探针路径违反该约束；需要正式路径测试才能证明采样逻辑。
- 后续用户明确授权安装：StatusIndicators 0.1.0~test3 与 AiPowerButton 1.0.6~test3 已安装，SpringBoard PID 2654 -> 3786。所有包内文件回读一致，4 份隔离策略和原偏好字节未变。未改变 VPN/定位开关或系统信任。
- 独立一次性验收工具包 ayao.statuscameravalidation 0.0.1 曾安装到 /usr/libexec/；网络探针三轮成功，退出 0。工具不注入、无 daemon；因持续锁屏无法继续验收，现已通过 dpkg 移除并确认三个可执行文件不存在。源码复用本项目 tests/network_probe.c 和已有 screen-observe/ui-input 项目工具，后续解锁后可重新部署。
- 当前锁屏且密码开启，截图黑屏；新增开关仍默认关闭，需用户正常解锁后继续官方设置 UI 和按键验收，不绕过认证。
- 待验收：真实状态源/初始状态、跨 App 窗口及旋转、熄屏停止采样、Waqt 布局、CPU/内存、真实双击、受限锁屏相机、原 AI/三击/SOS 回归。
- 用户确认实体按键，当前手机无实体 Home，按实体侧键准备测试；小白点未实现。

因此当前不满足正式发布或“手机已生效”的验收标准。

## test3 后续改进

- 去掉额外覆盖窗口，标签放进现有 _UIStatusBar，初次读取各宿主 currentData，不再消费任意聚合器的中间数据。
- 宿主弱引用注册上限 8；启用/亮屏查找上限 512 个视图，禁用不处理布局事件。
- 状态栏隐藏/无可见宿主取消采样；标签跟随宿主旋转和显隐，缺失当前字段不保留旧的活动状态。
- 上述是新增实现，实机验收仍未执行。
- 避免空标签在每次布局时反复隐藏/显示；frame 不变时不重复赋值，减少布局再入和无意义的视图更新。
- test3 两目标包均构建通过；包内版本、plist、仅 SpringBoard Filter、RootHide 安装名检查通过，审计及 SHA-256 保存在 package-audit-test3.json。

## 重载后文件审计

- 安装当时全部 payload 与包逐字节一致；后续回读 19 个文件，StatusIndicators/DoubaoPowerButton 两个 dylib 出现各 40 字节变化。
- 差异仅在 arm64e 切片 __text 节的 segment-name 尾部 8 字节填充区及对应首个代码页 SHA-256 槽；所有可执行代码未变、所有代码页哈希校验通过。arm64 切片无变化。
- 这与加载后元数据处理一致，但没有仅凭标记宣称 UI 已工作，也未覆盖文件或重装。
- 依赖 .jbroot 链接与 substrate 路径存在；四份隔离策略、AI/Waqt 原偏好仍逐字节一致，未发现新增崩溃报告。
- 状态偏好尚未创建，新开关未启用；手机仍锁屏且密码开启，功能验收待正常解锁。
- 等待期间移除临时工具后，再核对两个插件仍安装、四份隔离策略未变。没有为推进自动目标而解锁、改密码或启用快捷动作。

用户正常解锁后已恢复截图和系统设置导航，AiPowerButton 新页可见；但前台两次在点击前转为分身工坊/已解密文件，输入工具拒绝操作。状态栏主开关尚未启用，当前待稳定独占的手机 UI 场景，不能写成显示已验收。

## test4-test6 后续验证

- test4 修复 RootHide 偏好读取；只创建/启用插件自身偏好并调整标签位置，没有写 VPN/定位总开关或业务 App 配置。
- 日志已记录可见宿主、label、timer=1；状态栏不可见时 timer=0；回到可见时 timer=1。屏幕通知已有亮/灭状态记录。
- 实机截图显示下载 3K/s、上传 1K/s 随后更新。独立物理接口三轮快照通过。
- test4 宽底板遮挡系统图标；test5 已去掉底板、缩小为透明小字，当前截图不再覆盖 Wi-Fi/电池，深色页对比仍不足。
- test6 补细反色描边并关闭日志；描边效果、VPN/定位活动切换与 CPU/内存/耗电尚未实测，不能把代码上限写成实测资源上限。
- 期间手机被用户/其他任务切到高敏业务页面，仅观察屏幕，不点按、不读取沙盒、不附加或注入该进程。

test6 已安装、重载、回读及包内版本/Filter 检查通过，配置保持 enabled=true、rightAnchor=true、offsetX=-20、offsetY=0。重载后锁屏且密码开启，最新描边视觉效果尚未确认。四份隔离策略未变、无新增崩溃报告，临时验收工具目录已移除。

## test7 纯净独立显示

- 按用户要求改为锁盾 VPN 图标、定位箭头、纯数字网速，无底板、描边或 D/U/LOC 文案。
- 每项独立横向百分比、纵向偏移及大小；网速支持下载/上传/双行、单位开关。纯数字固定 KB/s，保持量纲一致。
- 旧配置不删除不迁移，仅停止消费旧整组位置键；位置修改不重启定时器，尺寸仅在文字/字体变化时重新计算。
- presentation_test.c 验证固定量纲/单位、无效数值、默认独立位置和 402 组边界/旋转布局；ASan/UBSan 通过。该测试只证明几何/文本算法，不代表实际手机渲染或旋转已通过。
- RootHide test7 候选已构建，包内版本/Filter/plist 检查通过。
- 用户授权后已安装 test7，全部包内文件在重载前逐字节匹配；SpringBoard PID 5474 -> 5648。状态栏/Waqt 偏好及四份隔离策略在重载后回读原样保留。
- 仅更新状态栏包，未安装或修改 AiPowerButton；安装即时检查其偏好未变，后续回读发现 cameraOnLockScreen 从 false 变 true，属于安装后其他操作造成的未归因变化，未覆盖。不能声明所有非目标偏好在整个期间均未改变。
- 新版独立图标/数字外观与设置调整尚未截图验收；安装成功不等于全部显示功能验证通过。

## test8 设置与样式扩展

- 六个设置资源页、35 项配置：独立图标样式、网速排列/单位/小数/方向/无流量隐藏、颜色/字重/透明度、横屏独立位置。
- 位置示例预览共用 SIConfiguration 与 SIItemViews，模拟状态明确标注；选择项目拖动仅在结束时写该项两个位置键，取消不写回，无后台采样/联网/GPS。
- 横屏未配置位置继承竖屏，设置列表读值也同步继承；字体/颜色/图标变化不重建计时器，现有数值样本直接重新格式化。
- presentation_test.c 的 576 种样式组合、12 个格式/无效/隐藏边界及 402 个布局边界通过 ASan/UBSan；RootHide 构建、版本、plist、精确 Filter 和预览类打包检查通过。
- 真正手机设置页、样式切换和拖动保存尚未验收，不写“NiceBarX 所有功能已复刻”。
- test8 已按此前安装授权更新到手机，11 个 payload 文件在重载前逐字节一致；SpringBoard PID 5648 -> 5941。重载后状态栏、Waqt、AiPowerButton 三份偏好和四份隔离策略均字节不变，无新增崩溃报告。

## test9/test10 入口和显示生命周期修复

- 用户反馈设置入口不出现、显示似乎仅在控制中心；之前只以配置存在证明入口已可见是验收缺口，明确更正。
- 入口缺少 isController=true。DhinakG/PreferenceLoader 的 prefs.xm 明确仅为该标记入口设置 lazy-bundle；test9 补标记，并让 root/子设置页显式从本 bundle 加载资源。
- 修复后真实设置截图已显示“状态指示 -> 网速位置与样式”子页及实际网速数字，入口恢复有直接视觉证据，不只是文件存在。
- 诊断快照证明外层 UIStatusBar_Modern 的 alpha/hidden 会独立改变；test10 监听该外层的显隐、挂载和布局事件，BOOL ABI 同时接受 B/c，不改变系统返回/行为。
- test10 已构建、安装和重载，关闭诊断输出；11 个文件即时回读一致，四份隔离策略及状态栏/Waqt 偏好未变、无新增崩溃报告。
- 普通系统设置页的顶部已看到数字，不是仅控制中心；桌面、更多 App 的覆盖仍未完成。相机截图为全黑，不足以证明全屏隐藏，不将其计为通过。
- 其他任务/用户期间修改 AiPowerButton 的触发按键与配置，保留该无关改动，不覆盖、不沿用旧版本断言。仅本状态栏插件的安装范围保持不变。

## test11-test13 本轮用户反馈修复

- 用户实测反馈：字号不一致/无法改、样式与位置生效迟、无标题位置滑块、控制中心显示与收回残影。此前未完整验收这些项目，修复不得写为全部已通过。
- 移除定位状态读取、显示视图、设置页及预览；仅 VPN 和网速。保留旧键但无消费者，因此旧 showLocation=true 不会使其显示。
- 项目所有设置 getter/setter 及预览使用 SISettingsStore，先原子替换并语义回读再 notify_post；不依赖 cfprefsd 延迟落盘。收到通知重新用当前数值采样渲染，无额外延时/采样重置。
- 统一字号默认 10 点，可在网速页精确输入；VPN 默认共用，单独大小开关控制独立值。三种数值控件已改为带标题、单位和范围的文本输入，界面说明左右/上下/字号差别。
- 文字使用实际字体和自然尺寸测量，单双行按实际文本切换；不把固定小框当字号。无底板/描边/阴影/光效。
- 排除控制中心、多任务、复用池和半透明过渡宿主；控制中心遮盖普通状态栏时也取消显示。隐藏移除视图并清理动画，更新视图禁隐式动画。这只是代码处理，尚不能证明所有系统截图缓存/过渡都无残影。
- settings_store_test.m 在 Mac 使用同一存储实现，通过 XML/binary 保留、非目标键/权限/last-good、回读先于通知、锁竞争/坏值/坏 plist 拒绝；presentation/rate 测试通过。RootHide 候选构建通过。
- 手机锁屏且密码开启，真实设置确认后即时变更、字号与控制中心切换验收未执行；不尝试解锁。最新安装结果单独回读记录。

## test14 解锁后验收续接（2026-11-09）

- 用户解锁后实时确认未锁定，设置入口和 VPN/网速设置页均真实可见，定位项目已移除。
- 通过设置页关闭 speedHideZero，随后读取正式配置确认立即保存；当前实际文字仍未出现，因此该事实只证明持久化，不证明即时渲染。
- 用户已有 speedX=92.40%、speedY=-14.97、speedFont=6.848 等自定义配置保留，未自行改成默认位置/字号来伪造验收。
- 为定位可见性，安装 test14：增加窗口/宿主与插件自身配置的请求式快照，数值显示两位小数；不扫描账号/业务数据、不增加持续采样。
- 诊断快照采集时屏幕已经熄灭：宿主可见、控制中心未呈现、screenOn=false、timer=0。截图黑屏，不能解释此前亮屏无字的根因，也不能判定单双行、字体或残影通过。
- 重载后手机重新锁屏且密码启用；正常唤醒 API 没产生可用画面，不输入或绕过密码。停止继续换版/重载和 GUI 点击。
- 本轮临时关闭的 speedHideZero 已按当时值逐项恢复为用户原来的 true，保持原格式及其他键，回读确认，并通知刷新。完整记录与截图保存在本轮私有 backups/si-accept-*。
- 当前仍是 test14 有限诊断包；完整显示缺陷未解决，不称“修复完毕”。


## test15 亮屏根因定位与修复

- 用户澄清“解锁，不是结束”后续接，不把前次停止当作永久取消。
- 同一时段截图显示正常 Preferences/AiPowerButton 页面，快照 screenOn=true，控制中心 isVisible/isPresented=false；UIStatusBarWindow 外层 alpha=0，而 SBMainSwitcherWindow 中的 _UIStatusBar 与外层 alpha 均为 1。
- 旧 SIHostVisible 仅因祖先类名包含 Switcher 排除了该可见宿主，导致 visible=false、timer=0。此处不显示的直接原因是把正常 App 状态栏误认作多任务，不是保存延迟。
- test15 去掉 Switcher 类名排除，保留控制中心和复用池过滤，未扩展 Filter 或注入业务 App。构建、包内版本/plist/精确 Filter 检查通过。
- 已安装 test15，7 份配置（四份隔离策略、状态栏、AiPowerButton、Waqt）在重载后逐字节一致，无新增崩溃报告。重载后锁屏且密码启用，未绕过解锁。
- 最新正常页面显示、字号/位置/单双行即时变化、控制中心残影与真实多任务行为仍未证明，不把过滤补丁写成全部通过。临时独立验收工具暂留以续接本轮，无后台服务/常驻任务。

## test15 解锁后实机续验（2026-11-09）

- 通过新授权测试设备只读确认同一台 iPhone 12 mini、iOS 16.3.1、RootHide；test15 的 RootHide payload、偏好和 `install ok installed` 状态均存在，未重装、未重载 SpringBoard。
- 请求式快照确认普通前台状态栏宿主为 `SBMainSwitcherWindow`，`visible=true`、`timer=1`、`rateValid=true`；这验证了 test15 不再把正常前台状态栏误排除。状态栏放大截图实际显示 `↓4K ↑2K`，不是“没有渲染”。
- 临时关闭 `speedHideZero` 后保存耗时约 3.3–10.6 ms，语义回读成功；触发采样后截图显示零速率文本链路可见。测试结束后恢复为原值 `true`，与本轮前备份逐项语义一致。
- 控制中心打开期间快照为 `isPresented=true`、插件 `visible=false`、`timer=0`，未向控制中心添加文本；通过顶部空白退出并等待稳定后恢复为 `isPresented=false`、`visible=true`、`timer=1`，截图未见持久残影。
- 回读确认 AiPowerButton、Waqt、RootHide 配置与本轮前备份语义一致；当前 CrashReporter 目录无新增文件。三份隔离策略文件在本设备当前路径不存在，因此未伪造比较结果。
- 临时包 `ayao.statuscameravalidation 0.0.5` 已用标准 sudo + dpkg 移除，手工部署的 `notify` 残留也已删除并确认工具目录不存在；主包、主 payload 和状态偏好保留。
- 本轮确认的是普通设置页和一次控制中心稳定进出，不等于 VPN 活动切换、全屏/横屏、真实多任务、所有 App 覆盖或 CPU/内存实测通过；当前仍是有限诊断 test15，不宣布正式发布。


## test18 formal-release review (2026-11-09)

- RootHide `iphoneos-arm64e` package built successfully. Release build keeps `SI_DIAGNOSTICS=0`; diagnostic JSONL/snapshot code is compile-time excluded from the package.
- Sampling uses one serial utility queue and one dispatch timer, interval bounded to 1-5 seconds; timer is cancelled when disabled, screen is off, status bar is hidden, or speed display is disabled. Each sample uses a fixed 64 KiB transient buffer and at most `SI_MAX_INTERFACES` records; no retained sampling history.
- Settings UI export filename now uses `StatusIndicators-Configuration-yyyyMMdd-HHmmss-XXXXXXXX.plist` with POSIX locale and an 8-character UUID suffix, so consecutive exports do not overwrite the same temporary file.
- Package audit includes version/architecture, plist syntax, PreferenceLoader icon declaration, 1x/2x/3x icon resources, new VPN symbol, absence of removed VPN symbols, and no unrelated high-sensitivity App Filter changes.
- Existing presentation/rate/settings-store tests pass under ASan/UBSan where applicable.
- Formal package is release-scoped for the verified RootHide arm64e target; ordinary rootless arm64 was not rebuilt or revalidated in this round.

## ForegroundInactive host and dynamic-color fix (2026-11-11)

- 在 iPhone15,3 / iOS 16.3 / RootHide 设备上，首次诊断发现旧逻辑只接受 `ForegroundActive`，会把 SpringBoard 承载的普通前台状态栏误判为不可见。代码现允许可见的 `ForegroundInactive` Scene，同时拒绝 Background/Unattached，并在同一 Scene 出现 Control Center、CoverSheet 或 NotificationCenter 时隐藏。
- 锁屏路径只监听 `SBLockScreenManager._reallySetUILocked:` 触发布局，不在布局判断中主动初始化锁屏单例，避免启动阶段的 dispatch-once 重入风险。
- 真实前台截图确认修复前汽水音乐页面已有网速文字，但颜色为黑色并与深色背景对比不足；原因是读取 `_UIStatusBar.foregroundColor` 得到了瞬态 legibility 层颜色。当前未配置颜色默认固定黑色；用户明确选择“跟随系统”时才读取系统颜色，固定白/自定义颜色路径保持不变。
- 最新 RootHide arm64e 包完成构建，离线 presentation/rate/network 测试通过，`git diff --check` 通过；包 Filter 仍仅为 `com.apple.springboard`。trait 颜色版本包 SHA-256 为 `0711c9af2ea42f0ff1bbbf0cbf6b0eb28c87f1a76b1805f4cf27beba8a8a8bfe`。
- trait 颜色版本已安装到目标设备并回读为 `install ok installed`，SpringBoard 无新增崩溃。安装前观察工具确认设备已解锁；安装重载后设备重新进入密码锁屏，因此颜色修复后的前台截图尚未取得，不能写成颜色已实机截图验收。设备解锁后需补一张截图确认白色文字及灵动岛收起后的最终位置。

## Dynamic centered group centered1 (2026-11-13)

- 新增可选动态居中排列：当前显示的 VPN、总静音和网速组成一个整体，以状态栏中心排列；项目间距默认 6 点可调，网速预留宽度默认 42 点可调，避免速率文本变化导致两侧图标抖动。关闭开关时继续使用原有独立横向位置；颜色、纵向偏移和固定锚点逻辑未改变。
- 本地 `presentation_test`、`rate_test`、plist 语法检查和 `git diff --check` 通过；RootHide Theos `958fea4f779943505b15b93c88bb4db8d97b346d` 编译 `arm64e` 主 tweak 与 Preference bundle 通过，保留 `SI_DIAGNOSTICS=0`。
- 包 `ayao.statusindicators_0.1.0+centered1_iphoneos-arm64e.deb` 已保存在 `packages/`，控制信息为 `Package=ayao.statusindicators`、`Version=0.1.0+centered1`、`Architecture=iphoneos-arm64e`，SHA-256 为 `f6624a2fc03eb2cc8fc29d5feb20f39dec706e2011513fcb4ef8030ab681ca1d`；Filter 仍仅为 `com.apple.springboard`。
- 已安装到已确认的 `iPhone15,3 / iOS 16.3 / 20D47 / RootHide`，设备端回读为 `install ok installed`、`0.1.0+centered1`、`iphoneos-arm64e`；安装前后 `ayao.statusindicators.plist` SHA-256 均为 `e8bb25c345b6fe51354f06c4626a2133313f98da2e94358411e58826e70bf4ae`，SpringBoard 重载后 `launchctl` 状态为 `running`，近期未发现 SpringBoard 崩溃文件。
- 本轮确认的是构建、安装、配置保留和 SpringBoard 恢复；动态居中在真实 VPN/静音/网速组合下的视觉间距、灵动岛展开收起和横屏效果仍需解锁后截图验收，不把安装成功写成视觉验收通过。

## Dynamic centered settings entry centered2 (2026-11-13)

- 用户反馈主页面没有看到“启用动态居中”。回读确认 `centered1` 包内该开关实际位于“颜色、字重、透明度”二级页顶部，主页面只有入口名称，容易被误认为缺失。
- 已将“启用动态居中”“项目间距”“网速预留宽度”移动到 Root 主设置页，Appearance 页恢复为颜色、字重和透明度设置；配置键和默认值不变，运行逻辑不变。
- RootHide `iphoneos-arm64e` 包 `ayao.statusindicators_0.1.0+centered2_iphoneos-arm64e.deb` 构建并安装成功，设备回读为 `install ok installed`、`0.1.0+centered2`、`iphoneos-arm64e`；主页面资源包含 `centeredGroup`、`groupGap`、`speedGroupWidth`，Appearance 资源不再包含 `centeredGroup`。
- SpringBoard 已重新加载；本轮仍未开启动态居中开关，未改变用户当前布局配置。

## Focus12 独立状态监听候选（2026-11-14）

- 包版本 `0.1.0+focus12`，RootHide `iphoneos-arm64e`；Theos 构建通过。主 tweak 与 Preferences 版本一致，Filter 仅 `com.apple.springboard`，安装名使用 `.jbroot`；包内没有旧 FocusSettings 查询身份、旧 Darwin Focus 提示、Focus 诊断树及运行日志路径。
- `tests/run-focus-monitor.sh` 用真实 `SIFocusMonitor.m` 配合 Foundation 假 DND 状态/服务执行；ASan/UBSan 通过。覆盖四内建模式/其他模式、活动/关闭/未知区分、关闭优先于残留标识、重复启用、初始查询与实时事件竞争、停用/重启后的旧回调、查询/注册失败及有效回调恢复、立即取消和销毁注销。
- VPN 测试提取控制器实际 `readStateForHost`/`hostDidUpdateData` 方法到假宿主执行，验证多宿主同轮更新、已有缓存、重复事件、明确断开、隐藏/禁用/释放宿主以及 Focus/静音未变。另执行实际 `SIItemViews.hide`，确认六个视图均隐藏，包括专注文字。假宿主不证明 UIKit 可见性或视觉动画通过。
- 现有文本/几何测试通过：576 种样式组合、12 个格式/无效/隐藏边界、402 个布局边界；rate 测试和 settings store 测试通过。
- 当前颜色、宿主选择、几何与固定锚点、动态居中、网速采样实现逐段与本轮修改前一致，哈希记于 `focus12-package-audit.json`。本轮只修改 Focus 显隐与透明度对称，不修其他配置导出/预览缺陷。
- 候选包 49,312 字节，SHA-256 `06486b5d44b3c05c03b094b3633a724219a45d07ada9686d9452040580c22e3b`。源码及包内嵌套内容敏感信息检查无命中；未提交或推送，不把正则检查称为绝对安全。
- 无 Focus 的 `0.1.0+centered2` 原包及 34 个归档输入逐项哈希校验未变；不覆盖回滚包或快照。
- **未安装、未重载、未改设备配置。目标 iOS 16.3 的 DND 监听 ABI/注册成功、状态对象/实际模式标识、四模式切换与关闭、跨 App/锁屏/控制中心 UI，以及插件专项 CPU/内存/耗电仍未实机验证，不作为正式发布。** 实际 API 不兼容或查询/监听失败时未知状态不显示活动图标；不再从旧 UI 快照兜底，也不新增轮询。

### focus12 用户授权安装回读

- 随后用户明确授权安装。核对目标 `iPhone15,3 / iOS 16.3 / 20D47 / RootHide` 后完成 Mac/设备双端备份；上传包哈希一致，`dpkg -i` 从 `focus11` 更新到 `focus12`，回读 `install ok installed / iphoneos-arm64e / 0.1.0+focus12`。
- SpringBoard 重载后恢复 `running`。15 个包内文件回读，14 个逐字节一致；主 dylib 差异 40 字节，执行代码段和字符串段均逐字节一致。设置组件版本、SpringBoard-only Filter 回读正确。
- 状态栏配置、RootHide 隔离配置、AiPowerButton 和 Waqt 配置字节/语义未变。锁屏音量插件的 `totalSilenceEnabled` 及两个快照键在安装窗口变化，已记录并保留；本插件只有读取路径，未向该配置写入，但不将变化归因于用户或其他进程。完整备份与证据不入仓库。
- 核对真实系统根 `/rootfs/var/mobile/Library/Logs/CrashReporter` 及 analyticsd 目录，安装后检查窗口未发现新增 SpringBoard 报告。**安装和运行恢复已确认；DND 监听注册/四模式实时切换、关闭残留、VPN/静音视觉独立性以及资源实测仍未确认。**

## Focus13 模式配置映射候选（2026-11-14）

- 用户实测 `focus12` 切换明显变快、效果改善，勿扰可识别；个人/工作/游戏均落为其他。用户反馈是行为证据，不是日志级注册或返回对象证明。
- 新版仅补 `SIFocusSnapshotFromState` 对同一事件 `activeModeConfiguration.mode` 的解析：模式 ID 不匹配时精确读取系统符号；缺失配置回退原 ID 解析，配置存在但未知符号不回退旧勿扰。关闭优先级保持不变。不猜未经验证的 `semanticType` 枚举，不恢复旧 UI 缓存。
- 新增 30 个符号/关闭用例和 6 个缺失字段/错误类型/ABI/回退用例；补充三配置模式的实际 monitor 回调交付与“查询次数不增加”断言。Focus sanitizer 连续 5 轮通过；原旧回调/注销/初值竞争、VPN多宿主/六视图隐藏、格式/几何/速率测试通过。
- 订阅/队列/事件排序/销毁实现与 `focus12` 逐段相同；`SIController.m`、`SIItemViews.m`、`Tweak.xm`、`SIConfiguration.m` 与 Makefile 全文件未改。哈希及包审计保存在 `focus13-package-audit.json`。
- RootHide `iphoneos-arm64e` 构建通过，主包与设置组件版本为 `0.1.0+focus13`，Filter 仍仅 SpringBoard，诊断输出未编入，包及本轮修改源码敏感信息检查无命中。
- 包 50,234 字节，SHA-256 `0919d76bd962b238572ac8439a365eba7d2c679dda541d3c523bf3735a02a72a`；原 `focus12` 和无 Focus `centered2` 安装包哈希不变，34 个无 Focus 归档源码/构建/资源输入逐项未变。
- **本轮未安装、重载或修改设备配置；三个模式的实际状态对象/图标、跨页面行为和资源实测仍未验证，候选不等于实机修复已通过。** 未知或自定义符号保持其他；自定义模式若采用已知系统图标，会按图标显示，不宣称严格语义分类。

### focus13 用户授权安装回读

- 随后用户授权安装；同一 `iPhone15,3 / iOS 16.3 / 20D47 / RootHide` 从 `focus12` 更新至 `focus13`。上传包 SHA-256 与候选一致，Mac/设备双端备份已保存，回读 `install ok installed / 0.1.0+focus13 / iphoneos-arm64e`，SpringBoard 重载后持续 `running`。
- 15 个包内文件回读，14 个逐字节一致；主 dylib 40 字节差异，执行代码与字符串段均与候选包逐字节一致；Filter 仅 SpringBoard、设置组件版本正确。
- 本次状态栏、RootHide、总静音、AiPowerButton、Waqt 共 5 份配置字节/语义和格式均未变。RootHide XML 与全部 38 个 appconfig 项保留。真实系统 CrashReporter 目录在安装窗口内未出现新增 SpringBoard 报告。
- **只确认安装/配置保留/运行恢复；三个模式的真实图标映射、关闭残留、即时切换、跨 App 与资源实测仍需验证，不将安装完成写为实机效果通过。**

## Focus14 游戏名称兼容候选（2026-11-14）

- 用户确认 `focus13` 整体可用，个人/工作已识别，游戏未识别；并明确系统模式名称为“游戏”。此前代码未读取模式对象的 `name`，要求截图不是必要前提。
- 只新增 4 行解析逻辑：在同一 `activeModeConfiguration.mode` 中、已知系统 ID 未命中时，精确读取/匹配名称“游戏”返回游戏图标。关闭仍先于解析；不做子串匹配、不改其他模式、不新增查询、轮询、日志、权限或 UI 快照读取。getter 使用既有 ABI 防护。
- 8 个新增边界用例与实时回调交付/无新增查询断言通过；原 36 个配置用例、状态生命周期/旧回调、VPN多宿主及六视图隐藏测试均通过 ASan/UBSan。本地构造对象不冒充实际设备字段采集。
- RootHide `iphoneos-arm64e` 构建、设置组件版本、SpringBoard-only Filter、包和源码敏感信息检查通过。包 SHA-256 `e5e944a89a88d5fb02f8aad56beb4a786f068386edc9ff504f10337b86d09405`，50,324 字节；审计见 `focus14-package-audit.json`。
- 监听/队列/回调排序实现及全部控制器/布局配置源码与 `focus13` 未变。原 `focus12`、`focus13`、无 Focus `centered2` 包及 34 个无 Focus 归档输入哈希未变。**未安装、重载或改设备配置；实际模式 `name` 返回与游戏图标效果仍未实机验证。**

### focus14 后续安装回读

- 用户追问未安装原因后补装：同一 RootHide/iOS 16.3 设备从 `focus13` 更新至 `0.1.0+focus14`，先完成 Mac/设备双端备份并校验上传哈希。安装状态 `install ok installed / iphoneos-arm64e`，SpringBoard 重载后 `running`。
- 状态栏、RootHide、总静音、AiPowerButton、Waqt 共 5 份配置字节/语义/格式均未变，RootHide 38 项隔离映射保留。15 个 payload 文件回读，14 个完全一致；dylib 40 字节加载后差异，执行代码及字符串段完全一致。检查窗口未发现新增 SpringBoard 崩溃报告。
- **游戏名称的实际字段值及最终图标效果未采集，不把安装与进程恢复写成游戏识别验收通过。**

## Config1 配置完整性及边界完善（2026-11-14）

- 用户随后确认 `focus14` 整体正常；发布审查发现配置导入错误类型崩溃、静音字段导出缺失、无效差分被当有效零流量及预览开关/样式不一致，均有本地复现。用户授权完善配置并整体检查，本轮不安装或正式发布。
- 新 `SIConfigCodec` 共用 50 键白名单和校验：设置页 setter/导出/导入共用类型与范围规则；导出取原资源默认值，展开横屏继承，保留所有已知设置和旧数字字符串规范化。schema=1 不变，旧部分导入不补默认值、只覆盖包含键；坏值/空设置拒绝，非目标键不导出。
- 普通文件读取在反序列化前最多 64 KiB（额外 1 字节用于判断超限），异常类型、bool冒充数值、版本/身份/根结构/范围/整数/颜色/文字长度均检查。取消/校验失败不持久化；确认后经原 store 合并保存，保留 XML/binary、非目标键、备份/属主/权限及回读后通知。增加分享弹层源视图锚点，不改全局配置。
- 配置测试对源码资源和实际包内资源均通过，XML/binary 全键数组/字典拒绝（200 种组合）、50 键往返、旧部分导入、静音字段、横屏继承/显式值、错误版本/根身份、NaN/Inf、数字字符串、64 KiB边界、取消/失败无写入和成功合并/备份/通知；使用真实codec/存储，ASan/UBSan。
- 预览尊重showMute/showFocus及指定Focus样式，自动模式用明确示例；24种实际选择表达式组合通过。更正专注文字通知名与运行消费者一致。
- 速率集合变化、单方向计数回退或零接口标整轮无效，但存当前快照作为新基线；重排不误判，真实idle仍有效。测试覆盖恢复下一轮、隐藏/未知显示组合；原错误断言已更新。timer/采样间隔/显示几何不变。
- Focus模块、控制器、视图、Tweak、颜色/布局与原存储实现全文件字节与本轮前相同；旧focus14/focus13/无Focus centered2包及34个归档输入未变。构建为RootHide `0.1.0+config1 / iphoneos-arm64e`，只注入SpringBoard，诊断日志不编入；包/源码敏感检查通过，审计见config1-package-audit.json。
- **本地算法、文件codec、构建通过不代表真实文件选择器/分享/取消/确认/布局恢复UI已通过。本轮未安装、重载、提交、推送或发正式release。** CPU/内存/耗电无插件专项基线，不用此前SpringBoard约134MiB当成本插件占用。
- 修复后分组静态复核及跨组调用/构建契约检查未发现新的可确认P0/P1/P2；之前导入类型、静音键缺失、异常差分有效性及预览不一致均已改源码并本地复验。结论仅覆盖本轮改动，不代表全部设备和UI已验收。

### config1 后续安装回读

- 用户随后授权安装。同一RootHide/iOS16.3设备从focus14安装config1，先保存Mac/设备双端备份并核对上传哈希。dpkg提示降级仅因Debian版本字符串排序；实际安装的是本次config1候选，不是旧代码。回读install ok installed / 0.1.0+config1 / iphoneos-arm64e，SpringBoard重载后running。
- 15个payload文件回读，14个完全一致；主dylib加载后40字节差异，执行代码与字符串段逐字节相同。状态栏/RootHide/静音/AiPowerButton/Waqt共5份配置字节和语义均未变，真实系统CrashReporter目录检查窗口没有新增SpringBoard报告。
- **安装确认不等于文件选择器或真实配置恢复验收；待用户确认导出保存、取消导入无变化、确认导入恢复静音等布局及基本显示无退步。** 不修改用户设置做验收，保留原包和回滚源码。

## 0.1.1 本地正式包（2026-11-14）

- 用户随后反馈：“好的，现在整体都没问题。” 记录为已安装config1的用户验收，不推断全部App、横屏、iPad或资源专项均通过。
- 生成0.1.1本地正式包，只更新主包/Preferences版本；全部逻辑源码未变，两个二进制的执行代码段与config1逐字节一致。配置/预览/速率及Focus/VPN回归复跑通过；对正式包内设置资源的50键配置测试通过。
- 包51,230字节，SHA-256 `5e22c1c7696ac652bae3dee9e8a0ec50042953209ccae551c21a4f8b9b56a972`；RootHide arm64e、SpringBoard-only、递归包敏感信息检查通过，审计为release-0.1.1-audit.json。
- 本轮没有重装/重载或改手机配置，没有commit/push/GitHub发布；原候选与无Focus回滚包保留。CPU/内存/耗电无插件独立基线。

### 正式版双设备交付

- 用户随后授权提交及安装正式版。两台均确认 RootHide：原手机 `iPhone15,3 / iOS 16.3 / 20D47`，新增手机 `iPhone13,1 / iOS 16.3.1 / 20D67`。不把地址/密码、完整设备配置或备份写入仓库。
- 两台分别完成 Mac/设备双端安装前备份，上传正式包哈希一致。分别从config1和0.1.0安装至0.1.1；回读install ok installed、iphoneos-arm64e、SpringBoard running。真实系统CrashReporter目录在检查窗口未出现新增SpringBoard报告。
- 每台15个payload文件回读：原手机14个完全一致，新手机13个完全一致。加载后二进制只有非执行字段/签名相关字节差异；两台主tweak及Preferences的执行代码和字符串段都与正式包一致，Filter仍仅SpringBoard。
- 原手机状态栏/RootHide/静音/AiPowerButton/Waqt共5份配置字节/语义未变。新手机RootHide/静音/AiPowerButton/Waqt共4份未变；其状态指示自身配置在安装窗口出现35个键变化，当前值已保留，安装前备份可回溯。安装脚本及包无自动配置写入/迁移，不归因于用户或其他进程，也不擅自覆盖这些变化。
- 新手机原布局不由安装脚本复制，未向高敏App注入或改隔离。安装回读不等于新增设备全部UI功能已验收。发布包/无Focus回滚包及源码保留；本次仅本地提交，不自动push或GitHub发布。

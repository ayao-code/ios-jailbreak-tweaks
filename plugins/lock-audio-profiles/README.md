# LockAudioProfiles

独立的锁屏/解锁音量配置插件，不修改也不依赖 `LockLowPower`。

## 能力

- 分别设置锁屏、解锁时的 `Ringtone`（铃声与提醒）音量。
- 分别设置锁屏、解锁时的 `Audio/Video`（媒体）音量。
- 媒体、铃声各有独立的“随锁屏状态切换”开关；关闭某个通道后，锁屏/解锁不再修改该通道。
- 提供与锁屏状态无关的整体媒体、铃声音量滑块。滑块直接读取和修改系统当前值，不保存容易过期的副本；滑动时显示系统对应的音量 HUD。
- 分别设置锁屏、解锁时的响铃模式来电/通知震动和静音模式来电/通知震动。
- 铃声、媒体及两种系统震动固定受配置档管理，设置页不再展示冗余的“控制项目”开关。
- 物理静音拨片优先：插件不会为了有声配置解除用户原本的静音状态。
- 铃声音量配置为 0 时使用系统铃声静音，因为 iOS 16.3 会把 `Ringtone` 音量 0 钳制到约 6.2%。插件仅撤销自己在当前 SpringBoard 生命周期内开启的静音；用户原本的物理静音不会被解除。
- 在插件自动切换音量的 0.15 秒窗口内直接拦截媒体和铃声音量 HUD；硬件音量键按下会立即取消拦截，因此手动调音量仍正常显示灵动岛或侧边 HUD。
- 提供 CCSupport 控制中心“总静音”模块，其优先级最高。开启瞬间媒体音量归零，同时关闭铃声和两种系统来电/通知震动；之后仍允许音量键或整体媒体滑块重新打开媒体声音，但铃声和震动保持关闭。只有再次点击控制中心模块才会关闭总静音，并恢复开启前快照后应用当前策略。
- 控制中心使用“左侧震动折线 + 圆角轮廓扬声器 + 右侧两道声波”的统一主体图标；开启总静音时只叠加关闭斜杠，震动折线、喇叭及声波的位置、尺寸保持一致。SVG 和 1x/2x/3x PNG 由同一套路径离线生成，运行时只读取图片。设置入口继续使用“锁 + 扬声器”图标。

## 事件与耗电

- 仅注入 SpringBoard。
- 锁屏状态只 Hook `SBLockScreenManager._reallySetUILocked:`，并以 `isUILocked` 最终值为准。
- 设置和控制中心通过 Darwin 通知触发。
- 设置页的整体音量滑块只在用户拖动时发送状态变更事件；没有持续同步任务。再次打开设置页时重新读取系统当前值。
- 总静音期间不持续压制媒体音量，只在开启瞬间归零，之后允许系统音量键正常调节。铃声使用系统静音状态，并只在明确写入时钳制音量；震动偏好通过系统原有变更通知保持关闭，避免轮询和音量通知循环。
- 配置档的铃声音量为 0 时只使用系统铃声静音，不再写入 iOS 无法保存的 `Ringtone=0`；媒体配置会在状态切换时明确写入。控制中心音量模块挂载或收到系统音量变化事件时，若读取到媒体音量精确为 0，则仅隐藏该模块自身的零值最小填充，不影响亮度滑块、音量键、拖动手势或非零媒体音量。
- 没有定时器、轮询、后台线程、网络请求或常驻 daemon。

## 震动边界

iOS 不存在统一的“媒体震动音量”。`ring-vibrate` 与 `silent-vibrate` 控制的是系统来电、CallKit 来电及普通通知通常遵循的系统震动策略。App 自己创建的 Core Haptics、游戏触觉、键盘触感或自定义音频会话不属于同一通道，本插件不会通过全 App 注入去强行拦截它们。

## 冲突

`LockEventRinger` 和 `DND Haptics` 会写入相同的音量或震动状态。包声明与这两个插件冲突，避免多套状态机互相覆盖。`CCSupport` 是控制中心模块依赖。

## 构建

```sh
make clean package
```

构建产物必须放在本目录 `packages/`。

## 控制中心图标设计参考

- [Apple HIG — Icons](https://developer.apple.com/design/human-interface-guidelines/icons)：简化可辨识的隐喻，保持笔画、尺寸一致，针对非对称图标进行光学居中。
- [Material Symbols](https://developers.google.com/fonts/docs/material_symbols)：小尺寸图标需要适合其光学尺寸的笔画粗细，而不是只扩大画布。
- [Material vibration](https://github.com/google/material-design-icons/blob/master/src/notification/vibration/materialicons/24px.svg) 与 [Lucide vibrate](https://github.com/lucide-icons/lucide/blob/main/icons/vibrate.svg)：用直线或折线表达震动；[Lucide volume-2](https://github.com/lucide-icons/lucide/blob/main/icons/volume-2.svg) 用圆角喇叭和右侧圆弧表达声音。当前图标为独立绘制，不直接复制这些参考资源。

```sh
swift tools/generate-icons.swift
```

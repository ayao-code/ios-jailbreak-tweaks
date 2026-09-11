# iOS 越狱插件合集

这里收集 ayao 开发和维护的 iOS Dopamine rootless 越狱插件，以及少量 App 相关项目资料。

本仓库采用 monorepo 结构：每个插件放在 `plugins/` 下的独立目录中。仓库当前同时存在三类项目：

- 完整源码项目：目录内有正式源码，可以直接维护和构建。
- 恢复 / 重建项目：原始源码一度缺失，后续从设备、安装包或构建产物中恢复出可维护源码。
- 历史归档项目：当前仍以安装包或构建痕迹为主，后续需要逐步补齐正式源码。

从现在开始，本仓库的目标状态是：每个插件或 App 目录都必须保留对应源码，不能只保留 `.deb`、`.theos/` 或其他编译产物。

## 插件列表

### AiPowerButton

路径：[`plugins/ai-power-button`](plugins/ai-power-button)

适用于 iOS 16 Dopamine rootless 越狱环境。安装后可以在系统设置中通过 `AiPowerButton` 配置长按关机键启动豆包或 DeepSeek 语音助手。

- 豆包模式：长按关机键启动豆包语音输入，发送由用户在豆包内手动完成。
- DeepSeek 模式：长按关机键开始语音输入，松开关机键后自动发送。
- 保留系统原始操作：音量键加关机键仍会触发 iOS 原生关机/SOS 界面。

### HideDoubaoPiP

路径：[`plugins/hide-doubao-pip`](plugins/hide-doubao-pip)

适用于 iOS 16 Dopamine rootless 越狱环境。安装后仅隐藏豆包输入法创建的 PiP 悬浮窗，通过透明化窗口并禁用触摸来避免干预正常视频 PiP。

- 只注入 SpringBoard，只处理系统 PiP 窗口。
- 优先通过豆包输入法 bundle/process 识别目标 PiP。
- bundle 信息缺失时使用保守的 PiP 视图结构兜底识别。
- 不包含右侧停靠、缩放或常驻 watchdog。

### AirPodsAutoNoise

路径：[`plugins/airpods-auto-noise`](plugins/airpods-auto-noise)

当前目录已补入可维护源码，用于后续继续调整 AirPods 自动降噪行为。该插件目录同时保留历史 `.deb`，方便回滚和对照，但历史安装包不再视为源码替代品。

### PhotosRecentsSort

路径：[`plugins/photos-recents-sort`](plugins/photos-recents-sort)

该目录当前保留恢复后的排序脚本源码和对应包，用于继续维护相册最近项目排序逻辑。

## 仓库结构

```text
plugins/
├── ai-power-button/
│   ├── README.md
│   ├── Makefile
│   ├── control
│   ├── Tweak.xm
│   ├── Preferences/
│   ├── ayao.aipowerbutton_1.0.0_iphoneos-arm64.deb
│   └── ...
├── airpods-auto-noise/
│   ├── README.md
│   ├── Makefile
│   ├── control
│   ├── Tweak.xm
│   ├── Preferences/
│   ├── packages/
│   └── 历史 deb...
├── hide-doubao-pip/
│   ├── README.md
│   ├── Makefile
│   ├── control
│   ├── Tweak.xm
│   ├── HideDoubaoPiP.plist
│   ├── changelog
│   └── ayao.hidedoubaopip_1.0.0_iphoneos-arm64.deb
├── photos-recents-sort/
│   ├── README.md
│   ├── control
│   ├── reconstructed/
│   └── ayao.photosrecentssort_0.1.0_iphoneos-arm64.deb
└── xianyu-ad-cleaner/
    ├── packages/
    ├── .theos/
    └── 待补正式源码
```

## 项目规范

项目级规则入口：

- `AGENTS.md`
- `CLAUDE.md`
- 统一正文：`PROJECT_SOURCE_POLICY.md`

后续所有插件 / App 相关维护，都以 `PROJECT_SOURCE_POLICY.md` 为准。

## 新增插件规范

以后新增插件时，统一按下面方式写入仓库：

1. 在 `plugins/` 下新建插件目录，目录名使用英文小写和连字符，例如 `plugins/example-tweak/`。
2. 每个插件目录必须是一个可以独立构建的 Theos 项目。
3. 每个插件目录至少包含：
   - `README.md`：说明插件功能、兼容环境、安装方法和版本说明。
   - `Makefile`：Theos 构建配置。
   - `control`：Debian 包信息，描述尽量使用中文写清楚。
   - `Tweak.xm` 或对应源码文件。
   - 当前正式版 `.deb`：放在该插件目录下，文件名保持包名、版本和架构清晰可识别。
4. 如果插件有设置面板，放在插件自己的 `Preferences/` 目录内。
5. 不同插件之间不要共用源码文件，避免发布和调试时互相影响。
6. 不允许只提交 `.deb`、`.theos/`、设备导出结果，而不保留正式源码。
7. 如果源码来自恢复、重建、反编译整理或设备导出，也必须放回该插件目录，并写清楚来源或恢复说明。
8. `.theos/` 是构建输出，不算源码；是否保留只取决于排障或恢复需要。
9. `packages/` 和目录根部下的 `.deb` 是否保留，按仓库实际发布策略处理，但它们不能代替源码。

## 构建方式

进入具体插件目录后构建：

```sh
cd plugins/ai-power-button
THEOS=/path/to/theos FINALPACKAGE=1 make clean package
```

构建完成后的 `.deb` 文件通常会在该插件目录的 `packages/` 下生成。是否同时在项目目录根部保留正式发布包，按当前仓库策略决定；但不论是否保留发布包，源码都必须和项目一起存放。

## 发版建议

多个插件共用一个仓库时，建议 tag 使用插件名前缀：

```text
ai-power-button-v1.0.0
example-tweak-v0.1.0
```

Release 标题和说明中写清楚对应插件名称、版本、主要功能和兼容环境。

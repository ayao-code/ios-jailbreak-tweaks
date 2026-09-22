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

当前保留的最新版安装包为 `1.0.1`。

- 豆包模式：长按关机键启动豆包语音输入，发送由用户在豆包内手动完成。
- DeepSeek 模式：长按关机键开始语音输入，松开关机键后自动发送。
- 保留系统原始操作：音量键加关机键仍会触发 iOS 原生关机/SOS 界面。

### HideDoubaoPiP

路径：[`plugins/hide-doubao-pip`](plugins/hide-doubao-pip)

适用于 iOS 16 Dopamine rootless 越狱环境。安装后隐藏豆包输入法创建的 PiP 悬浮窗，通过透明化渲染层保留 PiP 会话；冷启动必须短暂前台激活豆包时，使用双向 App-to-App 事务遮罩隐藏切换并返回原应用。

当前稳定版为 `1.0.30`；除隐藏豆包 PiP 和启用原生失效恢复外，还在冷启动语音时使用当前界面截图遮罩，等待前向语音会话与反向返回事务完整完成后再撤罩，使文字回传和松键停止继续走豆包原生链路。带 `~test` 或 `~debug` 后缀的安装包仅用于故障定位，不作为正式稳定版。

- SpringBoard 模块只处理系统 PiP 窗口；无跳转模块只注入豆包主 App 与键盘扩展。
- 优先通过豆包输入法 bundle/process 识别目标 PiP。
- bundle 信息缺失时使用保守的 PiP 视图结构兜底识别。
- 稳定版不包含右侧停靠、缩放、常驻 watchdog 或持续诊断采样。
- 诊断版包含临时状态采样，只应用于限定时间的故障定位，验证完成后应恢复为事件驱动或移除。

### AirPodsAutoNoise

路径：[`plugins/airpods-auto-noise`](plugins/airpods-auto-noise)

当前版本为 `1.0.2`，目录内保留可维护的插件源码、设置面板源码和对应安装包，用于继续调整 AirPods 自动降噪行为。安装包不作为源码替代品。

### PhotosRecentsSort

路径：[`plugins/photos-recents-sort`](plugins/photos-recents-sort)

该目录当前保留从已安装包分析后恢复的行为级源码骨架和对应安装包，用于继续恢复相册增强功能。`reconstructed/` 不等同于已完整恢复的原始源码，且当前目录还不能作为完整 Theos 项目直接构建。

### XianYuAdCleaner

路径：[`plugins/xianyu-ad-cleaner`](plugins/xianyu-ad-cleaner)

该目录当前只有 `.theos/` 构建痕迹和 `packages/` 下的 `0.1.0` 安装包，尚未补回正式源码，属于待恢复项目；在源码补齐前不能进行可维护的功能修改。

## 仓库结构

```text
plugins/
├── ai-power-button/
│   ├── README.md
│   ├── Makefile
│   ├── control
│   ├── Tweak.xm
│   ├── Preferences/
│   ├── packages/
│   └── ...
├── airpods-auto-noise/
│   ├── README.md
│   ├── Makefile
│   ├── control
│   ├── Tweak.xm
│   ├── Preferences/
│   └── packages/
├── hide-doubao-pip/
│   ├── README.md
│   ├── Makefile
│   ├── control
│   ├── Tweak.xm
│   ├── HideDoubaoPiP.plist
│   ├── DoubaoNoJump.xm
│   ├── DoubaoNoJump.plist
│   ├── changelog
│   └── packages/
├── photos-recents-sort/
│   ├── README.md
│   ├── control
│   ├── reconstructed/
│   └── packages/
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

其中包括以下强制边界：

- 每次只修改实现目标所需的最小范围，不得顺带改变无关功能或系统行为。
- 插件不得破坏或干扰系统稳定性、安全性及其他插件的正常运行。
- 不得引入持续高 CPU、高频轮询、忙等待、无意义后台任务或可感知的额外耗电和发热。
- 监听、定时器、线程及其他资源必须具有明确生命周期，并在不再需要时及时停止或释放。
- 如果存在 `Preferences/`，其源码、配置、资源和展示内容必须与当前最新版插件保持一致。
- 无法完成实机稳定性、CPU、内存和续航验证时，必须明确记录未验证项和潜在风险。

## 新增插件规范

以后新增插件时，统一按下面方式写入仓库：

1. 在 `plugins/` 下新建插件目录，目录名使用英文小写和连字符，例如 `plugins/example-tweak/`。
2. 每个插件目录必须是一个可以独立构建的 Theos 项目。
3. 每个插件目录至少包含：
   - `README.md`：说明插件功能、兼容环境、安装方法和版本说明。
   - `Makefile`：Theos 构建配置。
   - `control`：Debian 包信息，描述尽量使用中文写清楚。
   - `Tweak.xm` 或对应源码文件。
4. 如果插件有设置面板，放在插件自己的 `Preferences/` 目录内，并确保其中的源码、配置、资源和展示内容与当前最新版插件一致。
5. 所有 `.deb` 安装包必须统一放入插件目录下的 `packages/`，不得散落在插件根目录；历史包如需保留，也必须移入 `packages/`。
6. 正式版和调试版安装包必须明确区分；调试版不能替代正式版，也不能作为长期运行版本发布。
7. 不同插件之间不要共用源码文件，避免发布和调试时互相影响。
8. 不允许只提交 `.deb`、`.theos/`、设备导出结果，而不保留正式源码。
9. 如果源码来自恢复、重建、反编译整理或设备导出，也必须放回该插件目录，并写清楚来源或恢复说明。
10. `.theos/` 是构建输出，不算源码；是否保留只取决于排障或恢复需要。
11. 所有实现必须遵守最小变更、系统稳定性和资源约束，优先使用系统事件、通知或回调，不得无必要地持续轮询。

## 构建方式

进入具体插件目录后构建：

```sh
cd plugins/ai-power-button
THEOS=/path/to/theos FINALPACKAGE=1 make clean package
```

构建完成后的 `.deb` 文件通常会在该插件目录的 `packages/` 下生成。所有安装包统一保留在 `packages/`，不得复制到项目根目录；但不论是否保留发布包，源码都必须和项目一起存放。

## 发版建议

多个插件共用一个仓库时，建议 tag 使用插件名前缀：

```text
ai-power-button-v1.0.0
example-tweak-v0.1.0
```

Release 标题和说明中写清楚对应插件名称、版本、主要功能和兼容环境。

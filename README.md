# iOS 越狱插件合集

这里收集 ayao 开发和维护的 iOS Dopamine rootless 越狱插件。

本仓库采用 monorepo 结构：每个插件放在 `plugins/` 下的独立目录中，每个插件都保持完整的 Theos 项目结构，可以单独构建、单独说明、单独发版。

## 插件列表

### AiPowerButton

路径：[`plugins/ai-power-button`](plugins/ai-power-button)

适用于 iOS 16 Dopamine rootless 越狱环境。安装后可以在系统设置中通过 `AiPowerButton` 配置长按关机键启动豆包或 DeepSeek 语音助手。

- 豆包模式：长按关机键启动豆包语音输入，发送由用户在豆包内手动完成。
- DeepSeek 模式：长按关机键开始语音输入，松开关机键后自动发送。
- 保留系统原始操作：音量键加关机键仍会触发 iOS 原生关机/SOS 界面。

## 仓库结构

```text
plugins/
├── ai-power-button/
│   ├── README.md
│   ├── Makefile
│   ├── control
│   ├── Tweak.xm
│   ├── Preferences/
│   └── ...
└── another-plugin/
    ├── README.md
    ├── Makefile
    ├── control
    ├── Tweak.xm
    └── ...
```

## 新增插件规范

以后新增插件时，统一按下面方式写入仓库：

1. 在 `plugins/` 下新建插件目录，目录名使用英文小写和连字符，例如 `plugins/example-tweak/`。
2. 每个插件目录必须是一个可以独立构建的 Theos 项目。
3. 每个插件目录至少包含：
   - `README.md`：说明插件功能、兼容环境、安装方法和版本说明。
   - `Makefile`：Theos 构建配置。
   - `control`：Debian 包信息，描述尽量使用中文写清楚。
   - `Tweak.xm` 或对应源码文件。
4. 如果插件有设置面板，放在插件自己的 `Preferences/` 目录内。
5. 不同插件之间不要共用源码文件，避免发布和调试时互相影响。
6. 构建产物不要提交到仓库，`.deb` 包通过 GitHub Release 发布。

## 构建方式

进入具体插件目录后构建：

```sh
cd plugins/ai-power-button
THEOS=/path/to/theos FINALPACKAGE=1 make clean package
```

构建完成后的 `.deb` 文件会在该插件目录的 `packages/` 下生成。

## 发版建议

多个插件共用一个仓库时，建议 tag 使用插件名前缀：

```text
ai-power-button-v1.0.0
example-tweak-v0.1.0
```

Release 标题和说明中写清楚对应插件名称、版本、主要功能和兼容环境。

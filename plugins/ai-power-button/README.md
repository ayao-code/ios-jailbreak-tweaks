# AiPowerButton

适用于 iOS 16 Dopamine rootless 越狱环境的侧边键快捷插件。安装后可以在系统设置的 `AiPowerButton` 中选择长按关机键启动豆包或 DeepSeek 语音助手。

## 功能

- 长按关机键启动语音 AI 助手。
- 设置中可选择启动应用：豆包或 DeepSeek。
- 默认启动豆包。
- 豆包模式：长按关机键启动豆包语音输入，发送由用户在豆包内手动完成。
- DeepSeek 模式：长按关机键开始语音输入，松开关机键后自动发送。
- 保留系统原始操作：音量键加关机键仍会触发 iOS 原生关机/SOS 界面。
- 1.0.0 正式版已关闭测试日志输出。

## 兼容环境

- iOS 16
- Dopamine rootless 越狱
- arm64 / arm64e 设备
- 需要 `mobilesubstrate` 和 `preferenceloader`

## 安装

下载 `com.ayao.doubaopowerbutton_1.0.0_iphoneos-arm64.deb` 后安装，安装完成后重载 SpringBoard。

> 为了兼容旧版本升级，底层 package id 仍保留为 `com.ayao.doubaopowerbutton`；插件对外名称和设置显示名称为 `AiPowerButton`。

## 使用方法

1. 打开系统设置。
2. 进入 `AiPowerButton`。
3. 开启插件。
4. 在「启动应用」中选择「豆包」或「DeepSeek」。
5. 单独长按关机键触发所选语音助手。
6. 如果需要使用系统关机/SOS，按音量键加关机键即可，插件会自动放行系统原始行为。

## 版本说明

### 1.0.0

- 发布正式版。
- 支持豆包和 DeepSeek 双模式选择。
- 豆包恢复稳定语音唤起逻辑。
- DeepSeek 支持长按录音、松开发送。
- 保留音量键加关机键的系统关机/SOS 操作。
- 移除测试日志输出。

# 无专注模式回滚基线：0.1.0+centered2

## 保留内容

- 原安装包：`../../packages/ayao.statusindicators_0.1.0+centered2_iphoneos-arm64e.deb`。
- SHA-256：`5bf50a1a0a0a84190bb11a1c40058de1820fc2685b0d1c63fe65eef15004949d`。
- 功能：VPN、网速、实心静音、固定锚点、可选动态居中；无专注模式代码和设置页。
- 目标：RootHide / iOS 16 / `iphoneos-arm64e`。不用于普通 rootless。
- `source/` 保留 34 个源码、构建配置和资源文件；`manifest.json` 记录逐文件哈希及二进制代码段比较。

## 源码来源及验证边界

源码从添加 Focus 前的本地会话读回、当前未变化的共用文件和原包设置资源恢复；不是反编译源码。历史归档故意保留当时行为，不在此修补预览、导出或其他缺陷。

2026-11-14 本地 RootHide 构建成功：重建主 tweak 的 `__text`（29,596 字节）及 `__cstring` 与原包逐字节一致。Preferences 的代码段长度及字符串段一致，但代码段不完全一致；不宣称整个包可逐字节重现。实际回滚应使用上面保留的原包，而不是重建包。

原会话曾安装并回读该包；本轮未安装、重载、变更设备配置或重新验收 UI。保留旧包不等于证明所有 App、动画及耗电均已通过。

## 本地构建

在 `source/` 目录执行，`ROOTHIDE_THEOS` 指向已配置 iOS 16.5 SDK 的官方 RootHide Theos：

```sh
make THEOS="$ROOTHIDE_THEOS" THEOS_PACKAGE_SCHEME=roothide ARCHS=arm64e \
  PACKAGE_VERSION=0.1.0+centered2 clean package FINALPACKAGE=1
```

输出只在此历史源码的 `packages/` 下；不要覆盖项目主 `packages/` 中的原回滚包。

回滚不需要删除现有偏好；历史版不消费 Focus 键。不自动执行降级安装，安装与重载需单独确认。

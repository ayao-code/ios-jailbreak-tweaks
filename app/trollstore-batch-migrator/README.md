# TrollStore Batch Migrator

一次性、离线、前台运行的 TrollStore 工具迁移器。它从系统共享媒体目录
`/var/mobile/Media/Downloads/巨魔应用文件夹/manifest.tsv` 读取 31 个 IPA，逐个校验清单中的
SHA-256，再调用目标机已安装的 TrollStore 2 `trollstorehelper` 串行安装，
最后统一刷新 App 注册。1.1.2 首次打开会预备开发者模式，等待用户重启并在
系统弹窗中确认；确认后第二次打开才执行安装。安装包构建时仍会移除不必要的
调试 entitlement。迁移器只在 App 容器根目录下寻找 Bundle ID 精确匹配
`com.opa334.TrollStore` 的 `TrollStore.app/trollstorehelper`，不读取 LaunchServices
数据库。

## 安全边界

- 不包含或运行 Dopamine，不创建 `/var/jb`，不开启 SSH。
- 不联网、不启动 daemon、不注册后台任务、不轮询。
- 不读取或修改淘宝数据，不向淘宝注入代码。
- 只安装工具本体；不自动启用虚拟定位，也不配置 TrollFools 的注入目标。
- TrollStore 和高权限工具仍可能被 App 风控识别，不能承诺任何第三方 App
  绝对无法检测设备改动。

## 安装清单

清单必须恰好包含 31 项；迁移器拒绝非 IPA 文件、路径穿越、非法 SHA-256
以及 Bundle ID 为 `com.opa334.Dopamine` 的项目。清单和 IPA 已由 Mac 端迁移
流程生成并写入手机文件共享目录。

## 构建

```sh
THEOS=$HOME/theos make clean
scripts/sanitize_ipas.sh /tmp/trollstore-migrate build/sanitized
THEOS=$HOME/theos make ipa
```

产物位于 `build/TrollStoreBatchMigrator-1.1.2.ipa`。迁移器本身必须通过
TrollStore 安装；Apple 的普通 USB 安装流程会拒绝 TrollStore 伪签名 IPA。

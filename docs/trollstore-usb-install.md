# USB 安装 TrollStore 逻辑记录

总入口见 [完整越狱与恢复流程](jailbreak-and-restore-guide.md)。本篇只记录
安装巨魔的 USB Helper 阶段；后续应确认巨魔及持久化助手可用，再用巨魔安装
所选越狱 App、执行 Jailbreak，最后进入插件和配置恢复。

状态：流程记录，非自动化脚本。
日期：2026-11-17。
目标设备：USB 连接的 iPhone13,1，iOS 16.3.1 / 20D67。

## 结论

本次采用 TrollRestore 通过 USB 把系统 `Tips.app` 临时替换为 TrollStore Helper，再由手机端打开 Tips 完成 TrollStore 安装。这个流程只证明“Helper 已被写入并触发重启”，不等同于已经完成 TrollStore App 内安装和持久化助手配置。

## 安装逻辑总览

安装分两层处理：第一层是把 TrollStore Helper 安装到 USB 连接的手机；第二层是在 TrollStore 已经可用后，才用 TrollStore 安装或迁移普通 IPA。两层不能混为一个完成状态。

### 第一层：USB 安装 TrollStore Helper

1. 先只读确认目标设备：通过 USB / lockdown 读取设备型号、系统版本、BuildVersion 和 UDID，不在身份不明或未信任配对时写入。
2. 锁定写入目标：每次写入命令都显式传入 UDID；写入前后必须确认仍是同一台设备，避免多设备或重新插拔导致误写。
3. 校验系统版本：只有目标系统落在 TrollRestore 支持范围内时才继续；不支持则停止，不做试探性写入。
4. 先查 TrollStore 现状：如果设备已经有 TrollStore / Helper / Persistence Helper，优先验证现状，不重复覆盖安装。
5. 选择安装器：优先使用官方预编译 TrollRestore；只有在依赖、版本和命令都确认可用时才考虑源码方式。
6. 选择 Helper 承载 App：默认选择可移除系统 App `Tips.app`；不使用阿里、蚂蚁、京东、银行、支付、证券等高敏 App，也不做注入、Hook、调试附加或沙盒写入。
7. 处理阻塞条件：如果安装器因“查找我的 iPhone”或类似系统保护失败，停止并让用户在手机端处理，不盲目重试或绕过。
8. 执行写入：用 TrollRestore 指向固定 UDID，把 `Tips.app` 临时替换成 TrollStore Helper，并保存终端输出作为证据。
9. 写入后只做读回：等待设备重启后重新通过 USB 上线，回读 ProductType、ProductVersion 和 BuildVersion，确认同一设备恢复在线。
10. 明确边界：TrollRestore 输出成功只代表 Helper 已写入；完整安装仍需要用户在手机上打开 `Tips`，执行 Install TrollStore，并在 TrollStore 内配置 Persistence Helper。

### 第二层：TrollStore 安装或迁移 IPA

1. 仅在 TrollStore 已可打开、helper 可调用、目标设备空间足够时执行 IPA 安装；Helper 写入成功但 TrollStore 未完成安装时不进入本层。
2. 优先基于源 App 的 Bundle ID、版本、`Info.plist` 和 TrollStore 标记做清单，不把“本地有 IPA 文件”直接等同于应该安装。
3. 迁移已有 TrollStore App 时，将源 App 打包为标准 `Payload/<App>.app` 结构 IPA；不迁移普通 App Store App 的沙盒、账号、Keychain。
4. RootHide 设备上传 IPA 时，文件放到目标机 `/rootfs/var/tmp/<批次>/`，调用 TrollStore helper 时传入对应的 `/var/tmp/<批次>/<文件>.ipa` 路径，避免 RootHide 命名空间导致 helper 看不到文件。
5. 安装命令默认不加 `force`，也不先卸载旧 App；避免误删用户数据容器。只有用户明确授权完整覆盖时，才进入覆盖/卸载分支。
6. 安装后必须回读验证：至少确认 Bundle ID、显示名、版本、安装目录、必要扩展和 TrollStore 注册状态；不能只看命令退出码。
7. 清理只限临时安装包和批次目录，不删除已安装 App、数据容器、源包清单或证据日志。

### 完成判定

只有同时满足以下条件，才可以汇报“安装完成”：

- 手机端可以打开 TrollStore。
- TrollStore 设置页状态正常。
- Persistence Helper 已配置到用户确认的承载 App。
- 设备重启后 TrollStore 仍可打开。
- 后续 IPA 安装任务已完成逐项回读验证，且失败项、跳过项和未验证项都单独列出。

## 决策链

1. 先做只读识别，不直接写设备：用 `system_profiler SPUSBDataType`、`idevice_id -l`、`pymobiledevice3 lockdown info` 确认确实有 USB iPhone、配对可信、系统版本和设备型号。
2. 确认系统版本可用：TrollRestore 官方说明支持 iOS/iPadOS 15.2 到 16.7 RC 以及 17.0；本次设备是 iOS 16.3.1，落在支持范围内。
3. 先查现状再安装：用 `pymobiledevice3 apps list --type User` 搜索 TrollStore / Dopamine / RootHide / Persistence 等关键字；未看到 TrollStore 用户 App，因此按新装 Helper 处理。
4. 选择 TrollRestore 官方预编译包，而不是源码运行：此前源码方式和本机 `pymobiledevice3` 依赖发生过 `ImportError: cannot import name 'Command'` 冲突；官方 macOS arm64 预编译二进制已存在且可直接运行。
5. 选择 `Tips.app` 作为 Helper 承载 App：TrollRestore 提示“不知道选哪个就选 Tips”；Tips 是可移除系统 App，不涉及阿里/蚂蚁、京东、银行、支付、证券等高敏 App，也不需要 RootHide 注入或 Hook。
6. 执行写入时固定 UDID，避免多设备误操作：命令通过 `--udid <目标设备UDID>` 指向当前 USB 设备，并向交互输入 `Tips`。
7. 写入完成后只做低风险读回：等待设备重启后重新上线，再读 `ProductType`、`ProductVersion`、`BuildVersion` 确认同一台设备回到 USB 可访问状态。

## 执行命令模板

```sh
UDID=<目标设备UDID>
TROLLRESTORE=/path/to/TrollRestore

printf 'Tips\n' | "$TROLLRESTORE" --udid "$UDID" --no-color
```

工具路径由调用者私有提供，公开文档不保留本机下载目录：

```text
$TROLLRESTORE
```

本次安装器输出的关键结果：

```text
Replacing Tips.app with TrollStore Helper.
Rebooting device
Make sure to install a proper persistence helper into the app you chose after installing TrollStore!
```

重启后 USB 读回结果：

```text
device_online_after=19s
ProductType=iPhone13,1 ProductVersion=16.3.1 BuildVersion=20D67
```

## 后续人工步骤

1. 在手机上打开 `Tips`，此时它应表现为 TrollStore Helper。
2. 在 Helper 内执行 Install TrollStore。
3. 安装完成后打开 TrollStore。
4. 在 TrollStore 内把 Persistence Helper 安装到同一个 `Tips` 或用户明确选择的其他可移除系统 App。
5. 如果安装前关闭过“查找我的 iPhone”，安装后要重新打开。

## 验证边界

已验证：

- USB 识别到目标 iPhone。
- 目标系统版本满足 TrollRestore 支持范围。
- TrollRestore 已报告替换 `Tips.app` 为 TrollStore Helper。
- 设备已重启并重新通过 USB 上线。

未验证：

- 手机端是否已经打开 Helper。
- TrollStore App 是否已由 Helper 安装完成。
- Persistence Helper 是否已经在 TrollStore 内配置完成。
- TrollStore 后续安装 IPA 的能力是否正常。

因此，后续汇报不能把“运行 TrollRestore 成功”写成“巨魔完整安装完成”。完整完成标准至少应包含：手机端能打开 TrollStore、TrollStore 设置页显示正常、Persistence Helper 已配置、重启后仍可打开 TrollStore。

## 安全边界

- 不把高敏 App 作为 Helper 承载对象。
- 不对阿里/蚂蚁、京东、银行、支付、证券等高敏 App 开启注入、Hook、调试附加或沙盒写入。
- 不把 TrollStore 存在等同于越狱激活，也不把 Helper 写入等同于 RootHide / Dopamine 已安装。
- 文档中不保留 IMEI、序列号等设备敏感标识；需要复现时现场重新读取 UDID 并确认目标设备。

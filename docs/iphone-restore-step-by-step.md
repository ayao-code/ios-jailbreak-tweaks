# iPhone 恢复与配置对齐：详细步骤教程

> **当前恢复规则（2026-11-20）：源机只读、目标机覆盖，不要求双端备份，不强制保存目标旧配置。**
> 只从源机读取和导出，不向源机上传助手、安装、改配置、发通知或重载。恢复清单内的兼容纯设置文件可整文件覆盖；
> 混有账号、授权、容器或运行状态的文件只覆盖设置部分，清单外及高敏隔离策略不照搬。未保存目标旧状态就不承诺回滚。
> 下文历史数字、备份记录及旧工具能力保留，不代表新一轮仍须沿用旧备份流程。

> 总入口见 [完整越狱与恢复流程](jailbreak-and-restore-guide.md)。新目标应先按
> 总流程确认源机只读与目标范围、安装／确认巨魔、通过巨魔安装越狱 App 并执行 Jailbreak；
> 本篇重点是环境就绪后的恢复和本次执行明细，不代替完整越狱安装步骤。

> 整理日期：2026-11-19。参考机为 iPhone 14 Pro Max / iOS 16.3 / 20D47，
> 目标机为 iPhone 12 mini / iOS 16.3.1 / 20D67，两台使用 RootHide。
> 本文根据已保存的执行、备份和回读文件整理，不是本轮再次操作手机的结果。
> 下一次恢复必须重新盘点，不能把这里的历史数字当成当前手机状态。

本文同时说明：怎样恢复、每一步怎样验证、为什么某些内容没有照搬，以及
失败后怎样回滚。它不是一键克隆脚本，也不包含真实地址、密码或设备标识。

## 目录

1. [实际结果与时间线](#1-实际结果与时间线)
2. [明确范围、准备工具](#2-明确范围准备工具)
3. [连接两台手机并确认身份](#3-连接两台手机并确认身份)
4. [RootHide 命名空间核对](#4-roothide-命名空间核对)
5. [源机只读、差异清单和目标覆盖](#5-源机只读差异清单和目标覆盖)
6. [TrollStore 与普通 App 的前置恢复](#6-trollstore-与普通-app-的前置恢复)
7. [恢复插件源](#7-恢复插件源)
8. [恢复插件与依赖](#8-恢复插件与依赖)
9. [覆盖目标插件设置](#9-覆盖目标插件设置)
10. [恢复控制中心](#10-恢复控制中心)
11. [恢复桌面、文件夹和 Dock](#11-恢复桌面文件夹和-dock)
12. [重载与运行核验](#12-重载与运行核验)
13. [后续补齐阿里／蚂蚁黑名单](#13-后续补齐阿里蚂蚁黑名单)
14. [断线续跑与回滚](#14-断线续跑与回滚)
15. [清理、交付和剩余项](#15-清理交付和剩余项)
16. [本次包与设置明细](#16-本次包与设置明细)

## 1. 实际结果与时间线

### 1.1 恢复与外观补齐阶段

以下计数只属于此次 `resume-config` 恢复范围，不是仓库所有历史迁移的总计。

| 项目 | 已保存证据确认的结果 | 没有证明什么 |
| --- | --- | --- |
| 插件／依赖 | 新增 31 个包、升级 1 个包 | 不代表原机所有插件齐全，也不代表每个功能实测 |
| 设置 | 16 组、147 个目标设置键，原生 API／磁盘回读差异为 0 | 不是两台全部偏好字典逐字节相等 |
| 桌面 | 2 页、104 个唯一 App 引用、保留目标 2 个小组件 | 不保证逐像素相同；没有可靠文件夹展开验收 |
| Dock | 电话、信息、微信、设置 | 不能据此证明所有 App 的图标或功能相同 |
| 控制中心 | 19 个排列模块、9 个禁用项、1 个固定启用项 | 没有逐个点击测试网络、VPN、扫码等功能 |
| 软件源 | 最终参考机 35 条、目标 36 条，source_only=0、target_only=1 | 不是 36 条全部联网刷新成功 |
| 运行 | 12 个相关组件出现在 SpringBoard 映射；检查窗口内没有新增崩溃 | 不证明长期续航、CPU 或所有 App 的兼容性 |
| 包差异 | 源机独有 20、目标独有 2、匹配 395 | 包含真实插件及机型能力虚拟包，不是 20 个都应该补装 |

### 1.2 后续黑名单阶段：修正旧结论

外观恢复结束时，目标 `RootHideConfig.plist` 不存在，当时不能宣称黑名单完整。
**随后用户明确授权补阿里／蚂蚁黑名单，已经完成另一轮操作：**

- 11 个目标已安装主 App、59 个扩展，共 70 个安装侧 Bundle ID。
- 另外预列原机的天猫、盒马、阿里妈妈 3 个主 App，共 73 个明确条目。
- 73/73 的越狱服务查询返回黑名单 true；磁盘重复回读通过。
- 文件为 XML，`appconfig` 经 Foundation 读回为可变字典。
- 未复制原机的清理规则、全局模式、其他品牌状态或注入策略；原机未修改。
- 没有启动业务 App，没有验证 Manager 界面开关往返，也没有证明全进程零注入。

所以，旧报告中的“目标缺少 RootHide 黑名单配置”是**当时事实**，不是后续
黑名单阶段完成后的状态。此后若手机又变化，应以新现场为准。

## 2. 明确范围、准备工具

### 2.1 每种恢复单独授权

开始前分别确认：插件、插件设置、软件源、桌面／控制中心、TrollStore App、
普通 App Store App、RootHide 黑名单。它们不是一个不可分割的“全量恢复”。

本次用户后续停止 App 下载，剩余步骤不再新增普通 App。黑名单是在单独授权后
才修改，不能把恢复插件自动解释为允许更改 App 注入开关。

不迁移 Apple ID、聊天、相册、账号、Keychain、App 数据容器、VPN 账号／节点／
订阅／配置，也不复制第三方授权字段。不得把原机整个 `/var/jb` 覆盖目标机。

操作前读取：

- `PROJECT_SOURCE_POLICY.md`：源码、环境、源机只读和目标覆盖要求。
- `DEVICE_CONFIG_SAFETY.md`：安全写入、原子替换、回读和回滚。

### 2.2 Mac 与手机要求

- Mac：SSH、Python 3、`dpkg-deb`；原生助手构建需要 Xcode Command Line Tools、
  现有 iOS SDK、`ldid`。Mach-O 核对用 `xcrun otool`／`lipo`。
- 手机：可信配对、目标越狱环境已确认、足够空间、稳定连接。
- 有现成 TrollStore 时先验证，不重复部署 Helper。
- 密码交互输入或只在运行时内存使用；不能写入源码、日志、命令脚本和公开文档。
- 公开文档只留参数和脱敏结果；原始设备文件、截图、真实标识留 Git 忽略的 `tmp/`。

## 3. 连接两台手机并确认身份

### 3.1 建立私有参数

下面变量都由操作者根据现场填写，示例值不是历史设备地址。

```sh
# 在仓库根目录操作；这些变量用于后续命令模板。
RUN_ID="restore-$(date +%Y%m%dT%H%M%S)"
LOCAL_RUN_DIR="tmp/$RUN_ID"
mkdir -p "$LOCAL_RUN_DIR"
chmod 700 "$LOCAL_RUN_DIR"
SOURCE_SOCKET="$PWD/$LOCAL_RUN_DIR/source.sock"
TARGET_SOCKET="$PWD/$LOCAL_RUN_DIR/target.sock"

read -r 'SOURCE_HOST?参考机 SSH 地址: '
read -r 'TARGET_HOST?目标机 SSH 地址: '
# 按现场设定；通常登录 mobile，而不是尝试修改 root 认证配置。
SOURCE_LOGIN="mobile@$SOURCE_HOST"
TARGET_LOGIN="mobile@$TARGET_HOST"
```

`read` 提示语法适用于 zsh。其他 shell 用相应交互方式输入，不把真实值写进教程。

### 3.2 主机密钥校验

先检查 `ssh-keygen -F "$TARGET_HOST"`。地址变化时，读取当前 host key，和此前
已独立确认的**同一台设备**密钥比较。`ssh-keyscan` 只是观察，不能自动信任。

本次新地址的密钥匹配旧设备可信记录后，用 `HostKeyAlias` 指向旧可信身份。
新地址的旧记录可能属于过去的手机，不删除它、不关闭校验，也不把别的设备
密钥当成当前设备。不能确认就停下让用户核验。

```sh
# 无 HostKeyAlias 时：当前地址必须已具有正确、可信的 known_hosts 记录。
ssh -o StrictHostKeyChecking=yes -o ConnectTimeout=8 \
  -o ServerAliveInterval=15 -o ServerAliveCountMax=2 \
  -M -S "$TARGET_SOCKET" -o ControlPersist=600 "$TARGET_LOGIN" \
  'id; sysctl -n hw.machine; sw_vers; readlink -f /var/mobile'
```

参考机使用 `SOURCE_SOCKET` 建立另一条连接。不要让两台设备共用 socket。
输入 SSH 密码后，可通过同一连接执行后续小命令。

### 3.3 身份门槛

本次参考机应为 `iPhone15,3 / 16.3 / 20D47`，目标为
`iPhone13,1 / 16.3.1 / 20D67`。下一轮使用用户实际指定机型，不硬编码本次机型。

```sh
ssh -S "$TARGET_SOCKET" "$TARGET_LOGIN" \
  'id; sysctl -n hw.machine; sw_vers; dpkg --print-architecture; readlink -f /var/mobile'
```

RootHide 目标包应为 `iphoneos-arm64e`；不能通过 `--force-architecture` 塞入普通
rootless 包。本次 `mobile` 认证后可用密码 sudo，不需要另设 root 密码。
检查实际 `id`；把 root 用户名传给 mobile 的旧 socket 不会自动获得 root。

## 4. RootHide 命名空间核对

这是本次多次失败的核心原因：同一个字符串路径在 SSH 和原生进程中，可能
不是同一个实际文件。

| 对象 | 本次 SSH 视图 | 使用原则 |
| --- | --- | --- |
| 插件偏好 | `/var/mobile/Library/Preferences` | 由当前原生偏好 API 和插件消费者共同确认 |
| dpkg 数据库 | `/Library/dpkg/status` | `/var/lib/dpkg` 在本次是别名，先解析再读 |
| 控制中心 | `/var/mobile/Library/ControlCenter/ModuleConfiguration_CCSupport.plist` | 原生助手传当前 canonical jbroot 路径 |
| 系统实际桌面 | `/rootfs/var/mobile/Library/SpringBoard/IconState.plist` | 和 IconOrder 偏好分别确认消费路径 |
| TrollStore IPA 暂存 | `/rootfs/var/tmp/<batch>/` | helper 使用对应真实系统 `/var/tmp/<batch>/` |
| RootHide 配置 | `/var/mobile/Library/RootHide/RootHideConfig.plist` | 本次为 jbroot 消费路径，不能凭记忆改 real-system 同名位置 |

```sh
ssh -S "$TARGET_SOCKET" "$TARGET_LOGIN" \
  'readlink -f /var/mobile; readlink -f /var/lib/dpkg; readlink -f /Library/dpkg'
```

助手只上传到目标机，再解析它和补丁的路径。某些助手要求路径以 canonical
`/private/var/mobile/Containers/Shared/AppGroup/.jbroot-...` 开头；这个随机根
**必须现场解析**，不能复制原机标识。不要一律加上或删掉 `/rootfs`。

本次并非把所有配置都写入 real-system `/var/mobile`。旧迁移记录的路径不能
替代本轮消费者/API 核验。API 返回值、原字节、inode／元数据应对应同一消费文件。

## 5. 源机只读、差异清单和目标覆盖

### 5.1 先取证再制定计划

至少读取两台的：包状态、App 注册表、软件源、插件 Filter、偏好文件、控制
中心、系统 IconState、IconOrder、RootHide 策略及崩溃清单。

```sh
ssh -S "$TARGET_SOCKET" "$TARGET_LOGIN" 'uicache -l' \
  > "$LOCAL_RUN_DIR/target-apps.txt"
ssh -S "$TARGET_SOCKET" "$TARGET_LOGIN" 'cat /Library/dpkg/status' \
  > "$LOCAL_RUN_DIR/target-dpkg-status.txt"
```

本次直接解析 `status` 中 `Status: install ok installed` 的段落。某些环境的
`dpkg-query` 输出容易被误解析；`${binary:Package}` 等格式字符串还可能被远端
zsh 二次展开。需要复杂 shell 时，用显式 `/bin/sh` 和正确引用，不依赖设备 Python。

分别计算 `source_only`、`target_only`、`matched` 和版本差异；包 ID 相同但版本
不同，不能算完全一致。机型能力虚拟包和越狱基础组件不当成缺失插件。

### 5.2 确认覆盖清单，不做强制备份

| 变更 | 只读来源与目标检查 |
| --- | --- |
| 安装插件 | 包 ID／版本／架构、依赖、安装脚本、目标基础组件及碰撞范围 |
| 写插件设置 | 源设置、目标消费者、格式与属主／模式；纯设置文件可整文件覆盖 |
| 写软件源 | 源条目、签名及架构限制、目标基础源；覆盖清单内的对齐文件 |
| 写桌面 | 源布局投影到目标 App 清单，分别确认 IconOrder 与真实 IconState 消费路径 |
| 写控制中心 | 源列表、目标模块清单及实际系统版本的序列化接口 |
| 写黑名单 | 单独授权的主 App／扩展条目、目标隔离策略及原生服务状态 |

只从源机读取和导出；不向源机上传工具、改配置、发通知或重载。不强制在
Mac 或手机备份目标旧配置。源机仍在不等于目标旧状态可恢复：失败后按已确认
源配置修正，只有另存旧状态时才可回滚。历史已有副本不因取消门槛而删除。

需要特权读写时优先交互 sudo。自动化助手应以 `getpass` 读密码，通过 stdin
交给 `sudo -S -p ''`，文件负载另一次传输，禁止把密码和二进制负载混用 stdin。
不要在命令行拼接、日志输出或教程中固化密码。

## 6. TrollStore 与普通 App 的前置恢复

这一节描述前面的 App 恢复路线；**不能把后面的 31 个插件包计数解释成 App 数量**。
本次用户停下载后，外观续接阶段没有新增普通 App。

### 6.1 如果目标还没有 TrollStore

先核对系统支持范围、可信 USB 配对、是否已存在 Helper／TrollStore。
已有可用安装就不重装。需要 USB Helper 安装时，参照
[TrollStore USB 历史流程](trollstore-usb-install.md)：固定目标设备，官方安装器，
只使用用户同意的可移除系统 App 承载 Helper。

Helper 写入成功、手机重启，不等于 TrollStore／Persistence Helper 已完整配置。
应在手机上验证可打开、设置正常、持久化助手状态；未经重启回读不得冒充
重启持久化通过。本文不重新执行安装器或系统保护设置变更。

### 6.2 恢复已授权的 TrollStore App

1. 对照精确 Bundle ID、版本、主 Info.plist、必要扩展及 `_TrollStore` 标记。
2. 只打包 `.app`，使用 `Payload/<App>.app`；不带数据容器、App Group、Keychain。
3. 校验 IPA ZIP 结构、CRC、权限／软链接、架构、扩展和所需可执行文件。
4. 上传已确认的真实系统暂存目录，回读哈希，再次检查目标是否已经安装。
5. 已存在就停止，不能用旧快照决定覆盖，也不加 `force` 或先卸载 App。
6. 调用当前 TrollStore helper 的 `install`，然后回读注册、版本及必要扩展。

```sh
# 手机端模板；所有路径来自当前现场，不是固定路径。
sudo "$TROLLSTORE_HELPER" install "$IPA_REAL_SYSTEM_PATH"
```

helper 返回 0 不替代安装回读；返回特殊警告时先查实际状态，不能盲重装或
删除扩展。仓库 `install-trollstore-manifest.py` 仍有历史默认目标和 placeholder
连接契约；**未完成参数／目标审查前不能当成现成通用入口运行**。

### 6.3 普通 App／阿里系 App 走原生 App Store

使用准确 Apple item ID、Bundle ID、名称、价格和最低 iOS，打开真实商店页面。
可用时优先官方 UI／WDA 定位；工具不可用或 GUI 能力权限拒绝时停在门禁，
不能以历史独立输入脚本绕过当前门禁。

此前商店请求流程见 [原生 App Store 下载](native-app-store-download.md)。
下载请求已提交、按钮变进度圈和最终安装完成分开计数；用户要求“不等待”时
不冒充最终安装回读。遇到账户、支付、身份验证提示交给用户；不主动打开
下载后的高敏 App，也不把 SSH 密码当 Apple ID 密码。

## 7. 恢复插件源

### 7.1 差异按条目，不只按文件名

1. 读取两台当前 `.sources`／`.list`，保留目标基础源。
2. 本次对 deb822 `.sources` 按 Types、URIs、Suites、Components 比较。
   别的格式或带额外架构、签名限制时，必须完整解析那些字段，不能丢弃。
3. 只生成源机有、目标没有的条目到一个新增对齐文件，不覆盖目标全部目录。
4. 将本轮确认的候选上传到目标临时位置，校验后在 sources.list.d 同目录
   设置实际属主／模式并原子重命名；不削弱证书或签名校验。
5. 回读正式文件，再算 source_only／target_only。

本次初次从 7 条增至 36 条，新增 29 条。后来原机变为 35 条，最终目标保留
36 条：source_only=0、target_only=1，未擅自删除目标历史源。

### 7.2 添加成功不等于源可用

第三方源可能超时、证书失败、无签名或索引损坏。`apt-get update` 退出码 0
仍可能伴随 `W: Failed to fetch`、忽略旧索引。检查实际日志和索引，分开报告
“已登记”和“当前可刷新”。不要为了绿色结果关闭 TLS 或强信任不明源。
优先针对所需源／包验证，不让整套不稳定源长期阻塞关键恢复步骤。

## 8. 恢复插件与依赖

### 8.1 来源顺序

优先已核对的 RootHide 原包；自有插件使用对应正式源码／产物。
只能取得原机已安装文件时，按 dpkg 文件清单重建私有恢复包；不能把它叫成
原作者重新编译，也不能宣称已完整取得第三方源码或版权许可。
私有第三方恢复包留 `tmp/`，不新建只有 DEB 没有源码的正式插件项目。

### 8.2 审计 control、脚本和 payload

1. 清理 control 中 `Status`／`Config-Version` 等运行字段，保留版本和依赖。
2. 查看 `preinst`、`postinst`、`prerm`、`postrm`、triggers；二进制脚本也必须审。
3. 按登记清单取文件，用 `tar --no-recursion`，不要递归复制整个公共目录。
4. 排除用户偏好、账户数据、旧 pkgmirror、dpkg 数据库和随机 RootHide 路径。
5. 检查所有 Filter：全局 UIKit 不等于高敏 App 安全排除；软链接和已编译
   loader 路径也属于检查对象。
6. 普通 rootless 包若需转换，优先目标原生 Patcher；不要只改 control 架构。
   本次部分本地包做了路径／Mach-O load-command 适配，保留同源源码与私有记录。
7. 为每个上传包记录哈希，重新确认目标身份，模拟依赖和冲突后才安装。

```sh
# PACKAGE_ROOT 是已审查的 DEBIAN + payload，不是整个越狱目录。
dpkg-deb --root-owner-group -b "$PACKAGE_ROOT" "$PRIVATE_DEB"
shasum -a 256 "$PRIVATE_DEB"
# 目标手机上的交互命令；只能使用当前已核对的一组完整依赖包。
sudo apt-get -s --no-download install "$REMOTE_DEB"
sudo dpkg -i "$REMOTE_DEB"
```

禁止 `--force-depends`／`--force-architecture`，也不自动执行无界限
`apt-get -f install`、全量升级或删除冲突 App。多包恢复分依赖和功能批次，
每批状态回读通过后再进入下一批。

### 8.3 本次特意处理的风险

- 左滑返回原 Filter 是 `com.apple.UIKit`，本次收窄到明确已安装、非高敏 App，
  没有增加阿里／金融／京东进程注入。
- IconOrder 的原 preinst 会清理其他桌面兼容键，本次未执行这段脚本。
- libsandy 安装脚本会 `killall -9 securityd`，暂缓，不把守护进程存在当 Crane 可用。
- Filza preinst 会删除同名 TrollStore App，iCleaner 会清理目录，未直接重放。
- Fix120Hz 及原机的大屏／长焦等能力项不能搬到 12 mini；设备能力不是设置。
- 新包逐个确认 `install ok installed`、版本／架构／依赖。文件哈希不一致时
  查明签名／RootHide 标记的具体差异，不能把所有差异都归为“正常”。

## 9. 覆盖目标插件设置

### 9.1 先确定消费者和允许键

参考实际已安装版本的面板 Resources plist、消费者源码或可核对实现。只选
用户设置：保存值存在时用它；不存在时，只有两端默认值和语义已一致才补默认。

不能复制音量快照、容器／账号、授权、命令序号、状态缓存或 AppData 的
`ADRealBadges`。本次源配置里的 `muteStyle`、`infiniteZoomEnabled` 没找到当前
消费者，未将其当有效设置；未知键不是无条件恢复对象。

纯设置文件在确认兼容后可整文件覆盖，不要求保留其目标旧设置；混合域按
允许设置键覆盖，不携带上述不可迁移内容。下面列的是旧工具的真实接口，
逐键合并不等于整文件覆盖。

### 9.2 两种 patch 格式不能混用

| 客户端 | patch 结构 | 场景 |
| --- | --- | --- |
| `settings-key-client` | 直接的键值字典 | 白名单插件；状态栏调用同源 SISettingsStore |
| `tweak-prefs` | 根对象包含 `set` 字典及 `remove` 数组 | 已审核域、Waqt／Tinge／LetMeKnow、IconOrder |

本次 `remove` 为空，不清空目标其他键。白名单不是可任意放开的全域写入权限。

```sh
bash scripts/tools/settings-key-client/build.sh "$BUILD_DIR"
# 以下为已签名上传后的手机调用格式。
settings-key-client read "$DOMAIN"
settings-key-client apply "$DOMAIN" "$CANONICAL_PATCH"
settings-key-client notify "$DOMAIN"

tweak-prefs read "$DOMAIN"
tweak-prefs apply "$DOMAIN" "$CANONICAL_PATCH"
```

助手不自动确认插件安装、默认值或全部落盘；调用方必须完成这些检查，
但不要求双端备份。助手只在目标运行，源数据用已有只读方式导出。
`notify` 只对源码明确支持的域有效，返回不支持不能当作已经通知。

### 9.3 每域执行顺序

1. 原生读回及原文件解析应一致；不一致就先查路径或缓存，不直接覆盖。
2. 只读取得源设置，确认目标格式、属主／模式和覆盖范围，不备份目标旧配置。
3. 纯设置文件生成完整候选，混合域生成设置 patch；只上传到目标的 canonical 路径。
4. 按已核对的写入路径覆盖目标；直接文件覆盖先暂存并原子替换，状态栏使用
   `SISettingsStore` 保留锁／原子存储行为。旧逐键客户端只支持其声明的 patch。
5. 等待落盘，API／磁盘符合候选；混合域的不可迁移字段和清单外配置保持不变。
6. 如果原生 API 改了序列化格式，仅在语义已落盘后，用同目录临时文件恢复
   原格式和元数据，再回读。RootHideConfig 不走普通偏好格式转换逻辑。
7. 发确切通知；没有即时消费者更新接口的插件进入正常重载验证。

本次断线后重读确认 Tinge 未落盘，重连后补写。Bolders 参数一致却漏了
`tweakEnabled` 总开关，后续补入；只核对尺寸参数会漏掉这个问题。
最终 15 组 144 个键，加 LetMeKnow 3 个键，共 16 组 147 个目标键一致。

## 10. 恢复控制中心

1. 先取得当前模块注册清单，只读取每个 bundle 的 Info.plist，避免为查 ID
   传输整个模块资源树造成超时。
2. 核对源列表中的每个第三方模块 ID 已有对应消费者。缺包先补包，不能靠列表
   凭空创建定位、自动亮度或 VPN 模块。
3. 不要求原配置备份，按确认的源列表使用目标原生 `ControlCenterServices` 序列化接口覆盖。
4. 用本次 SDK 编译 `scripts/migration/controlcenter-settings.m`，签名、上传，
   传它能访问的 canonical CCSupport 路径。
5. 只使用实际存在的 reader selector；本次 iOS 16 为 `_readSettings`，不是猜
   iOS 17 的 `_readSettingsWithVersion:`。类方法签名不匹配就停止。

```text
controlcenter-settings inspect <canonical-config-path>
controlcenter-settings read <canonical-config-path>
controlcenter-settings apply <canonical-config-path> <canonical-patch.plist>
```

patch 使用 `module-identifiers`、`disabled-module-identifiers`、
`userenabled-fixed-module-identifiers`。本次新建文件由原生 serializer 输出 XML；
已有文件还需核对原格式、额外键和权限，serializer 不是任意额外键都能保留。

最终 19／9／1 的结构与源机一致；重载后再次核对原生结果、磁盘与源机。
6 个第三方排列模块为：定位、自动亮度、照片模块、Safari、VPN、锁屏音量。
按钮列表写入和功能可用分开验收，不为了看效果点击网络、支付、扫码、VPN。

## 11. 恢复桌面、文件夹和 Dock

### 11.1 候选必须由新现场计算

读取原机 IconOrder、目标真实 IconState、目标当前 App 注册表。目标尚无
IconOrder 保存文件时，先保留 `.absent`，不能把缺文件说成桌面空白。

候选算法：

1. 使用原机页／文件夹／App 的相对顺序，文件夹递归处理。
2. 过滤目标未安装 App，不制造空图标、不触发下载。
3. 目标原有而原机布局没列出的 App 保留在末页，不卸载或隐藏丢失。
4. Dock 投影为原机的已安装应用：电话、信息、微信、设置。
5. 保留目标自己的小组件对象；不复制原机小组件的内部状态标识。
6. 为新页面／文件夹生成布局标识，保留目标非目标布局数据；壁纸不改。
7. 校验图标引用唯一、目标原有有效图标无遗漏、所有新引用都已登记。

本次 Patcher 安装后新增图标，重新生成候选，将它归入原机工具文件夹。
最终 104 个唯一 App 引用、2 个小组件、2 页。不能直接复用安装 Patcher 前的
103 图标候选。不存在的源 App 数量随实际注册状态变化，见每轮候选报告。

### 11.2 写入及消费验证

先分别只读核对 real-system IconState 和 IconOrder，再通过 `tweak-prefs` 设置
`IconOrder`／`enabled`，保留域内其他键。调用客户端的 `iconorder-xml` 时，用
IconOrder 相同的 Foundation `writeToFile:atomically:`，不是剥离文件夹名称后重写。

源文件夹名可能含 XML 控制字符；macOS Python 严格 parser 会失败，但原生
Foundation 能读。用 `iconorder-disk-only` 导出原生解析的 binary 证据，不自动
清空、改名或修复合法的消费者数据。binary 导出文件不等于应覆盖生产文件。

```text
tweak-prefs iconorder-disk-only com.ichitaso.iconorder
tweak-prefs springboard-layout-read com.ichitaso.iconorder
tweak-prefs iconorder-xml com.ichitaso.iconorder
tweak-prefs iconorder-disk-read com.ichitaso.iconorder
```

重载后从真实 IconState 再读。系统改内部根标识正常，但不能因此忽略 App
丢失、重复、顺序、Dock、文件夹内容或小组件改变。本次语义比较一致，
不是原始文件 SHA-256 一致，也不是所有视觉像素一致。

## 12. 重载与运行核验

1. 包、配置及预期变更范围都通过后，确认用户授权，仅在目标重载。
2. 保存崩溃清单、当前 SpringBoard PID、已写配置证据。
3. 在目标调用一次必要 `sudo sbreload`；不要循环重载碰运气。
4. 重连确认身份、进程 PID、新布局、原生控制中心回读和偏好落盘。
5. 本次在新增 Patcher／AppData 等包后又做一次必要重载，记录为不同事件。

手机缺 `ps`／`top` 不等于没有进程。可通过 `launchctl list` 找 SpringBoard；
本次用系统 `footprint -p <当前PID> -v -w` 只读映射，不附加调试器、不向 App
注入。字符串映射存在只证明加载，不证明每个 Hook 功能已测试。

最终确认 12 个组件：BoldersReborn、IconOrder、SquidGesture、StatusIndicators、
Waqt、Tinge、PrimalFolder2、LockAudioProfiles、DoubaoPowerButton、AppData、
WeChatNotiAvatar、LetMeKnow。检查窗口内没有新增崩溃文件。

### GUI 验收限制

本次正式 GUI 预检返回 `mobile_not_authorized`，流水线在此停止。
不得改成独立 HID 工具绕过当前门禁或把旧截图当本轮验收。
已经取得的锁屏黑图不能证明界面正常，也不能证明界面异常。
控制中心视觉、文件夹展开、可访问性、具体业务 App 功能及长期功耗仍未验收。
当前截图、前台和锁屏状态不足时停止输入，不打开高敏 App 做试验。

## 13. 后续补齐阿里／蚂蚁黑名单

### 13.1 为什么另做一轮

用户单独授权“主动加入阿里系黑名单”。本次选择最小方案：合并明确的
Ali／Ant `appconfig` 条目，而非复制原机整份 RootHide 配置。
官方 UI／接口优先；批量原生开关无法使用时，经本次明确授权才使用已核对
消费者路径、原生 XML 暂存和原子发布，GUI 开关往返仍标为未验证。

### 13.2 只读盘点与建清单

1. 新现场确认两台 RootHide 版本、配置路径和原文件存在状态。
2. 原机 Ali／Ant 主 App 条目与目标注册表取并集，核对安装包主 Info.plist
   和 `PlugIns/*.appex/Info.plist`。这是安装元数据，不是业务沙盒数据。
3. 每个扩展必须核对实际 Bundle ID 与所属主 App，不能猜固定后缀。
4. 本次目标主 App：淘宝、支付宝、闲鱼、高德、夸克、点淘、一淘、阿里云盘、
   大麦、钉钉、饿了么。原机天猫、盒马、阿里妈妈预先列入。
5. 只读核对目标 RootHide 配置、相关策略和清理规则，不强制备份，也不整份照搬源机策略。
6. 先查越狱服务原状态；本次淘宝、支付宝原先返回 false，目标配置确实不存在。

### 13.3 原生格式与原子写入

`RootHideConfig.plist` 必须是 XML，不能把 Python FMT_BINARY 或普通 CFPreferences
的二进制结果直接覆盖它。官方 Manager 的写法需要 `appconfig` 可变字典。

使用 `scripts/migration/blacklist-config-stage.m`：只允许明确 Ali／Ant 主 ID
及其扩展的补丁，调用 Foundation 原生 serializer，**只写同目录新暂存文件**。
该助手不自动发布、并发检测或回滚；调用方必须检查发布与并发，
不要求备份，但没有旧状态副本时不能承诺回滚。

```text
blacklist-config-stage <canonical-original-config> <canonical-patch> <canonical-stage>
```

patch 只含 `bundle_ids` 数组。暂存文件名必须符合客户端要求，不能用任意路径。
发布前核对 XML 语法、Foundation 可变字典、完整语义、元数据，确认正式文件
和其他策略仍等于备份基线，然后同文件系统原子替换。

原文件存在时保留现场官方属主／模式；本次文件原先不存在，mobile 原生 writer
配合 umask 077 生成 0600 文件，记录这个实际结果，不推广为所有设备固定模式。
官方 setuid Manager 另可能输出 root:mobile／0600，不能为方便读取随意改属主。

### 13.4 不能只验证 plist

`scripts/migration/blacklist-consumer-check.m` 调用当前 `libjailbreak` 里的越狱
服务接口，逐 Bundle ID 查询；本次接口 domain/action 从实际库核对，不猜版本。

```text
blacklist-consumer-check inspect <canonical-staged-config>
blacklist-consumer-check query <bundle-id> [more-bundle-ids...]
```

本次 73/73 返回 true、磁盘重复回读、原机与非目标配置不变、清理规则不变，
检查窗口内没有新增崩溃。Manager UI 开关往返、业务 App 启动和运行镜像纯净
没有验收。只有授权到具体范围，才可以补做相应检查，不擅自扩大操作。

**重要：黑名单不是撤销 TrollFools 修改。** 已经写进 App 包的 dylib／load command
不会因 `appconfig=true` 自动移除；本次没有清理高敏 App 的既有注入。
它也不会自动覆盖以后新装 App／新增扩展，更不保证 App 无越狱检测。

## 14. 断线续跑与回滚

### 14.1 命令超时先回读，不重复写

1. 检查原命令 session／PID／设备任务是否仍在运行，socket 是否有效。
2. USB 未看到设备／Wi-Fi 不可达时先恢复连接，不改 SSH 认证或反复安装。
3. 新地址必须重新确认主机密钥、机型、系统、RootHide 根和目标身份。
4. 重新读 status、配置/API、实际桌面；按已经落地的权威状态继续。
5. 某个 write 超时可能已落盘，也可能没有。Tinge 本次重读确认没有落盘后
   才补写；控制中心早先 tar 超时不等于配置已经变了。
6. 有并发用户编辑，不用旧 expected 覆盖；重新取基线、重新生成最小 patch。

### 14.2 分类回滚

| 类型 | 回滚原则 |
| --- | --- |
| 旧配置存在 | 无旧副本时按已确认源候选修正；另有旧副本时可原子恢复并回读，不承诺无备份回滚 |
| 原配置不存在 | 仅在正式文件仍是本轮发布内容时撤回本轮新文件，恢复 `.absent`，不删除用户新配置 |
| 软件源 | 撤回本轮新增／改动的 exact 文件，保留其他来源和并发编辑 |
| 新装插件 | 先审依赖和卸载脚本；明确授权后撤回本轮包，碰撞文件仅在有旧副本时恢复，再核对 status |
| 升级插件 | 使用已验证的原包／原文件恢复；不把整个旧 status 盖回去 |
| 桌面 | 分别处理 IconOrder／真实 IconState，回读消费者；必要重载需明确范围 |
| 黑名单 | 发布或服务回读错误时按目标隔离清单修正；只有旧状态已保存时才回滚，遇并发编辑停止 |

备份包数据库是取证和恢复参考，不是全库覆盖许可。旧 status 覆盖会破坏其他
并发安装状态。卸载脚本可能有停止服务、删目录等副作用，不能为“快速回滚”
直接执行任意 `dpkg -r`。本次并未做全量设备回滚。

## 15. 清理、交付和剩余项

### 15.1 清理的精确边界

只删除本轮上传的助手和 patch 精确路径，关闭本轮 socket，保留源导出、
安装日志、恢复清单和回读报告；已有历史副本不删除。本次核心收尾移除 29 个明确临时文件；黑名单
阶段另清理自己的 checker／stager／patch。不用通配符清理别轮产物。
不要停止商店后台下载，不删除已经安装 App、源码或最后可回滚包。

```sh
ssh -S "$TARGET_SOCKET" -O exit "$TARGET_LOGIN"
ssh -S "$SOURCE_SOCKET" -O exit "$SOURCE_LOGIN"
```

### 15.2 仍未完成的 20 个源机独有包

按最后保存的包差异，不是本轮文档写作实时设备清单：

- 机型能力 3 项：大屏、长焦、Perseus 能力，不迁移到 12 mini。
- 120Hz／性能／工具：`cn.zqbb.fix120hz`、`cn.zqbb.holdcpu`、`cn.zqbb.hello.mnt`。
- 容器：`com.opa334.crane`、`com.opa334.libsandy`，服务和容器功能需独立处理。
- 文件／清理：`com.tigisoftware.filza64bit`、`github.poqw312.icleanerpro`、
  `com.dao.filzacrack`，不能照搬危险脚本或授权相关逻辑。
- App 内组件：`byg.iosios.net.advertisement`、`byg.iosios.net.dazzpro`、
  `byg.iosios.net.mycamera.rootless`、`byg.iosios.net.picsew.rootless`、
  `byg.iosios.net.stormsniffercrack-rootless`、`com.25mao.doutu.rootless`、
  `com.25mao.miyou.rootless`、`com.25mao.wcplugins.rootless`、
  `com.dumpapp.wechat-rootless`。来源、许可、当前 Filter／依赖和配置需单独审查。

剩余 20 不是都适合无条件安装，核心外观完成不等于全插件完成。
GUI 视觉／文件夹展开及长期耗电依然未验证。

### 15.3 证据与可维护源码

| 位置 | 用途 |
| --- | --- |
| `tmp/resume-config-20261118/reconnect-20261118T233930/final-completion-report.json` | 核心恢复最终结果及 20 包差异 |
| 同目录 `preferences-final.json`、`letmeknow-result.json` | 144＋3 个目标键回读 |
| 同目录 `runtime-final.json`、`target/IconState-final.plist` | 映射、崩溃与真实布局 |
| 同目录 `extra-result.json`、`helper-cleanup.json` | 后续 10 包及精确助手清理 |
| `tmp/resume-config-20261118/install-result.json`、`reviewed-install-result.json` | 前两批 8＋14 包 |
| `tmp/ali-blacklist-20261119/result.json`、`manifest.json` | 后续 73 个黑名单条目和服务回读 |
| `scripts/tools/settings-key-client/` | 正式白名单偏好客户端源码及构建 |
| `scripts/migration/tweak-prefs.m`、`controlcenter-settings.m` | 布局／偏好读写及原生 CC serializer |
| `scripts/migration/blacklist-config-stage.m`、`blacklist-consumer-check.m` | 黑名单暂存与服务查询源码 |
| `plugins/status-indicators/SISettingsStore.m` | 状态栏同源原子配置存储 |

这些 `tmp/` 证据含私有现场参数，不提交；其中 one-off Python 脚本不能直接
用于下一台手机。留在 `scripts/migration/` 的其他历史脚本也需逐个读参数、
确认当前路径和目标，不能看到脚本名就执行。构建成功不等于设备执行成功。

本文不重新发布预览 dylib、不操作 iCloud、不提交代码。公开发布前对实际
变更文档及包／源码归档做敏感信息检查，不能把普通文本无命中当全库脱敏。

## 16. 本次包与设置明细

下面版本用于重建本次执行记录，不表示现在必须升级或降级到这些版本。


### 16.1 安装包明细

三批共 32 次包安装／升级登记：8＋14＋10。其中 CCSupport 为升级，
其余 31 项是本轮新增；不含更早外观轮次中已经安装的 6 个包。

#### 第一批：自有包

| 包 ID | 本轮版本 | 动作 |
| --- | --- | --- |
| `ayao.aipowerbutton` | 1.0.6 | 新增 |
| `ayao.airpodsautonoise` | 1.0.2 | 新增 |
| `ayao.feiliancontrolcenter` | 1.3.1 | 新增 |
| `ayao.lockaudioprofiles` | 0.1.18 | 新增 |
| `ayao.locklowpower` | 1.2.2 | 新增 |
| `ayao.photosrecentssort` | 0.2.9 | 新增 |
| `ayao.statusindicators` | 0.1.2 | 新增 |
| `ayao.trollfoolsnoads` | 0.1.0 | 新增 |

#### 第二批：外观、手势、依赖

| 包 ID | 本轮版本 | 动作 |
| --- | --- | --- |
| `ayao.hidedoubaopip` | 1.0.30 | 新增 |
| `byg.iosios.net.autofaceunlock-rootless` | 1.1-7 | 新增 |
| `com.25mao.leftpan` | 2.0-1 | 新增 |
| `com.ichitaso.iconorder` | 1.0.5 | 新增 |
| `com.ichitaso.primalfolder2` | 0.1.2 | 新增 |
| `com.imkpatil.letmeknow` | 1.4.2 | 新增 |
| `com.lclrc.controltab` | 1.0 | 新增 |
| `com.lclrc.squidgesture` | 2.1.6 | 新增 |
| `com.nightwind.boldersreborn` | 1.1.2 | 新增 |
| `com.opa334.altlist` | 1.0.11 | 新增 |
| `com.opa334.ccsupport` | 1.3.13.1 | 升级已有 CCSupport |
| `com.opa334.libundirect` | 1.1.6 | 新增 |
| `com.p2kdev.quitall` | 1.3 | 新增 |
| `com.squidforce.disablepastealert16` | 1.0 | 新增 |

#### 第三批：Patcher、工具依赖和组件

| 包 ID | 本轮版本 | 动作 |
| --- | --- | --- |
| `com.roothide.patcher` | 2.1.5 | 新增 |
| `libxar1` | 1.8.0.487.100.1-1 | 新增 |
| `file` | 5.43 | 新增 |
| `libmagic1` | 5.43 | 新增 |
| `gawk` | 5.1.0-2 | 新增 |
| `libmpfr6` | 4.1.0 | 新增 |
| `plutil` | 0.2.2+2 | 新增 |
| `com.iosdump.appdata` | 2.7.5 | 新增 |
| `byg.iosios.net.dyyy` | 2.3-0 | 新增 |
| `com.netskao.wechatnotiavatar` | 1.3-1 | 新增 |

### 16.2 对齐设置域明细

| 设置域 | 目标键数 |
| --- | ---: |
| `ayao.statusindicators` | 53 |
| `ayao.lockaudioprofiles` | 11 |
| `com.nightwind.boldersrebornprefs` | 17 |
| `ayao.photosrecentssort` | 5 |
| `com.25mao.leftPanPrefs` | 8 |
| `ayao.aipowerbutton` | 5 |
| `com.p2kdev.quitall` | 2 |
| `ayao.airpodsautonoise` | 2 |
| `com.ichitaso.primalfolder2` | 6 |
| `com.lclrc.squidgestureprefs` | 9 |
| `com.netskao.autofaceunlock` | 3 |
| `ayao.feiliancontrolcenter` | 2 |
| `ayao.locklowpower` | 1 |
| `com.p2kdev.waqt` | 13 |
| `com.p2kdev.tinge` | 7 |
| `com.imkpatil.letmeknow` | 3 |
| **合计：16 组** | **147** |

设置计数不包含桌面 `IconOrder`、控制中心数组、RootHide 黑名单 73 条、
运行缓存或账户数据。Crane 未计入此次最终设置对齐；源机的部分持久化字段
因没有当前消费者或属于状态快照被排除。

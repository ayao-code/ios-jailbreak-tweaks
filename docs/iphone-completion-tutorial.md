# iPhone 补齐与对齐教程：插件、设置、布局、App 和 VPN

> **当前恢复规则（2026-11-20）：源机只读、目标机覆盖，不要求双端备份，不强制保存目标旧配置。**
> 只从源机读取和导出，不向源机上传助手、安装、改配置、发通知或重载。恢复清单内的兼容纯设置文件可整文件覆盖；
> 混有账号、授权、容器或运行状态的文件只覆盖设置部分，清单外及高敏隔离策略不照搬。未保存目标旧状态就不承诺回滚。
> 下文历史数字、备份记录及旧工具能力保留，不代表新一轮仍须沿用旧备份流程。

> 越狱及恢复的统一顺序见 [完整越狱与恢复流程](jailbreak-and-restore-guide.md)。
> 本篇属于更早的专项执行记录，不代替范围确认、巨魔安装和实际 Jailbreak 前置流程。

> **历史轮次提示：**本篇保留较早恢复／App／VPN 轮次的数字和观察，不能与
> 后续 `resume-config` 结果相加或当作当前设备状态。2026-11-18 续接恢复及
> 19 日单独授权的阿里／蚂蚁黑名单补齐，详见
> [恢复与配置对齐详细步骤](iphone-restore-step-by-step.md)。后续黑名单已经
> 完成 73/73 服务回读；本篇旧阶段的“没有黑名单基线”不代表它仍未补齐。

> 这是 2026-11-17 至 18 日实际操作的统一教程，不是对手机做全量克隆。
> 参考设备为 iPhone 14 Pro Max / iOS 16.3，目标为 iPhone 12 mini / iOS 16.3.1，
> 两台均使用 RootHide。以下结果来自本次保存的回读记录，不代表以后设备状态。

## 1. 先看结果，以及“补齐”到底包括什么

| 部分 | 实际做了什么 | 验证到了哪一步 |
| --- | --- | --- |
| 原有插件设置 | 14 组、125 个键对齐，修改 124 个，1 个原本一致 | 原生接口、磁盘及非目标键回读 |
| 缺失外观插件 | 安装 Waqt、Tinge、HideAllBar、PrimalFolder2 中文包、CCLess，另加 Alderis 依赖 | 6 包安装状态、版本、架构和 145 个文件核对 |
| 新增插件设置 | Waqt 13 键、Tinge 7 键 | 原生接口及磁盘一致 |
| 控制中心 | 启用 19 项、禁用 9 项、固定启用 1 项 | 配置字典与参考一致，目标界面截图 |
| 桌面与文件夹 | 按参考分类整理目标已有 App，2 页，Dock 对齐 | 运行布局与候选一致，封面已观察；展开未验收 |
| 缺失普通 App | 桌面阶段过滤 85 个缺失项，没有补下载；保留 3 个目标额外 App | 当轮 App 清单未变 |
| App Store | 独立输入工具操作商店，提交 10 款阿里系下载请求 | 下载开始；按要求不等待全部安装 |
| VPN 软件 | 最终 9 款均有，较该轮开始新增 6 款 | 版本、build、主程序及扩展匹配；不证明连通性 |

**注意三层区别：配置值相同、实际运行生效、界面完全一致，不是一回事。**
机型、已安装 App、小组件、通知和壁纸不同，不能把两台界面说成逐像素相同。
设置的 125 键与后补的 20 键属于两轮不同范围；系统开关、控制中心和 IconOrder
布局不计入这两个设置键计数。

## 2. 开工前的范围和工具

### 2.1 先确认范围，不能一股脑复制

分别决定是否要：安装缺失插件、复制插件选项、排列控制中心、调整桌面、下载
缺失 App、补 VPN 软件。用户取消某一项后，立刻停止那部分，不把“都补齐”
理解成抹掉手机、安装所有 App 或复制全部系统数据。

本次不迁移：Apple ID、密码、生物识别、聊天、照片、App 数据、Keychain、
VPN 账号/订阅/节点/配置；不复制第三方授权字段，不自动登录、付款或开启 VPN。
阿里/蚂蚁、银行/支付/证券及京东 App 禁止注入，不为迁移开启其 tweak injection。

### 2.2 准备环境

- Mac：SSH/SCP、Python 3、Pillow；打包需要 `dpkg-deb`，原生工具需要 Xcode
  Command Line Tools、已有 iOS SDK、`ldid`。设备已有的 TrollStore 不重装。
- 所有地址、连接、密码、UDID、容器路径通过私有参数提供。SSH 登录与 `sudo`
  用交互认证，不把密码写进教程、命令文件或日志。
- 手机接电、保证稳定连接。普通输入必须确认未锁屏；设置密码时由本人正常
  认证。只在实时确认没有密码时，允许正常亮屏上滑，不绕过身份验证。
- 先读仓库 `PROJECT_SOURCE_POLICY.md` 和 `DEVICE_CONFIG_SAFETY.md`。

以下使用 `$SOURCE_HOST`、`$TARGET_HOST`、`$SOURCE_SOCKET`、`$TARGET_SOCKET`、
`$KNOWN_HOSTS`、`$LOCAL_RUN_DIR` 等**调用者已配置的私有变量**；示例不能直接
复制执行，必须先核对具体设备及动作范围。

```sh
# 在仓库根目录；RUN_ID 是本轮时间戳，不放真实设备身份。
LOCAL_RUN_DIR="tmp/$RUN_ID"
mkdir -p "$LOCAL_RUN_DIR"
chmod 700 "$LOCAL_RUN_DIR"

# 密码由 SSH 交互输入，连接建立后后续操作复用这个专用 socket。
ssh -o UserKnownHostsFile="$KNOWN_HOSTS" -o StrictHostKeyChecking=yes \
  -o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 \
  -M -S "$TARGET_SOCKET" -o ControlPersist=1800 -fN "$TARGET_HOST"

ssh -S "$TARGET_SOCKET" "$TARGET_HOST" 'sysctl -n hw.machine; sw_vers; id'
ssh -S "$TARGET_SOCKET" "$TARGET_HOST" 'uicache -l'
ssh -S "$TARGET_SOCKET" "$TARGET_HOST" /bin/sh -s <<'REMOTE'
dpkg-query -W -f='${binary:Package}\t${Version}\t${Architecture}\t${Status}\n'
REMOTE
```

参考设备建立另一条专用连接，做同样盘点。SSH 提示主机密钥变化时，**停止**，
比对已有可信密钥或由本人独立核验，不能删除旧记录或关闭校验继续写手机。
本次两个新 IP 的密钥均匹配已有可信设备记录，才建立连接。

### 2.3 RootHide 路径是最容易出错的地方

SSH 的 `/var/mobile` 可能是 jbroot 命名空间，真实系统目录通常需要通过
`/rootfs` 视图读取；TrollStore helper 则可能使用真实系统路径。

```sh
ssh -S "$TARGET_SOCKET" "$TARGET_HOST" 'readlink -f /var/tmp/your-patch.plist'
```

必须按当前现场解析路径，不硬编码随机 `.jbroot-*`。例如从 SSH 上传到
`/rootfs/var/tmp/...` 的 IPA，传给真实系统 TrollStore helper 时使用对应的
`/var/tmp/...`；补丁传给偏好工具时又必须是工具消费者能看到的规范路径。
不能盲目给所有路径加上或删掉 `/rootfs`。

## 3. 源机只读盘点，目标按清单覆盖

### 3.1 插件不只比较包名

比较安装包 ID、版本、架构、依赖、文件清单、实际 Filter、设置面板及消费者。
普通 rootless 包和 RootHide 包不能混用。本仓库当前 rootless 使用
`iphoneos-arm64`，RootHide 使用 `iphoneos-arm64e`，不能强制忽略架构。

本次 Bolders Reborn 和 PrimalFolder2 已在两台安装，偏好字典一致。但 Waqt、
Tinge、HideAllBar 和 CCLess 缺失：仅复制文件夹设置，无法补出周边外观和模块。

### 3.2 修改前确认什么

只读取得源机设置、软件源和布局，确认目标的版本、消费路径、格式及属主/
权限。列出本轮允许覆盖的文件或设置部分，不强制备份目标原配置。
兼容的纯设置文件可整体覆盖；混合偏好只覆盖可迁移设置，安装仍走包管理器
或对应官方渠道，不能把源机整个越狱根目录盖过去。

API/磁盘不一致或发现并发配置变化时先停止并重新确认候选，不修改源机。

## 4. 缺失插件是怎样补上的

本次补装：

| 包 ID | 版本 | 用途 |
| --- | --- | --- |
| `byg.iosios.net.waqt` | 1.4 | 时间/日期 |
| `byg.iosios.net.tinge.rootless` | 1.2.2 | 角标配色 |
| `com.cydiabc.hideallbar-rootless` | 2.1-1 | 底部横条 |
| `com.dao.pf2.cn` | 0.1.2 | PrimalFolder2 中文设置面板 |
| `com.dao.ccless` | 2.1.0.1 | 控制中心模块集合 |
| `ws.hbang.alderis` | 2.2 | Tinge 依赖 |

优先使用来源和版本已核对的原包。本次无现成合适原包时，从参考设备的
`dpkg -L <package>` 清单重建私有包：

1. 读取 package control、依赖、架构及 maintainer scripts；有脚本必须另审。
2. 按登记清单取文件，tar 使用 `--no-recursion`，不把整个目录下其他插件
   顺带打入。不收偏好文件、账号数据、旧 pkgmirror 和整个越狱根。
3. 保留原模式、软链接、`.roothidepatch` 与 `.jbroot` loader 链接；后者只保留
   当前消费者需要的规范目标，不复制参考手机的随机根。
4. Filter 仅限 SpringBoard/系统设置；PrimalFolder2 中文包保持设置专用，
   不增加第二套 SpringBoard 文件夹 Hook。
5. Mac 重建 `.deb`，上传后核对 SHA-256、目标身份、冲突及依赖。

```sh
# PACKAGE_ROOT 是本地已审查的 DEBIAN/ + payload，不是整个手机目录。
dpkg-deb --root-owner-group -b "$PACKAGE_ROOT" "$PRIVATE_DEB"
shasum -a 256 "$PRIVATE_DEB"
scp -o ControlPath="$TARGET_SOCKET" "$PRIVATE_DEB" "$TARGET_HOST:$REMOTE_STAGE/"

# 在目标手机终端，经确认文件和完整依赖集合后：
sudo dpkg --simulate -i "$REMOTE_STAGE/package.deb"
# 模拟通过后才安装；依赖按已审查顺序与本轮所需包一起提供。
sudo dpkg -i "$REMOTE_STAGE/package.deb"
```

本次 6 包模拟与安装通过；不是使用 `--force-depends` 或强改架构。第三方包
来自参考设备，不代表重建了它们的源码，也不代表已全面完成供应链/版权审计。
第三方产物留私有 `tmp/`，不在仓库创建只有 DEB 没有可维护源码的插件目录。

**安装验证：**包状态为 installed，版本/架构正确；145 个安装文件回读，9 个
Mach-O 只在已确认 RootHide 标记及签名区域变化。不得把任意字节差异都解释成
正常签名，更不能只核对文件大小。补丁链接与实际 loader 依赖还要验证存在。

## 5. 插件设置是怎样对齐的

### 5.1 区分纯设置文件与混合偏好

从两台已安装插件的设置面板 Resources plist 提取 `defaults`、`key`、默认值
及变更通知，再结合实际消费者源码。源机有值用实际值；没保存的键只有两端
相同版本面板默认值一致才用默认值，不直接推断为关闭。

纯设置文件在版本和格式兼容后可整文件覆盖目标；混合偏好仍排除：授权、
license、运行版本/迁移状态、音量快照、命令 ID、账号/容器标识。
缺消费者的不写；本次 TrollSpeed 历史域误纳入后已撤回，恢复原本不存在状态。

### 5.2 三种写入方式

| 类型 | 实际接口 | 不能做什么 |
| --- | --- | --- |
| 普通插件选项 | CFPreferencesSetMultiple / Synchronize | 不清空域，不带走账号/运行键 |
| 状态指示 | 同源 `SISettingsStore.m` 原子存储 | 不绕过文件锁、格式、last-good 和通知 |
| Crane | 自身 manager 的两个全局界面选项 | 不复制 craneprefs 的 App/容器/Keychain |

```sh
bash scripts/tools/settings-key-client/build.sh "$BUILD_DIR"
# helper 上传、签名、当前 HOME 和实际执行验证都通过后，在手机调用：
settings-key-client read "$PREFERENCE_DOMAIN"
settings-key-client apply "$PREFERENCE_DOMAIN" "$CANONICAL_PATCH_PATH"
settings-key-client notify "$PREFERENCE_DOMAIN"
```

`apply` 接受**设置键到值的字典**，只合并，不删除。`allowed-settings.h` 是
明确白名单，不能为了方便直接放开任意域。它不是一键迁移脚本：调用方仍要
完成版本、数据类型、落盘、格式、权限及清单外不变量验证。该工具只合并
设置，不能用它声称已完成整文件覆盖；整文件覆盖须使用已核对的文件写入路径。

另一个旧工具 `scripts/migration/tweak-prefs.m` 的补丁格式是
`{"set": {...}, "remove": []}`，与上述客户端不同；不要混用。Crane 使用
`scripts/migration/crane-root-settings.m`，只修改全局快捷菜单选项。

CFPreferences 可能延迟写盘或重序列化：接口返回后等待磁盘语义一致，若
改变原 XML/binary，必须使用同目录临时文件保留原格式和真实权限后原子替换，
再核对 API/磁盘。RootHide 配置不走这条通用处理路径，始终保持它的官方格式。

原轮 125 键，新补 Waqt/Tinge 20 键；8 组已知插件收到确切设置通知。第三方
插件可能要重载消费者才能生效，因此保存成功后还要走下一节。

## 6. 控制中心和桌面怎样恢复

### 6.1 控制中心：先有模块，再排列

先盘点系统和已安装第三方 `.bundle/Info.plist`，核对每个模块 ID。缺 CCLess
时，复制列表不会凭空出现定位、自动亮度等按钮。

补模块后用 `scripts/migration/controlcenter-settings.m` 调用原生
ControlCenterServices 序列化接口，对准已核对的 CCSupport 配置路径：

```text
controlcenter-settings inspect <canonical-CCSupport-config-path>
controlcenter-settings read <canonical-CCSupport-config-path>
controlcenter-settings apply <canonical-CCSupport-config-path> <canonical-patch.plist>
```

patch 包含 `module-identifiers`、`disabled-module-identifiers`、
`userenabled-fixed-module-identifiers` 三个数组。本次读写接口选择实际存在的
`_readSettings`，不能用别的 iOS 版本签名猜调用。文件保留原格式、权限及版本
等其他键；最终目标字典与参考相同，计数 19/9/1，且截图确认入口展示。

检查时不点击网络、VPN、支付、扫码等业务按钮，模块展示不等于功能已测试。

### 6.2 桌面：把参考布局投影到目标现有 App

读取**当前实际 IconState**、App 注册表和 IconOrder 保存的布局，不根据历史
清单猜。主屏页中的文件夹要递归展开，“第一屏 App”可能含大量文件夹内容。

本次候选规则：

1. 采用参考页、文件夹和 App 的相对顺序。
2. 过滤目标未安装的 85 个 App，不下发下载安装，不制造空图标。
3. 目标已有但参考布局没有的 3 个 App 移到后页保留，不卸载。
4. Dock 采用参考的 4 个已安装 App，保留目标自己的小组件对象及内容状态。
5. 文件夹/页面新的布局标识按目标生成，不搬业务账户数据。壁纸保持目标原样。

保存到 IconOrder 的 `IconOrder` 键，保留其他键，确认启用后重载。上游源码
表明 `SBDefaultIconModelStore` 启动时从此键恢复，不能只修改偏好却不重载。

本次结果 2 页。运行 IconState 与候选比较时忽略系统重建的页面/文件夹临时
标识，但不能忽略 App 顺序、缺失、重复、Dock 或文件夹内容。

### 6.3 重载和视觉验收

设置和模块验证通过且用户授权后，在目标手机调用原生 `sudo sbreload`。
本次两次重载分别加载新插件与新布局，均确认 SpringBoard PID 更换。

截图工具 `store-screen`；系统 UI 输入 `scripts/tools/home-ui-input/`；App Store
输入为 `SDP_ALI_RESTORE_UI` 变体。这些是独立短生命周期工具，不注入业务 App。
坐标来自当前截图，锁定状态和前台布局异常、页面移动、黑图、弹窗时停止。

本次观察到：时间/日期、角标、底部横条、文件夹封面和控制中心入口生效。
**文件夹展开没有可靠截图，尚未验收；不能把配置回读当成展开效果证明。**
电量百分比、粗体文本是缩减范围前已通过系统界面打开的两项，保留而未回滚；
除此之外不做系统设置全量克隆。

## 7. App Store 下载：为什么不用你逐个点

真实链路：**SSH → 独立系统输入工具 → 手机原生 App Store**。有可用 WDA
时优先元素定位；本次 WDA 是占位条目，没有可启动 runner，备用工具实际跑通。
“有 WDA 图标”不等于可用，“WDA 不可用”也不等于只能让用户手点。

1. Apple lookup 核对精确 item ID、Bundle ID、名称、免费价格和最低 iOS。
2. `uiopen --url` 打开准确 `itms-apps://` 页面，不根据猜测的 ID 或模糊搜索点。
3. 新截图确认标题和“获取/云下载”，工具核对未锁定及 App Store 前台。
4. 再截图比对标题/按钮区域；稳定后只点一次，点击前记录 attempt。
5. 看按钮变加载圈/进度/打开；任务只要求下载时立即切下一款，不等下载完。
6. 账号验证/付费提示停止；截图超时后重新查看，不盲重试，以免取消下载或
   点击已变成“打开”的业务 App。

```sh
bash scripts/migration/build-native-store-helpers.sh "$BUILD_DIR"
# store-ui-input / store-screen 签名、上传及现场执行验证后：
store-screen --state
store-ui-input --check com.apple.AppStore
store-ui-input tap com.apple.AppStore "$BUTTON_X" "$BUTTON_Y"
```

Mac 的参数化脚本 `scripts/migration/native-app-store-control.py` 与依赖清单已
发布在远程主分支；旧本地 checkout 可能还没有它们，先确认文件存在，不重置
脏工作区。该脚本不是自动识别一切：要显式提供主机、socket、设备型号/系统、
尺寸、标题/按钮区域及 `--reviewed`，并逐张确认点击前后截图。

完整调用见 [App Store 下载指南](native-app-store-download.md)。本次 10 款
下载请求已提交，按用户要求未等全部安装，不能把这个计数写成 10 款都验收。

## 8. VPN 软件怎样补齐，和普通 App 安装有什么区别

### 8.1 不能只搜索名字里有没有 VPN

读取全部候选 App 的主 Info.plist 与 `PlugIns/*.appex/Info.plist`，查找
`com.apple.networkextension.packet-tunnel` 等扩展，再结合名称判断。Tools
没有 VPN 字样，但包含隧道扩展，所以纳入；不要把所有扩展应用一概当 VPN。

本次参考 9 款，目标原有飞连、Shadowrocket、Tools，缺 6 款：

| App | 版本 | 最终核对 |
| --- | --- | --- |
| Storm Sniffer | 2.2.1 | 新出现，App Store 云下载由本轮发起 |
| Hotspot VPN | 2.0.2 | 新出现，安装前复查已存在，未覆盖 |
| GOFast VPN | 1.4.0 | 新出现，安装前复查已存在，未覆盖 |
| Jump VPN | 1.1.0 | 新出现，安装前复查已存在，未覆盖 |
| EASY VPN | 2.1.0 | 新出现，安装前复查已存在，未覆盖 |
| Surge | 5.19.0 | 新出现，安装前复查已存在，未覆盖 |
| 飞连 | 3.3.26 | 原有，保留 |
| Shadowrocket | 2.2.82 | 原有，保留 |
| Tools | 2.2.0 | 原有，保留 |

最终软件覆盖 9/9，版本、build、主程序和扩展 ID/类型匹配。没有启动这些 App
或启用隧道，未证明每款登录后能正常连接。

**不要误报实际动作：**本轮准备了前述 5 款的应用包，但它们在写入前已出现
在目标注册表，安装脚本拒绝覆盖，因此 TrollStore 安装写入次数为 0。无法
仅凭注册表确定它们是谁安装的。本轮只实际发起 Storm Sniffer 商店下载；
最终齐全是已回读事实，不等于本轮脚本亲自安装了全部 6 款。

### 8.2 已有 TrollStore App 的应用包迁移路线

这是为确实缺失的应用准备、但本轮未执行到写入的路线；此前迁移用过同类
模式，仍需每次重新核对来源、权限和安装结果。

1. 源 App 有 `_TrollStore` 标记才采用；官方商店安装来源优先 App Store。
2. 只读取 App bundle，打包为 `Payload/<App>.app`，保留软链接和可执行权限，
   不打包数据容器、App Group、节点、Keychain 或账号。
3. 检查 IPA CRC、主 Bundle ID、版本、架构、扩展和所需可执行文件，记录 SHA-256。
4. 上传到经过核对的真实系统暂存目录，回读 SHA-256。再次核对目标 App 注册
   表：已经存在就停止，**不加 force，不用旧快照决定覆盖**。
5. 调用现有 TrollStore helper，不重装 TrollStore，也不借此改注入策略。

```sh
# 以下在手机执行；路径变量必须来自现场 namespace 核验，不直接照抄。
sudo "$TROLLSTORE_HELPER" install "$IPA_REAL_SYSTEM_PATH"
```

已保留的 `scripts/migration/install-trollstore-manifest.py` 是历史清单驱动工具。
其中机型、路径、socket、staging 等必须重新核对；拒绝已安装 App 的保护不能
删掉。退出码 184 可能意味着已安装但次级二进制仍有加密限制，需要回读扩展
并单列风险，不能当成失败盲重装，更不能删扩展“修复”。

## 9. 最后怎么证明、怎么清理、怎么回滚

### 完成判据

- 包：installed 状态、版本/架构、依赖、Filter、链接和文件回读。
- 设置：目标符合恢复候选、清单外及不可迁移字段不变、API/磁盘一致、格式/权限正确。
- 界面：新 PID 后的新截图；不要把事件返回值当 UI 响应证明。
- 布局：App/Dock/文件夹内容语义符合候选，缺失 App 过滤、目标 extras 保留。
- App：主 ID、版本/build、主执行文件、扩展 ID/类型及其执行文件存在。
- 不变量：已取得基线的策略和无关设置不变；**没有取得基线就不能说已验证**。
  本轮目标 RootHide 策略未取得完整基线，只能说明未发出策略写入且新 Filter
  没有高敏 App，不能升级为全进程“零注入”证明。
- 崩溃：检查窗口内文件列表；无新增报告不等于长期零崩溃/零耗电。

### 清理与回滚

仅删除本轮上传的助手、补丁、下载 IPA/DEB 暂存文件，关闭本轮 SSH socket；
保留源导出、恢复清单、操作记录、安装日志和最终回读报告；已有历史备份不删除。不要按
通配符清理其他任务的 IPA/DEB，更不要删除最后可用备份或停止 App Store 下载。

```sh
ssh -S "$TARGET_SOCKET" -O exit "$TARGET_HOST"
```

失败时先回读目标，按已确认的源配置修正并验证；未另存目标旧状态时不承诺
回滚。若已有原始副本，可仅恢复对应配置；新增包在确认依赖与用户授权后
卸载，碰撞文件也只有存在旧副本时才能还原。**不能把旧 dpkg status
整份盖回去**，否则会丢其他并发安装状态；不要自动执行无范围回滚。

本次没有执行全量回滚。所有教程、工具和产物发布前必须扫描敏感信息；文档
和源码可提交，原始截图、连接、凭据、设备标识、第三方私有产物留在忽略目录。

## 10. 文档、源码和本次证据去哪找

| 文件/目录 | 用途 |
| --- | --- |
| `docs/iphone-completion-tutorial.md` | 本篇统一教程 |
| `docs/plugin-settings-alignment.md` | 分轮结果、范围变化和外观限制 |
| `docs/native-app-store-download.md` | 原生商店下载安全流程 |
| `scripts/tools/settings-key-client/` | 已保留的逐键客户端、白名单、构建 |
| `plugins/status-indicators/SISettingsStore.m` | 正式原子存储源码 |
| `scripts/migration/tweak-prefs.m` | 历史偏好/布局读取客户端 |
| `scripts/migration/controlcenter-settings.m` | 控制中心原生序列化 |
| `scripts/migration/crane-root-settings.m` | Crane 两个全局 UI 键 |
| `scripts/tools/home-ui-input/` | 主屏/控制中心输入源码及构建 |
| `scripts/migration/build-native-store-helpers.sh` | 商店输入/截图构建 |
| `app/safe-domain-probe/tools/ui-input/` | 原生输入与本机 OCR 源码 |
| `app/safe-domain-probe/tools/screen-observe/` | 只读截图/锁屏状态 |
| `scripts/migration/install-trollstore-manifest.py` | 历史缺失 App 清单安装工具 |

本次已保存证据（均在被忽略的目录，不是新一轮可直接重放的自动化入口）：

- `tmp/settings-align-20261118/final-report.json`：125 键原轮结果及范围缩减。
- `tmp/ui-complete-20261118/final-report.json`：补包、控制中心、布局与视觉边界。
- `tmp/ui-complete-20261118/package-plan.json`：包、哈希、路径与 Filter 审查。
- `tmp/vpn-apps-install-20261118/final-report.json`：9/9 回读及真实安装动作边界。

这些目录里的临时脚本带当轮连接和布局参数，不可直接套到别的手机，不作为
公开可维护工具。源码、构建和本篇流程保留；下一轮重新盘点和产生私有计划。

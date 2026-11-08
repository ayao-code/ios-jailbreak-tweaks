# 淘宝状态只读诊断助手

> 2026-11-08 仓库整理说明：原始截图、设备导出、历史测试包及详细日志已按用户要求清理。下文旧 `research/`、`evidence/` 路径仅描述当时记录，不代表文件仍在；保留正式源码、资源和必要交付包。此次整理未重新执行功能验收。

独立 TrollStore App，目标设备为用户授权的 iPhone 12 mini / iOS 16.3.1。
这是非 App Store 权限的诊断工具，不能作为普通沙盒或领券恢复的验证证据。

## 范围

- 仅查询 `VJGTV94XY8.com.taobao.taobao4iphone` 钥匙串组中 generic/internet password 的可访问数量，分别查询非同步和同步项目。
- `SecItemCopyMatching` 只返回临时持久引用用于计数；引用不展示、不保存、不上传。查询不请求 `kSecReturnData` 或账号、服务、密码等属性。失败和不可访问状态不等于记录不存在。
- 在真实 AppGroup 父目录中最多检查 512 个 UUID 容器的管理元数据，只对 `MCMMetadataIdentifier` 严格匹配 `group.com.taobao.taobao4iphone.extension` 的目录枚举名称。
- 目录枚举最多三层、150 个项目，不跟随符号链接、不读取 App 内容；输出名称屏蔽长数字和邮件地址。该屏蔽不是任意个人信息的通用检测器，导出前应自行审阅。
- 不加入目标 App Group，不调用可能创建共享容器的 membership API，不修改其生命周期。
- 没有删除、修改钥匙串、改设备标识、网络访问、注入、Hook、启动淘宝或请求提权功能。
- 报告仅写入本助手自己的 `Documents/readonly-report.json`。iOS 正常安装和查询可能产生系统日志；只读指目标业务数据不被修改。
- 使用精确钥匙串组和无沙盒权限；不申请 wildcard 钥匙串、root persona、platform 或私有 Keychain entitlement。TrollStore 是否保留权限、能否访问目标数据必须由实机结果确认。

## 构建及使用

运行 `bash app/taobao-state-inspector/build.sh`。无 Xcode iPhoneOS SDK 时使用现有 Theos iPhoneOS16.5.sdk，可通过 `IOS_SDK_PATH` 覆盖。

通过 TrollStore 安装生成的 IPA，打开“淘宝只读诊断”，点击“开始只读检查”。不要手动赋予更多权限或同时使用改机、清理工具。

报告可经“导出诊断报告”分享，也可通过设备已授权的 Documents 文件服务读取。仅生成数量和目录结构不能证明旧号码存储在哪个条目，更不能证明领券失败由此引起。

本阶段只读。任何后续删除操作都需要新的明确授权和可验证的目标；本 App 不包含清理入口。完成诊断后通过 TrollStore 卸载本助手，保留仓库源码。

## SSH 只读元数据工具

`bash app/taobao-state-inspector/tools/build-metadata.sh` 构建独立命令行工具，避免重复安装桌面助手。只适用于已越狱、已明确授权的目标设备，经 SSH 临时运行后应移除设备上的二进制。

SQLite 使用只读连接及只读事务，只对淘宝精确 access group 查询 `genp` / `inet` 的分类数量。服务名仅用于内存中的名称分类，不导出原始字段，不选择 `acct`、`data`、标签、密码或令牌，不调用删除和修改语句。

名称包含 device/UUID/UTDID 等归为身份相关、login/account 等归为登录相关，但命名启发式不能证明记录真实用途或删除安全。数据库读取权限不足、表结构不匹配或查询失败必须报告为未完成，不能推断没有残留。

该工具没有网络、清理、标识生成、App 注入或启动功能。SQLite 只读连接可能使用既有 WAL/SHM 协调读者，不能声称完全没有系统层副作用；不会复制数据库，不执行 checkpoint 或写入业务记录。

`tools/build-api-metadata.sh` 构建只读 Security API 工具，申请淘宝精确钥匙串组，不申请通配符。它只请求属性，绝不请求 `kSecReturnData`；属性可能包含账号元数据，但不输出或保存账号值。只输出服务/标签是否包含固定的 login/account/device 等词、同步状态及序号，以及下一段明确允许的登录服务名称。名称信号不能证明删除安全。

进一步定位时，仅允许输出含 login 且最多 96 字符、全部由 ASCII 字母/点/横线/下划线/空格组成的 service/label 名称，不输出任何 account 字段。非匹配名称不显示，不读取条目内容。该名称用于区分账号历史和有效认证数据，不能仅凭 login 词就删除。

剩余项目盘点可输出符合 com/org/group 命名空间且最长 128 字符、限定 ASCII 字符集的 service 名称；输出先屏蔽 16 字符及以上十六进制段、4 位及以上连续数字、24 字符及以上连续字母数字段。其余仅标记 `not_exported`。不显示 account、原始未知服务名或身份值。history/cache/risk/jail/security 等词仅为分类线索，不能证明检测标记或删除安全。

对于未导出的名称，仅输出 service/label 的类型、长度及 UUID/十六进制/命名空间等结构分类，以及 account 属性是否存在；不输出 account 值。结构无法辨认用途时必须保留，不能把 UUID 型服务名判作已废弃记录，也不能仅据记录存在推断检测标记。

对于 account 属性，仅在其是长度不超过 128 且完全由 ASCII 字母及点/横线/下划线/空格构成的字段名时，输出 login/history/device 等固定词的匹配信号，不输出原值、手机号、令牌或哈希。服务名中的 `iphone` 不是手机号线索。`com.alipay.alisecx.localstorage.` 后缀一律遮蔽，安全 SDK 命名和身份命名不等同于越狱检测结果。

现场 SQLite 查询证明专属组有 20 条 generic-password 记录、inet 表无匹配；svce 均为长度 20 的 BLOB，因此 SQL 文本分类不能判断用途。这不是原始服务名，也不是能据此删除的记录清单。访问受保护属性失败时不重启 securityd、不修改权限、不关闭数据保护、不直接修改数据库。

## 单次授权登录服务重置

独立 `tools/build-login-reset.sh` 工具不打包进原只读 App。它仅接受 `--delete-login-only`，通过 `SecItemDelete` 清除 generic-password 类中精确 group `VJGTV94XY8.com.taobao.taobao4iphone`、精确 service `com.taobao.login.service` 的非同步项目。

运行前需确认淘宝已卸载且用户明确要求清理其旧登录资料。删除可能清除该登录服务的认证资料，但不读取密码或令牌内容。工具要求现场总数为 20、目标数为 2，否则无删除退出；执行前后在内存中比较其余 18 条的持久引用和属性，不输出、不落盘任何账号字段。

不删除 UMID、未知条目、同步项或其他 access group，不修改 IDFV、设备标识、系统数据库或淘宝沙盒。无备份的删除不可撤销；验证失败即停止，不自动扩大范围。登录服务项的存在不证明其保存的就是用户看到的旧号码，也不证明删除会解除领券限制。

## 剩余记录盘点（2026-11-06）

精确登录服务重置后，Security API 再次只读确认 18 条非同步 generic-password，internet-password 查询为 `errSecItemNotFound`。

| 元数据类别 | 数量 | 处理 |
| --- | ---: | --- |
| `com.alipay.alisecx.localstorage.[REDACTED]` | 8 | 安全 SDK 命名；含 device、login/security 字段信号，未确认实际内容或删除安全，保留 |
| `com.autonavi.amap.idfv` | 1 | IDFV 相关，保留，不改标识 |
| UMID 名称信号 | 1 | UMID 相关，保留 |
| `com.amap.adiu.desencrypt` | 1 | ADIU 相关，保留 |
| `com.taobao.taobao4iphone` | 3 | 通用 App 服务，未确认用途，保留 |
| 其他名称不显示的项目 | 4 | 不透明命名及二进制 service，未确认用途，保留 |

以上仅是元数据分类，不证明淘宝实际采用这些标识、保存了特定检测结果，或领券异常由它们引起。`iphone` 包含 `phone` 的早期子串匹配已纠正，不能据此判断保存手机号。没有新确认的历史/缓存项目，本轮不增加删除。

## 追加授权的两类服务重置

用户接受重新认证和不可撤销的数据丢失风险后，单独授权删除上表的 8 条 alisecx 项及 3 条淘宝通用服务项，不包含其他 7 条身份相关或未知项目。它们不被描述为已确认的缓存或越狱检测标记。

`tools/build-service-reset.sh` 构建独立命令行工具。`--inspect` 仅做前置查询；`--delete-approved-services` 才执行删除。每次要求精确淘宝组内 18 条非同步 generic-password 中，目标数为 8 + 3、非目标 7 条且 alisecx 服务名只有一种，否则不删除。

alisecx 前缀仅用于识别此次已盘点的服务，实际 `SecItemDelete` 查询绑定现场完整 service 值、精确 class、group 和非同步条件，不使用模糊删除。删除后回读其余 7 条并在内存中比较属性和持久引用，不导出账户、密钥、令牌或安全 SDK 后缀；任何失败均停止，不自动扩展范围或重试。

执行前需确认淘宝仍未安装、目标仍为授权的 12 mini。工具不加入目标沙盒、不加载到淘宝进程、不修改系统文件或直接操作数据库；诊断和删除命令行二进制运行后从设备移除，保留源码。用户不要求备份，不能承诺安全状态可恢复或领券成功。

本次实机结果：预检 18 条，其中 alisecx 8 条、淘宝通用服务 3 条、其余 7 条；两次精确服务删除均返回 `errSecSuccess`，删除后 7 条，其余项目的属性及持久引用与删除前一致。独立只读查询再次确认目标服务没有匹配、总数仍为 7。设备临时工具已移除，Dopamine/TrollStore 核心元数据未变。没有重新安装淘宝或验证登录、领券，不能把删除结果写成业务已恢复。

## 14PM 系统卸载工具

`tools/build-maintenance.sh` 构建 `alibaba-maintenance`，仅允许 `iPhone15,3`。`--inventory` 返回已知阿里 App 的安装和容器管理元数据及可访问钥匙串数量，不读取记录内容。`--uninstall-approved <Bundle ID>` 仅接受源码中固定的 12 个阿里 App，要求普通安装路径、User 注册和没有嵌套 Crane 容器。

卸载通过 iOS 系统接口完成；源码没有手工沙盒、共享目录、钥匙串删除或身份更改。权限参考目标设备已安装 TrollStore 官方 helper，MobileInstallation SPI 只包含卸载。权限不足导致返回 false 时立即停止，不退回手工删容器。12 mini 对照不运行此工具，保持只读。

2026-11-07 实际卸载和元数据回读记录见 `research/alibaba-cleanup-2026-11-07.md`；阿里 App 卸载成功不等于持久身份清零或业务已恢复。

## 14PM 阿里本地钥匙串重置

`tools/build-alibaba-keychain-reset.sh` 生成仅面向 14PM 的单次命令行工具，不打包进桌面助手。`--inspect` 查询固定 12 个已核实 access group 的非同步/同步密码类数量；`--erase-local-approved-groups` 才执行用户授权的本地重置。

强制前提为目标 App 和已知组消费者已卸载、全部 query 成功、逐组本地数量等于现场清单（合计 200）且点淘同步项为 3、其他组同步项为 0。只对精确 group/class/非同步条件调用 SecItemDelete；操作前再核对本地引用一致性，操作后验证本地匹配为零且同步引用未变。任意失败立即停止，不自动扩大权限、范围或重试。

不查询秘密数据或属性，不读取账户、密码、令牌、标识值；不同步删除，不删除证书或私钥，不直接写数据库，不改变硬件标识或生成假身份。不保证其他 App 业务侧无间接影响、不保证账号或支付恢复。现场删除及独立回读见清理报告，点淘 3 条同步记录仍保留。

### 点淘同步项的单独授权入口

用户后续明确接受跨设备同步删除影响，新增 `--erase-diantao-sync-only`，不改变既有本地重置入口。该入口只对 `MYV5GKGP85.com.taobao.live`、generic-password、synchronizable=true 调用一次 Security 删除 API，不读取秘密值、不修改设备标识。

强制前提：14PM 型号、目标和组消费者没有安装、12 个已核实组的两类/同步状态共 48 个查询组合均可读，只有目标组合恰好 3 条，其他组合均为零。删除前再次比对目标引用和消费者，删除后比对其余查询组合引用未变。临时工具执行后移除，不访问对照机；设备零匹配不能证明 iCloud 传播完成或其他设备已删除。

追加执行结果：点淘 3 条同步记录删除返回 0，本机验证 3 → 0，其余 47 个查询组合引用未变；独立进程回读全部 48 组合均无匹配。此结果覆盖此前保留同步记录的状态，iCloud 传播未观察。累计删除 203 条已核实密码类记录，不声称整个系统钥匙串或所有业务状态清零。

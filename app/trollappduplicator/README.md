# 分身工坊（CloneStudio）

> 2026-11-08 仓库整理说明：原始截图、设备导出、历史测试包及详细日志已按用户要求清理。下文旧 `research/`、`evidence/` 路径仅描述当时记录，不代表文件仍在；保留正式源码、资源和必要交付包。此次整理未重新执行功能验收。

在公开 MIT 许可 TrollAppDuplicator 源码上的二次开发。复用应用列表、文件浏览与
SSZipArchive，重写副本生成管线。**交付为独立 App，不是越狱插件**。

当前版本 `0.1.0-preview4`，Bundle ID `com.ayao.clonestudio`，arm64，最低 iOS 15。
与原 TrollAppDuplicator 是不同工具身份，可以共存，不会自动覆盖或卸载旧工具。
源码保留在本目录，原作者许可见 LICENSE，上游来源见 source-provenance.json。

另有用户要求的“上游最小改动＋IPA导入＋回调开关”独立实验构建，见
UPSTREAM_EXPERIMENT.md。upstream3每次新建不同ID，可选共享组迁移；仍保留原签名应用身份，
与本页默认强隔离版不同，不混称完整隔离或安全版。

通用双开关方案见GENERIC_TWO_SWITCH_DESIGN.md，当前仅设计，未实现或安装；
共享组能力仍是大麦专用实验，不能按该文档误认为当前工具已支持任意App隔离。

## 已实现

- 从文件选择器导入已解密 IPA/tipa，也可选择已安装 App 的代码包。
- 首页蓝色“主程序未加密”可选；红色“主程序加密/无法读取”仅弹提示，不进入生成。
  选取已安装 App 时重新读取主程序状态，完整包检查仍在引擎中保留。删除首页底部说明。
- 注册IPA/tipa的系统“用分身工坊打开/拷贝到分身工坊”入口。冷/热启动通过
  AppDelegate openURL接收，不是分享扩展。提供方若把文件识别成通用数据可能不显示入口，
  此时使用工具内“+”导入；未声称所有来源的共享面板都支持。
- 外部输入经security scope和NSFileCoordinator读取后复制到工具输出目录的隐藏`.imports/<UUID>`，
  自有Inbox中的本地副本直接复制。协调错误与复制错误分开，明确检查复制成功、大小、
  源文件变化及副本可读性；失败不传递虚假的文件路径。选择器关闭后恢复待导入队列。
- 工具本身补充`com.apple.private.security.storage.AppDataContainers`。TrollStore官方说明指出
  `platform-application`与`no-sandbox`组合可能需要它才能访问自己的数据容器；preview3在
  真机上确实被拒绝读取Inbox内容及创建缓存目录。该权限比单个文件授权范围大，代码只处理
  用户主动选择的IPA，不扫描第三方账号容器，生成的分身主程序和扩展都不继承此权限。
  不原地改源文件；最多8个待处理输入，繁忙时排队，超过上限明确提示。缓存目录仅在
  取消或生成结束时清理自己的UUID暂存；异常进程终止可能留下缓存，未自动扫描删除。
- 不提供解密、不调用目标 App、不附加进程、不自动安装或修改 RootHide 配置。
- 设置页“保护原版（隔离共享）”默认开启，关闭要确认共享风险。
- 生成前再次展示模式和功能限制；生成期间不允许另一个并发任务。
- 每个源 App 每种模式一个持久副本 Bundle ID，重复生成沿用；不同模式用不同ID，
  避免模式变更默默改变同一副本的数据权限。第一版暂不提供同模式多实例管理。
- 两种模式始终使用独立应用、容器和精确钥匙串身份，不给副本平台/无沙盒/调试权限。
- 在工作副本中调用现有 TrollStore 的 ldid，回读每个 Mach-O 的签名权限。
- 校验全包 Mach-O、加密标记、arm64、系统要求、已知越狱依赖及注入标记；错误拒绝生成。
- 校验签名前后指令 section 字节不变，以及非目标资源不变。
- ZIP 预检路径、重复/大小写与Unicode规范化冲突、CRC、特殊文件、展开上限。
- 导出候选 IPA 和 JSON 检查报告，文件页可分享到系统文件/安装工具。
- 删除仅针对工具输出文件，需要确认，不卸载任何 App、不清共享组或账号数据。

## 保护开关

| 模式 | 回调/文档注册 | App Groups/关联域/推送 | 内嵌扩展 | 身份/钥匙串 |
|---|---|---|---|---|
| 开启（默认） | 移除副本注册 | 不授予原版能力 | 移除全部内嵌App/扩展，生成前说明并确认 | 独立 |
| 关闭（兼容模式） | 保留 | 保留有限的上游能力字段，不复制任意私有权限 | 保留appex并改独立ID；Watch/内嵌App暂拒绝 | 仍独立 |

开关只影响以后生成的包，不改已安装App。兼容模式不保证保留能力能实际工作，
也**不保证不干扰原版**。保护模式也只降低注册与共享授权冲突，不认证无干扰。

独立签名使用 `AYAOCLONE.<cloneBundleID>` 作为本地 TrollStore 应用/钥匙串命名空间。
这不是苹果开发者签名资格或服务端注册，也不是隐藏改包行为。TrollStore能否实际接受、
安装后权限是否保留、App是否允许身份变化，需要实机核对。副本不继承管理工具权限。

## 使用流程

1. 用 TrollStore 安装本工具。工具依赖已安装TrollStore的ldid。
2. 点齿轮选择保护模式；默认保持开启。
3. 点“+”选择可信、可授权使用的已解密IPA，填写副本名称并确认功能限制。
4. 得到 IPA 和报告。先审阅报告，再自行交给 TrollStore 安装；不能因为生成成功
   就认为登录、支付、通知或原版不受影响都通过。
5. 安装后先回读独立身份、普通容器、实际App Group/回调注册，再确认原版正常。

也可以在支持IPA类型的文件来源点共享，选择“用分身工坊打开/拷贝到分身工坊”。
收到文件后先复制到工具自己的临时目录，显示原有生成确认，不自动制作或安装。

输出目录 `/var/mobile/Documents/CloneStudio`。在 RootHide SSH 下可能需要不同路径视图，
不能盲目复制到同名字路径。本工具不自动查改系统注册或RootHide白名单。

## 必须知道的限制

- 只有已解密IPA/已安装代码包可处理，不读取账号数据；已安装包不是原子快照，
  建议优先用不可变IPA，并在制作时不要更新源App。
- 没有原作者源码时，撤销App Group/钥匙串权限可能导致副本无法登录或启动；
  代码写死组名不会被自动改写，不插入Hook来绕过。
- 移除回调不会阻止App主动跳到外部授权；外部登录/支付仍可能不兼容，不能使用
  元数据编辑假装修改了按钮和服务端登记。没有强制阻断出站的运行时逻辑。
- 第一版保护模式移除全部内嵌App/扩展，功能明确降级；不是完整保留扩展的方案。
  不能称加密扩展被移除为“解密成功”。
- App Group/Universal Links、APNs及Apple登录在新身份下不一定支持；保留声明不等于合法资格。
- 仅拒绝已知注入标记/加载依赖，不提供通用恶意代码检测或所有非系统依赖解析；
  不能把这个检查当安全认证。不解决服务端设备识别或账号限制。
- ZIP/目录第一版上限2 GiB展开、5万项，拒绝符号链接/特殊文件；工作空间要求
  约展开大小3倍加256 MiB。框架可能有合法符号链接，此类包当前不支持，不能盲改链接。
- 第一版仅支持含普通 arm64 slice 的App，纯arm64e/x86包拒绝；不是全设备兼容。
- 原装App不会被写入，但安装副本后的系统路由和服务行为仍需验证。
- 阿里/蚂蚁、京东、银行/支付/证券等高敏App不进行注入、Hook、调试附加、插件沙盒写入
  或检测绕过。本轮未制作、安装、登录或启动大麦分身。
- 无daemon、不保活、不轮询目标App；工作I/O采用32/64KiB缓冲，但文件名/报告仍占内存，
  压缩库和签名工具峰值未测量，不承诺零内存/零启动影响。

## 构建

```sh
THEOS=$HOME/theos make -C app/trollappduplicator stage FINALPACKAGE=1
```

产物 `build/CloneStudio-0.1.0-preview4.tipa`，工具打包器仅打包工具自身。
已安装版本的交付包移入 `packages/`，包括 `TrollAppDuplicator-1.2.1-local1.tipa`、普通 preview4 和 upstream3；旧版工具属于此前版本，
不代表本轮重新安装了旧版工具。CloneStudio与原工具使用不同Bundle ID。

## 本轮验证范围

- preview4用已签名工具的`--import-check <IPA路径>`在手机上运行同一导入函数，复现preview3
  的NSCocoaErrorDomain 513 / NSPOSIXErrorDomain 1；元数据可读不代表文件内容可读。
- 补齐工具数据容器权限后，同一Inbox中的111998665字节大麦IPA读取、复制成功，源文件
  前后与副本SHA256全部为`de197dfb72542fc609c384f6e336e33bfa8f9d8b2075ae36ccc67fc5aa6181e4`。
  暂存副本已清理，原IPA保留；证据见evidence/import-preview4/probe-final.stdout.jsonl。
- preview4已安装并回读版本、数据容器和新增工具权限；备份见evidence/import-preview4/preview3-tool.tar
  及probe-metadata.json中的手机路径。14项导入/状态和13项生成检查通过，包含分身不继承
  AppDataContainers的断言。真实“+”选择器/共享面板的界面点击仍未验证。
- 一次性CLI诊断仅由显式参数触发，无常驻、轮询、自动解密或第三方进程附加。
  诊断源码在tests/device_import_probe.m；正常启动仍走UIApplicationMain。

### 历史验证记录

- preview3复现并修正：原导入器对不存在的IPA返回成功与不存在的副本路径；新版明确失败。
- preview3完成14项导入/状态检查及13项生成管线检查，见evidence/preview3-import-results.json
  与evidence/preview3-host-results.json。界面颜色/入口属于静态检查，不冒充真机点击验证。
- 在Mac对实际大麦IPA（111998665 bytes）运行同一导入实现，复制成功，源/副本SHA256一致，
  见evidence/import-fix-preview3/real-damai-import-host.json。未执行大麦代码、未安装分身。
- 真机已确认此前分享文件存在于工具自身Documents/Inbox；未取得旧版实际复制失败原因。
  新版真实iOS分享UI是否恢复仍需实机操作验证，不能用Mac复制检查代替。
- preview3已更新至同一工具身份，安装版本、数据容器及代码指令与构建一致均已回读。
  前版已在Mac和手机备份，见evidence/installation-preview3/；没有更新第三方App或RootHide配置。

- iOS arm64编译与工具IPA打包完成，ZIP CRC/身份和依赖已检查。
- 在Mac编译同一个AppDuplicator/ClonePolicy/MachOInspector和ZIP实现，使用自建测试App包，
  不是对第三方App执行代码。host条件只替换输出目录、签名器发现、系统版本与偏好suite，
  不替换实际签名/改包算法。
- 13项本地夹具检查：两种模式、重复身份复用、输入不变、路径越界、大小写冲突、
  符号链接、加密、损坏Mach-O、过高plist/二进制系统要求及注入标记拒绝、签名指令变化拒绝。
- 结果见 evidence/preview1-host-results.json，构建日志见 evidence/preview1-build.log。
- preview2另外完成5项Mac检查：IPA/tipa输入复制、非IPA拒绝、原文件不变、主队列完成、
  文件类型声明和首页文字检查（结果中合并为5个记录）。见evidence/preview2-import-results.json。
- preview1工具已安装，preview2于2026-11-08 18:50更新到同一工具身份，版本和数据容器
  已回读确认；未自动启动或制作大麦分身。更新记录见evidence/installation-preview2/。
- 未验证：iOS真实首页/共享面板/冷启动导入UI、TrollStore内部ldid的实际调用、生成包在
  手机的安装/权限/容器行为、目标App登录/支付/推送和原版无干扰。预览版不标正式可用。

本轮未提交、未推送；只更新工具本身，不改RootHide配置或第三方App。

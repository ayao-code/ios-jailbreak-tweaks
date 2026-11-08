# SafeDomainProbe：本机隔离验证 App

> 2026-11-08 仓库整理说明：原始截图、设备导出、历史测试包及详细日志已按用户要求清理。下文旧 `research/`、`evidence/` 路径仅描述当时记录，不代表文件仍在；保留正式源码、资源和必要交付包。此次整理未重新执行功能验收。

这是“越狱宿主上的受保护运行域”项目的验证载体，不是已经实现的隔离系统，也不是越狱检测绕过插件。

## 约束

- 最终目标仍是同一台手机保持越狱、阿里系运行于真正受保护的环境；不能把本 App 正常打开或没有已知注入标记称为目标完成。
- 首先在 12 mini 验证，14PM 不修改；RootHide 和普通 Dopamine 必须分别确认版本与启动链。
- 不 Hook、注入、附加调试器到高敏 App，不修改其安装包、沙盒、账号、钥匙串或 App Group。
- App 只执行自身诊断、固定路径的 `stat/access/fopen`、三个固定 URL Scheme 可见性、固定越狱进程名命中、当前进程环境中 `MobileSubstrate`/`mobilesubstrate` 两个固定字符串的布尔命中、对自身 Documents 临时文件的 `PROT_WRITE|PROT_EXEC` 映射检查，以及对 `127.0.0.1` 固定四端口的无载荷 TCP 连接检查；不记录环境变量键值，不扫描其他 App，不连接外部网络，没有后台轮询。
- 唯一写入测试是在 `/private/jailbreak.txt` 使用 `O_EXCL` 尝试创建空文件；只有本次确实创建成功才立即关闭、删除并回读清理结果，既有同名文件绝不覆盖或删除。
- 可写可执行映射测试只在本 App 自身 Documents 以 `O_EXCL` 创建固定临时文件，写入 10 字节后尝试与阿里安全 SDK 相同的 `mmap(PROT_WRITE|PROT_EXEC, MAP_SHARED)`，随后解除映射、关闭、删除并回读；既有文件绝不覆盖或删除。
- `sysctl(KERN_PROC_ALL)` 只输出固定白名单中的越狱进程名命中，不保存 PID、参数、完整进程名或完整进程列表。
- 分享扩展不引用 `UIApplication`，Scheme 检查在扩展中明确记为不可用。
- 主程序和分享扩展各写自身 Documents 下的 JSON 报告；扩展不读取传入的分享内容，没有共享容器权限。
- 源码、构建脚本和资源全部保留在本目录；不替换越狱核心组件。

## 收集与结论边界

| 观察 | 可说明 | 不可说明 |
|---|---|---|
| 自身 dyld 镜像 | 当次报告包含的已加载库及部分已知标记 | 所有 Hook 不存在、库未被篡改 |
| 固定环境变量是否存在及两个固定内容标记 | 当次环境中的已知键及 `MobileSubstrate`/`mobilesubstrate` 是否命中 | 原始环境变量内容、其他进程或系统服务纯净 |
| 自身签名标志和有限 entitlement | 当次进程的可读取状态 | Apple 信任链未被越狱宿主影响 |
| 固定路径 `stat/access/fopen` | 三种常见文件 API 对固定目标的结果 | 拒绝和不存在等价、所有越狱资源不可见 |
| 固定 URL Scheme | `cydia/sileo/zbra` 是否可由主 App 查询到 | 对应 App 一定存在或系统完全无越狱痕迹 |
| 受控空文件写入 | 当前进程能否在固定系统路径独占创建空文件及清理结果 | 任意系统路径均可写、其他 App 权限相同 |
| 固定进程标记 | `KERN_PROC_ALL` 返回中是否命中预定义名称 | 未命中即无越狱、完整进程列表被隐藏 |
| 主程序及扩展分别报告 | 两种进程路径的分别观察 | 主程序通过自动代表扩展通过 |

所有报告始终将 `ordinary_ios_sandbox`、`isolated_filesystem_and_services` 和 `clean_ios_environment` 标为 `not_proven`。后续独立验证不能靠修改这三个字段制造完成证据。

## 构建

```sh
bash scripts/build.sh host
build/probe-host > build/host-report.json
bash scripts/build.sh ios
bash scripts/verify.sh
```

Host 版本验证 Objective-C 收集与 JSON 序列化路径，不调用报告写盘函数，也不是 iPhone 实机证据。

`verify.sh` 重建两种目标并验证 JSON 数据类型、已知环境键与内容标记的正反例、环境变量键值不泄漏、三种路径操作（包括 `/var/lib/cydia/` 和 `/User/Applications/`）、`stat` 原函数库来源、可写可执行映射的主机禁运行契约、固定 Scheme、进程名白名单、主程序与扩展包结构、扩展无 `UIApplication` 引用及不虚构隔离成功。结果在 `build/verification-summary.json`，该结果只代表 Mac 侧验证。

`SSH_CONTROL_SOCKET=<已授权且存活的复用会话> bash scripts/audit-mini.sh` 先验证目标型号，再只读流式取得插件 Filter。使用 Foundation 解析 XML、binary 和 OpenStep 格式，结果只写 Mac 的 `build/mini-filter-audit.json`，不修改设备。无法解析项导致审计非零退出，不把未知项当安全。会话指针不写报告，原始 Filter 暂存结束后清除。

用户授权在 14PM 调查后，可执行 `SSH_CONTROL_SOCKET=<已授权的14PM复用会话> bash scripts/audit-14pm.sh`。工具先要求型号 `iPhone15,3`，只读当前 Choicy 策略、Taobao 主程序/扩展 Info.plist、插件 Filter 和 launchd 外部进程状态；Crane 只记录目标配置形状及布尔设置，不记录容器名、账号或容器内容。结果在 Mac 的 `build/14pm-baseline.json`。对 Choicy、Crane 配置及 systemhook 比较前后哈希/内容，不执行配置修改或 App 重启。非普通文件 Filter 单独列出，不跟随未知 symlink，也不当作没有注入。

`SSH_CONTROL_SOCKET=<已授权的14PM复用会话> python3 scripts/inspect-crane-default-safety-14pm.py` 只读 MCM 元数据和目标默认数据根/三个非默认容器的分配容量，并核对已有配置双端备份、共享服务 PID 及配置前后差异。设备不写入、不启动 App，不读取账号或 Keychain；仅向 Mac 的 `build/14pm-container-storage-inventory.json` 写脱敏报告。配置或所选 PID 在盘点时改变就非零退出，不回滚非目标变化；容量/目录存在不算数据备份。默认容器的保护和官方切换副作用见 `research/safe-domain-2026-10-25/CRANE_DEFAULT_SAFETY.md`。

用户改用大麦后，`scripts/disable-choicy-damai-14pm.py` 只通过官方设置界面关闭大麦自定义配置或开启盘点扩展禁注入；不手写正式plist，不切Crane容器。`SSH_CONTROL_SOCKET=<已授权的14PM复用会话> python3 scripts/observe-damai-launch-14pm.py --cold-start` 只终止已确认的大麦目标PID并正常启动，最多三个离散截图、只读前台、配置及服务PID观察，不向大麦触控，不登录/购票/支付。没有上述参数仅请求正常启动，不保证新进程。工具遇未知/非目标变化退出；配置备份不算数据备份，Widget未验证。实际结果与完整边界见 `research/safe-domain-2026-10-25/DAMAI_TEST.md`。

iOS 构建使用 Xcode 的 iPhoneOS SDK，或 `IOS_SDK_PATH` 指定 SDK；没有 Xcode 时可使用本机 Theos SDK。产物 `build/SafeDomainProbe-0.1.5-unsigned.ipa` 未配置 Apple 开发签名和 provisioning profile。可经 TrollStore 临时安装来诊断 RootHide 下的文件、端口、Scheme、进程与可写可执行映射行为，但报告固定标记为 `non_app_store_diagnostic_only`，**不得作为有效普通 App Store 沙盒对照或“阿里检测已解决”的证据**。

实机安装前需有效的普通 App 签名及主程序、扩展相应的 provisioning profile；核对最终 entitlement，并记录实际安装来源。开发签名允许调试不等于 App Store 签名基线，签名差异必须在实机结果中保留。

## 顺序与停止条件

1. 当前 12 mini 身份、越狱、配置、插件范围和系统运行基线只读盘点。
2. Mac 构建主程序和扩展，Host 执行报告生成；检查已知标记能被报告而不是被吞掉。
3. 安装本测试 App 前确认普通签名路径；先观察现有策略，不直接改 RootHide plist 权限或格式。
4. 使用官方配置入口仅对本测试 App 比较策略前后；配置先双端备份，保留 XML、属主、权限和非目标键。
5. 如需写入配置、启停组件、重启桌面或设备，不自动扩大授权；新增崩溃或非目标变化立即停止。
6. 主程序和扩展、冷启动、更新、异常配置及共享服务穿透未完成验证时，不对阿里系宣称隔离完成。

本 App 不是强隔离原语。独立文件系统视图、服务边界及对同等内核权限代码的抗绕过能力，仍须有独立实现和证据；如果必须修改内核或共享服务才能实现，不在日常手机上直接尝试。

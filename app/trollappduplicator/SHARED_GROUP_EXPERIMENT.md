# 共享组单项离线实验

本文件记录最初离线候选：当时不安装、不更新工具、不操作账号，也不处理通知故障。
后续upstream2已移植原生生成实现并更新工具，仅工具更新，不安装大麦；见UPSTREAM_EXPERIMENT.md。
以用户已安装并报告能登录的callbacks-off IPA为基线，不采用强隔离版重新生成。

## 实际改动

- 分身ID不变：`cn.damai.iphone.00000000-0000-0000-0000-000000000000`。
- 旧组：`group.cn.damai.damaiApp`；新组：`group.cn.damai.2ce0e1bd`。
- `group.cn.damai.damaiAppOS`字符串别名同步为`group.cn.damai.2ce0e1bdOS`。
- 新组名根据分身ID确定，保持23字节等长，重复运行不随机换组。
- 主程序与3个扩展共7处已定位的C字符串修改，位置均在非指令的`__cstring`且不在加密区。
- 主程序、通知扩展和小组件已有的application-groups权限同步替换；其余权限原样保留。
- App Intents本来没有application-groups权限，只改已有字符串，不新增该权限。
- 4个目标Mach-O由本机ldid重签并回读。不是完全不重签的上游模式，不声称Apple官方签名有效。
- 除4个目标程序外，1,139个文件字节原样保留，包含主Info.plist、回调配置和扩展配置。

## 明确不变

应用ID、名称、签名application-identifier、Team标识、钥匙串相关权限、推送与关联域声明、
回调注册状态、扩展ID、扩展数量、加密命令cryptid及其范围全部保持基线。
不插入dylib或Hook，不读取运行中进程，不解密扩展，不改RootHide，不复制任何旧共享数据或token。

## 检查与限制

- 主程序及3个扩展全部section布局、非目标section内容与预定修改一致。
- 所有指令section字节不变；所有crypt范围字节不变，两个原本加密的扩展仍加密。
- 重签后逐key核对entitlements，只有既有application-groups的目标值改变。
- ZIP路径/大小/类型/重复检查、原输入SHA256不变、输出CRC与逐文件字节核对通过。
- 独立C Mach-O检查器与负向夹具共14项检查通过，覆盖加密区/指令区/未知后缀/非字符串起点拒绝。
- 证据见`evidence/shared-group-experiment1/group-migration-report.json`及`verification.json`。
- 完整Flux SDT因缺少flux-sdt.yaml未初始化；这里的离线检查不代表完整GUI/登录/通知验收。

静态扫描只证明已经找到的常量迁移，不能证明动态构造组名没有遗漏；这个候选不能叫完整隔离。
App Intents原本无共享组权限，本轮不修补这个独立问题。两个加密扩展及最低iOS16.6问题仍在。
现有签名资源/embedded.mobileprovision按基线保留，离线重签目标程序后它们不是完整Apple签名，
TrollStore安装时仍可能重建签名或改权限，需要实际回读；仅打包CRC通过不证明安装可用。

新组首次使用需要系统接受并初始化。未预填utdid、推送token或用户ID，不能伪造身份参数。
共享组变化不会修复APNs资格、服务端账号绑定、原版钥匙串身份重叠或外部登录回调。
不能从新目录推断消息通知独立。未测试登录、支付、通知、启动性能或官方异常检测。

## 复现

```sh
python3 app/trollappduplicator/scripts/migrate-shared-group.py \
  --input research/damai-upstream-installed-audit-20261108-200718/input/cn.damai.iphone.00000000-0000-0000-0000-000000000000-callbacks-off-00000000-0000-0000-0000-000000000000.ipa \
  --output-dir /absolute/new-output-directory
python3 app/trollappduplicator/tests/verify-shared-group.py \
  --candidate-dir /absolute/new-output-directory
```

输出目录必须不存在，避免覆盖已有候选。原IPA不会改写。新脚本仅支持本次大麦已有分身、
thin arm64、等长__cstring组名修改，不是通用分身/共享组修改器。
upstream2的原生实现已接入独立开关，不在手机执行此Python脚本。

候选为`evidence/shared-group-experiment1/Damai-shared-group-experiment.ipa`，SHA256：
`c3d2a56377659ec33871988dc85a6e405e079defdbd06993c8b2b7f459f53c24`。

同ID实验候选会更新现有分身，不是另装第三份。下一步如用户确认安装，先保留能用的IPA，
通过正式安装路径更新，不先卸载、不清共享目录。安装后先只读核对新组、容器和非目标权限，
再由用户确认验证码登录，失败停止，不同时修改钥匙串/通知/回调归因。

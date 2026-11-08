# 上游最小改动实验版

> 2026-11-08 仓库整理说明：原始截图、设备导出、历史测试包及详细日志已按用户要求清理。下文旧 `research/`、`evidence/` 路径仅描述当时记录，不代表文件仍在；保留正式源码、资源和必要交付包。此次整理未重新执行功能验收。

后续共享组单项候选说明见SHARED_GROUP_EXPERIMENT.md。upstream2已把该能力移植到
手机端工具中，作为独立的“共享组隔离（实验）”开关；不是通用共享组适配器。

当前实验版本：`0.1.0-upstream3`，工具ID：`com.ayao.clonestudio.upstream`。
沿用本目录保存的MIT上游源码背景，复用已修好的IPA导入与ZIP实现。
共用同一套源码，通过`CLONE_UPSTREAM_EXPERIMENT`编译选项选择行为；不复制整个项目。
现有CloneStudio工具及隔离管线保留，不覆盖手机上现有工具或大麦分身。

## 本版范围

- 从“+”或系统文件打开入口导入IPA/tipa，保留此前AppDataContainers工具权限修复。
- 只改主Info.plist的CFBundleIdentifier和CFBundleDisplayName。
- “避免回调冲突”默认开启：仅删除主Info.plist的CFBundleURLTypes。
- 关闭开关：保留原回调注册，关闭前确认冲突风险。不注册随机新回调。
- “共享组隔离（实验）”默认开启：仅接受原始大麦解密IPA，修改共享组常量与既有权限并重签；
  不改应用/Team/钥匙串身份、不删扩展、不改关联域、后台声明或指令/加密字节。
  关闭时恢复upstream1行为，不重签、不迁移共享组。
- 只输出IPA，不额外向用户输出JSON。源文件、已安装应用及RootHide配置不修改。
- 每次“新建分身”生成新的完整UUID应用ID，不读取或覆盖旧分身ID映射。
  同输入、同名称再次生成也创建新身份；开启共享组迁移时组名随新ID派生。
  重复安装同一份已生成IPA依然是更新该IPA对应的分身，不是再次新建。
- 工具本身和普通版是独立ID，输出目录为`/var/mobile/Documents/CloneStudioUpstream`。

分身ID和文件名均有UUID，避免新建时复用已有身份和输出文件。旧映射保留但不再用于新建。
原签名application-identifier及扩展ID仍按前述兼容策略保留，不能把新ID误称完整账号隔离。

## 重要限制

这不是独立账号/数据隔离保证。保留原签名身份可能导致普通容器复用，保留App Group和
钥匙串访问组可能访问同一份共享数据。不同图标、Bundle ID或包目录不证明数据隔离。
巨魔安装后必须只读核对实际注册、数据容器和权限；不能仅凭文件夹数量判断。

关闭回调注册不阻止出站授权请求，也不修复验证码或网络请求失败；保留回调可能抢原版跳转。
没有登录、支付或官方检测结果。本版不伪装官方身份，不绕过服务端校验，不注入或Hook高敏App。

只检查主程序未加密，不删除或解密内嵌扩展。真实大麦输入包含3个扩展，本版全部保留；
其中未解密/高最低系统要求的扩展可能影响安装或使用，这正是上游行为的限制。
原签名及签名资源原样保留，但主Info.plist被修改，输出不是有效官方签名包；交给TrollStore
安装时签名及容器行为可能再次变化。没有声称全包可安装。

## 构建与本地对照

```sh
THEOS=$HOME/theos make -C app/trollappduplicator stage FINALPACKAGE=1 \
  CLONE_VARIANT=upstream _THEOS_RELATIVE_DATA_DIR=.theos-upstream
sh app/trollappduplicator/tests/build-host.sh /tmp/clonestudio-host-build
python3 app/trollappduplicator/tests/verify-upstream.py \
  --source-ipa research/damai-ipa-recompare-20261108-174236/input/trolldecrypt.ipa \
  --output-dir app/trollappduplicator/evidence/upstream1-candidates \
  --report app/trollappduplicator/evidence/upstream1-comparison.json
```

产物：`build/CloneStudio-Upstream-0.1.0-upstream3.tipa`。普通版构建不传这两个实验参数。
实验构建使用独立.theos-upstream目录和latest-upstream-package.json，不覆盖普通版产物。

## 本轮证据

- upstream3修复“新建误覆盖”：每次生成新应用ID，忽略原有更新映射；同输入/同名两次
  生成回读不同ID和不同派生共享组，源IPA不变。见evidence/upstream3-new-identity-regression.json。
- 工具更新不卸载或重签已有大麦分身，不清账号/共享数据。共享组、回调与导入能力保留。
- 已安装upstream3，手机端同输入/同名两次生成新ID和不同组名，旧GUI偏好和大麦注册、
  RootHide配置不变，自检输出清理。证据见evidence/installation-upstream3-20261108-210324/readback.json。
  未安装测试分身，不把生成检查等同于完整共存、通知或登录验证。
- 现有应用签名身份/扩展ID兼容与通知问题没有在本次身份修复中改动，仍未保证完整隔离。

### upstream2历史记录

- upstream2已更新手机上同一工具ID，旧工具包在Mac和手机均备份，未更新大麦本体/分身。
- Native GroupMigration.c采用固定缓冲流式预检，不把整个主程序加载进内存；只支持thin arm64。
  已定位组名仅可在__cstring起点且不与指令/加密区重叠，重签后核对section、crypt、权限。
- Host调用同一AppDuplicator/GroupMigration生成同ID候选，所有包内文件字节与Python脚本候选一致。
  7项Native负向/边界检查及14项导入、13项既有隔离回归通过；不是完整SDT或GUI验收。
- 真机调用已安装工具--import-check及--group-generation-check均成功，源IPA不变，自检IPA清理。
  自检使用skipIdentityPersistence，不保存生成身份。RootHide SSH与GUI有不同全局偏好视图，
  CLI自检不能代替GUI偏好；实际GUI分身ID仍为cn.damai.iphone.00000000-0000-0000-0000-000000000000。
- 安装记录：evidence/installation-upstream2-20261108-205522/readback.json；真实GUI点击/用户生成包/登录/通知均未验证。

### upstream1历史记录

- 已完成iOS arm64编译、ZIP CRC及工具签名身份检查。
- 对真实大麦输入生成回调注册移除/保留两份候选，使用同一个实验分身ID。
  两份候选都只改主Info.plist，除该文件外所有文件字节相同，扩展/二进制/签名保留。
- 夹具确认两模式差异、身份沿用、原包不变、缺失/损坏IPA及主程序加密拒绝。
- 既有导入14项、隔离管线13项本地回归检查通过。完整Flux SDT因缺少flux-sdt.yaml
  无法初始化，未完成该流水线；本地检查不冒充完整SDT或GUI/登录验收。
- 初始交付仅构建，用户随后确认安装工具。2026-11-08 20:01已安装实验工具，版本及
  代码指令、签名身份、独立工具容器均回读确认；旧工具、原版大麦和现有分身保留。
  回调开关偏好未设置时默认开启，未手写手机偏好。
- 实验工具在手机上读取并复制实际111998665字节大麦IPA成功，源前后和副本SHA256一致，
  测试副本已清理。真实文件选择器UI未验证。
- 安装证据见evidence/installation-upstream1-20261108-200106/readback.json，旧工具包在
  Mac及手机均有备份；实际注册列表仅新增实验工具，原版/分身注册与RootHide配置无语义变化。
- 未安装任一对照分身；未执行目标App代码、登录、支付、账号访问或改白名单。

upstream3创建新身份以支持共存，但安装后仍需回读普通容器、App Group、扩展注册及权限。
不要直接卸载旧实验分身做对照，卸载和共享状态仍有风险。发现共享应停止账号测试，
不自动恢复、删除或清理数据。旧upstream1/2生成的同ID候选仍会更新旧分身，不使用旧包当新建。

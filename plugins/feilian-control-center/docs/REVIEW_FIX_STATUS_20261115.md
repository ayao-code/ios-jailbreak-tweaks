# Review 修复候选：bfirst7-reviewfix1

## 已修改的代码

- Easy 关闭回读要求 Session 非空，不再把 nil.status=0 当成断开。
- Easy 原生 Start 只在主队列登记/发布当前 generation 的状态；后台原生
  调用保持后台执行。取消后返回的结果不再修改新请求。原生启动尚未返回、
  或已取消的原生 Session 尚未确认断开时，拒绝新的 helper 请求；只停止
  本次原生 Session，不新增旧 A 停止命令或固定等待。
- UIKit 后台到期回调绑定 generation；空/旧回调不结束新请求。
- root 发布保留已兼容的 RootHide shell 原语；broker 把已校验目标的
  dev/inode 传给固定脚本，cd 后以实际 cwd 的 dev/inode/uid 比较，匹配后
  才 chmod/mv 固定 leaf。检查后替换目录不会改变固定 cwd 的 inode。
  所有发布统一走此入口，不再保留旧直接发布分支。
- 源文件通过 root、0600、64字节、普通文件、单硬链接检查后，目标错误均
  清理本次源文件。拒绝非法源/目标和实际 cwd 身份不匹配；目标 leaf
  原子替换而不跟随，不创建 App 目录中间文件。
- IPC 陈旧监听检查只 connect，不执行完整授权；仅明确 ECONNREFUSED
  且 inode 未改变时移除陈旧 socket，其他情况安全拒绝替换。
- 并发 close/到期探针对未获权、到期仍开放、close 后仍开放立即失败。
  历史 native-probe 与 live host 的 HTTPS 错误不再推进/返回成功。

## 当前验证证据与边界

Mac 编译实际 Easy helper 搭配 host-only UIKit/NetworkExtension stub，
验证 bookkeeping，不把 stub 当私有 API/真实隧道验证：15个检查通过。
最终 shell 发布器在目标手机独立验证两次：目标 inode 不匹配拒绝、源文件
清理且目标未写；身份匹配发布成功，许可 root/0644/64字节，随后精确清理。
只写无有效认证内容的测试许可，不发送 VPN 命令、不安装候选插件。
RuntimeGuard 10个检查通过；测试 oracle/陈旧 socket 源码不变量8个静态
检查通过。目标 iOS arm64/arm64e 源码编译、诊断源码语法和 DEB 构建通过。

RootHide 目标只读确认 /rootfs 为目录，真实 /var 指向 private/var；
原生 C 发布方案无法在 RootHide 中执行 App 目录 open/renameat，即使继承
目录句柄仍被 EPERM 拒绝。已停止该方案并移除本轮新建试验源码，最终保留
shell 的固定 cwd + broker inode 绑定，不修改权限或绕过沙盒。
目标 /var/run 为 root:daemon 0775，保留该真实权限。

候选 DEB 在本项目 packages/，源码与原历史失败记录均保留；没有覆盖
iCloud，没有把历史 bfirst6 六方向或安全回归当作本候选验收。
最终发布原语正负例已验证，但新 broker→脚本整体握手、Easy 取消边界
真机以及本候选完整三App开关/六方向仍待验证，发布门禁未通过。
新增 draining 防护按安全失败优先：若取消 Session 无法确认终态，拒绝
新请求，不无限保活/轮询；可能需要目标 App 正常重启恢复，需真机验收。

首次候选SHA256（本轮重建后不能用于最终包校验）：
`bf1dca94f230bd43c8dd9905acebe4031dbeae221648344e846356bb46dde1b1`。
最终源码/候选嵌套归档敏感信息检查通过。手机端独立诊断文件与测试许可
已删除；安全模式标记不存在。未安装候选、未刷新SpringBoard、未覆盖
旧bfirst6或iCloud，当前新增修复尚未提交，不冒充上一轮已提交内容。

后续同版本重建及真机安装/回归记录见 `REVIEWFIX_LIVE_20261115.md`，
本页“未安装”等状态属于前轮阶段快照，不能作为最新结论。

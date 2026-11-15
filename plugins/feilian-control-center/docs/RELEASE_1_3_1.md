# VPN 控制中心 1.3.1：无独立认证后台

## 发布边界

用户明确选择本机开放调用，去掉独立认证broker、许可文件和许可发布脚本。
App服务端不校验请求来自SpringBoard，不引入硬编码Token。保留本机App私有
socket权限和固定五目标开关；不开放网络端口、任意命令或全局App注入。
客户端仍核对实际目标VPN，避免向错误进程发请求或申请有限后台执行时间。

独立后台源码留作历史回滚参考，不参与当前构建。协议使用v2/vcc2.sock，
旧控制中心模块和新辅助不能混用，安装后需要刷新SpringBoard并重启目标
App主进程才能加载相应代码；不等于需要整机重启，不改RootHide隔离规则。

## 发布审核修复

本机开放模式下，原服务实例级_lastGeneration可被其它调用者的大编号影响，
使后续控制中心编号被拒绝。1.3.1改为接受新连接后重置编号，仅对同一连接
拒绝重复/倒序；_peerEpoch仍隔离旧回调。没有恢复来源认证或认证后台。
补充真实socket回归：UINT64_MAX请求后新连接编号1可用，同连接重复1仍拒绝。
App辅助使用不复用的内部operation ID，与调用者wire编号分离，防止取消后
旧异步回调影响新请求。服务端超时测试要求真实EOF且小于1.5秒，禁用服务端
计时器的故障注入副本必须失败，避免客户端自身超时假通过。

87项Mac真实socket检查、15项Easy资源归属、10项运行时测试对象检查通过，
另8项静态判据检查通过。Mac检查不是手机功能、界面或联网证据。

## 已验证与未验证

12 mini前序无后台候选：Easy、飞连、Hotspot、Jump独立后台开/HTTPS/关通过；
Easy/飞连/Hotspot六个有向切换6/6通过；Easy和飞连主App退出后后台冷启动
重连通过；Hotspot空闲310秒后开/HTTPS/关通过。正式版的编号隔离修复经
本机87项回归，不能将前序候选实机证据误写成正式版全部场景再次执行。

GOFast原有Beta原生连接仍超时，不宣称已修复。Jump/GOFast继续标Beta。
真实点击/长按/截图GUI未执行，原因是mobile_not_authorized及无USB设备；
宿主方法调用不是手指触摸。没有长期续航或全部App兼容性保证。
整体SpringBoard33秒样本CPU约0.14%空闲/0.37%操作期，内存约101-110MiB；
包含系统及其它插件，不能当成此插件独占开销或因果增量。

## 产物

`packages/ayao.feiliancontrolcenter_1.3.1_iphoneos-arm64e.deb`

SHA256: `3a4dc83b3d512c367de0c80a889e1ead656bb4b4442f63d3b9b3c9fa0b93f6bd`

仅为RootHide目标打包，不承诺普通rootless安装验证。发布只推VPN专属分支，
不推当前main中其它未发布提交，不自动创建GitHub Release或tag。
账号、节点、VPN配置、RootHide名单和控制中心排列保持，先备份再安装回读。

# bfirst7-reviewfix1 真机验收记录

目标 iPhone13,1 / iOS16.3.1 / RootHide；2026-11-15。
本轮构建、隐私扫描与安装回读均为 bfirst7-reviewfix1，不沿用bfirst6通过项。
新broker发布权限、dev/inode绑定与App nonce/audit许可在真实SpringBoard
握手使用同一已安装IPC；没有复制业务实现或绕过认证。

## 当前已观察

- 目标起始五VPN全断开且已解锁，无安全模式标记。
- 有限握手/probe/双线程close回归：10/10客户端均ready=1，逐轮close
  完成并要求close后probe为false，最终ready_count=10；完整回执仅一个
  STRESS_STARTED，暂未观察到新增CrashReporter报告。
- 首次取消回归固定50ms取样：仅1/10观察到opening FD且通过，其余9个
  CANCEL_WINDOW_NOT_OBSERVED；不能算10次取消通过。20次相同snapshot
  回读state_callbacks=0。测试窗口采样改成最多1秒内有限观察opening FD，
  不修改生产状态机，不把窗口不足样本抹除。

## 验收边界

临时SpringBoard-only测试调用已安装handler/IPC，不是真实手指点按或长按
视觉验收。RootHide高敏App隔离不改，高德/阿里/金融/京东不注入或附加。
标准SDT Custom发现无flux-sdt.yaml，完整标准管线未执行，不冒充全通过。

本轮不会自动覆盖iCloud；只有新的完整实际结果才用于判断候选可交付。

- 同版执行断言15秒安全到期，两个已获权客户端均在20秒后probe失败，
  双线程close完成，最终ready_count=2；并非仅因为没获权而假通过。
  运行前标头的iterations=10属于工具固定文本，实际到期模式迭代数为2，
  以两条逐轮记录及最终计数为准。未发送connect/disconnect命令。

- 改进取消窗口观察后：10/10实际opening FD被观察到，取消后open=0及
  probe=0，0.002–0.042秒完成。首轮窗口不足记录保留，不替换为通过。
  20次相同回读依然0次state callback。该项是IPC建立/认证取消，不是
  原生VPN启动进行中的取消，不混淆验证边界。

## 三个原生后台开关

| 提供方 | 初次连接到准确稳定回读 | HTTPS | 原生关闭 |
| --- | --- | --- | --- |
| Easy | 17.022秒 | 200/Success | 通过 |
| 飞连 | 10.037秒 | 200/Success | 通过 |
| Hotspot | 15.017秒 | 200/Success | 通过 |

每次连接后6秒仍为唯一目标，随后明确原生关闭并回读全断开；默认选择
恢复为本轮测试开始时的Easy，完整BFIRST_TEST_DONE。没有发送旧A停止。
圆形进度三次均animating=1，center delta_x/delta_y为0.000；只证明紧凑
布局几何，不冒充长按展开视觉。该组实测没有新增CrashReporter报告。

## 原生启动进行中取消

独立真实SpringBoard工具通过已安装IPC启动Easy，在系统状态2（connecting）
且请求还未返回时close同一客户端，随后系统所有目标全断开并保持至少1秒，
回执为VPNReplyTimeout=7，取消到收尾约1.009秒；没有新增崩溃报告。
这是一条真实原生连接进行中的取消样本，不等于所有OldStart迟到并发交错
都被覆盖。后续完整矩阵起始Easy重连用于补查取消后恢复。

## 六方向回归：第一方向失败，未完整通过

取消后Easy初连成功（17.098秒、6秒后唯一目标、HTTPS200/Success），
说明该实际取消样本后的恢复可用。随后Easy→飞连从选择到结束19.999秒
失败，failed=1，系统当时仅飞连活动但status=2/connecting而非connected。
没有把activeProvider=feilian当成功。之后五方向未执行，不称6/6。

操作日志中：飞连target-ready约5.967秒，connect-dispatch约5.969秒；
旧Easy由系统退出，飞连connecting；connect-reply=7在15.864秒，4秒
有限系统观察后仍未确认稳定connected，19.873秒报告超时。与15秒
执行断言预算已被准备/认证消费的风险相符，但没有采集本次断言到期
专属stage来证明因果；也没有证明飞连节点/网络时延正常，不武断归因。
不得通过延长无限保活、去掉安全预算或挑选重跑成功样本“修复”此失败。

失败后立即禁用网络测试，独立工具只停止本轮飞连目标；最终五目标均
status=1/connected=0/active=0，REACHED=1。没有新增CrashReporter报告。

本次已安装module及Easy helper的arm64/arm64e __text与本地候选一致；
broker arm64 __text一致，publisher脚本字节一致。RootHide重签会改变
整文件hash，未宣称整文件hash相同。候选包本轮重建SHA256：
`5788351809424a86c9c7b1e9821a984068f586df0df50406b8f1cfa626932b1c`。

## 收尾

本轮测试dylib/filter已精确删除并刷新卸载；最终手机正常、已解锁、无安全
模式标记，五目标均断开，默认Easy与本轮开始一致。四份RootHide策略字节
一致，高敏隔离没有变化。CrashReporter全列表相较本轮基线新增0。
临时解锁文件在最后刷新后删除，内存映射下次正常宿主重启退出，不宣称
已经全部退出内存。私有日志与原样二进制保留在Mac受限临时目录。

bfirst7候选仍安装手机，不冒称稳定发布；切换失败没有修改为通过，没有
覆盖iCloud，旧silent1云盘哈希保持不变。此次修复和新增测试未提交/推送。
下一步应定位飞连准备认证与有限断言预算的具体耗时、原生connecting迟到
或失败原因，再选择不改变系统安全预算的修复路径。当前不能说任务完成。

## 后续发布决定

用户随后明确接受飞连切换超时暂不处理，要求1.3.0发布并安装两台手机即可。
前述“不能发布/尚未提交”属于当时阶段状态，当前决定与安装回读见
RELEASE_1_3_0.md。失败没有被删除或改成通过，发布不表示全部验证完成。

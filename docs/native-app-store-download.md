# 在手机 App Store 批量发起下载

## 已跑通的方案

通过 SSH 启动一个**独立、短生命周期的系统输入工具**，直接操作手机原生
App Store。不是向下载目标 App 注入，也不是下载 IPA 后侧载。

2026-11-17 在 iPhone 12 mini / iOS 16.3.1 / RootHide 上，已观察到淘宝、天猫
点击云下载后变为加载状态；淘宝开始下载另有用户确认。支付宝点击后截图超时，
重新打开其准确页面时已显示“打开”，因此未重复点击。加载状态只证明下载请求
已生效；“打开”是安装侧 UI 证据，不代替完整版本/注册回读，也不代表其他设备
已经验证。

本轮最终已提交 10 款请求：淘宝、天猫、支付宝、闲鱼、点淘、高德地图、优酷、
钉钉、夸克、淘宝闪购。按用户要求未等待全部安装完成；除支付宝重开页面显示
“打开”外，其余依据点击后的加载状态。临时控制工具随后移除，系统继续下载。

## 操作顺序

1. **确认目标**：核对 SSH 与 USB 的机型、系统版本和配对设备；不要把旧设备
   地址、旧快照或历史安装清单当作当前事实。
2. **建立清单**：通过 Apple lookup 核对每款应用的 App Store item ID、精确
   Bundle ID、名称、价格和最低系统版本。Bundle ID 不一致就拒绝；禁止凭记忆
   猜 item ID。此次只处理免费应用。
3. **准备控制工具**：优先使用已有可运行的 WDA/Appium 元素定位；WDA 不可用
   时，经用户授权，使用本仓库的独立 App Store 输入变体和只读截图工具。
4. **打开准确页面**：调用 `uiopen --url` 打开清单中的 `itms-apps://` URL，
   等待页面就绪；不通过模糊搜索随便点结果。
5. **检查现场**：读取锁定状态和精确前台 Bundle ID，取得新截图，确认应用
   标题以及“获取”或云下载按钮。输入前再次截图，比对标题及按钮区域；主体
   变化就不点击。状态栏、开发者滚动字幕等动态内容不作为稳定性基准。
6. **发送一次点按**：坐标从当前截图中的实际按钮推导并归一化到 0..1，不
   复用其他机型的固定坐标。工具自身再次检查未锁定和 App Store 前台。
7. **确认请求生效**：立即截图，检查按钮变为加载圈、下载进度或“打开”，并
   确认没有账号验证、付费或异常弹窗。事件 API 返回 0 本身不算成功。
8. **切换下一款**：用户只要求发起下载时，不等安装完成、不轮询到完成；系统
   自行处理后台下载。只有要求核验安装时，才另做应用注册表及版本回读。
9. **收尾**：记录请求数量、未提交项和阻塞原因，移除本轮上传的临时工具，
   关闭本轮 SSH 控制连接；不要移除既有工具或停止 App Store 后台下载。

## 工具与构建

- 源码：`app/safe-domain-probe/tools/ui-input/main.m`，构建宏
  `SDP_ALI_RESTORE_UI=1`。该变体只允许 App Store / RootHide Manager；本流程
  只操作 App Store，不修改 RootHide 开关。
- 截图：`app/safe-domain-probe/tools/screen-observe/main.m`，优先默认 UIKit
  捕获；黑图、尺寸异常或无法核对内容时停止，不能根据失效截图输入。
- 构建：`scripts/migration/build-native-store-helpers.sh`，输出目录由调用者
  传入。它保留源码，不安装服务、不修改目标 App、不引入后台循环。
- Mac 控制：`scripts/migration/native-app-store-control.py`，提供 `open`、
  `tap`、`capture` 三个子命令。连接、机型、系统、截图尺寸和按钮区域由参数
  提供；不内置设备地址、密码或固定机型坐标。不自动识别按钮、不批量盲点，
  必须人工/助手查看截图后显式传入 `--reviewed`。
- 设备调用：`store-screen --state`、`store-ui-input --check com.apple.AppStore`、
  `store-ui-input tap com.apple.AppStore <x> <y>`；分别用于状态、门控与点按。
- 旧 `native-app-store-ui.py` 的机型、画面尺寸和模板针对历史 14PM，不能直接
  用在 12 mini；复用逻辑必须重新确认当前设备与截图布局。

### 可复用工具调用

需要 macOS、Python 3、Pillow、可用的 SSH 控制连接；构建还需要 Xcode Command
Line Tools、已有 iOS SDK 和 `ldid`。原生输入/截图源码和签名配置均已在仓库保留，
不需要从设备导出二进制。控制脚本是本轮临时脚本的参数化版本，本轮实机证据
来自原始流程；发布版本的本地安全校验不等于重新完整执行 10 款下载。

```sh
python3 -m pip install -r scripts/migration/native-app-store-requirements.txt
bash scripts/migration/build-native-store-helpers.sh "$BUILD_DIR"
# 经授权将 store-ui-input / store-screen 放到目标临时目录并赋予执行权限。
# 通过已有 SSH 控制连接，先在手机正常打开 App Store；不要记录密码。
python3 scripts/migration/native-app-store-control.py \
  --socket "$SSH_SOCKET" --host "$SSH_TARGET" --evidence "$EVIDENCE_DIR" \
  --machine "$DEVICE_MODEL" --os-version "$IOS_VERSION" \
  --screen-size "$NATIVE_SCREEN_SIZE" \
  open --item "$APP_STORE_ID" --bundle "$BUNDLE_ID" --filename before.png

# 查看 before.png，确认标题、免费按钮、无弹窗；自行量取当前图中的区域。
python3 scripts/migration/native-app-store-control.py \
  --socket "$SSH_SOCKET" --host "$SSH_TARGET" --evidence "$EVIDENCE_DIR" \
  --machine "$DEVICE_MODEL" --os-version "$IOS_VERSION" \
  --screen-size "$NATIVE_SCREEN_SIZE" \
  tap --reference before.png --after after.png \
  --title-box "$TITLE_BOX" --button-box "$BUTTON_BOX" \
  --x "$BUTTON_X" --y "$BUTTON_Y" --label cloud --reviewed
```

区域为 `left,top,right,bottom`，点和区域均归一化到 0..1；“获取”使用
`--label get`。每款使用新的截图文件名。`open` 留下准确清单和截图摘要，`tap`
要求摘要匹配，重新核对 Apple 清单，检查新截图的标题/按钮稳定性，并在发送
事件**之前**落盘 `tap_attempt`。同一个证据目录中已尝试的 item ID 禁止再次
点按；结果未知时先查看页面，不换目录绕过防重复门槛。`capture` 用于重新观察。

控制脚本不会自动解锁。锁屏时停止；确认确实没有密码后，可按上文原生工具
的限制执行正常亮屏上滑，再重新检查。不要修改系统密码/自动锁定设置。

## 边界与常见误判

- SSH 密码不是 Apple ID 密码，不读取账号 Token、Keychain 或敏感 App 沙盒。
- 不侧载、不重签名目标 App、不 Hook、不附加调试器、不修改注入或隔离配置，
  下载后不主动启动高敏 App，不处理其登录或隐私协议。
- Apple ID、两步验证、Face ID / Touch ID、价格、订阅等提示出现时停止，交由
  用户处理。正常免费安装确认也必须先核对真实弹窗，不能泛化为“允许所有”。
- 锁屏且设置了密码时停止；只有实时确认未设置密码，才可正常亮屏上滑。
  `--unlock-no-passcode` 返回非零后先回读状态，不盲重试侧边键。
- WDA 图标或 `uicache -l` 条目不证明 runner 可启动。本次残留条目只有占位
  可执行文件，没有 `PlugIns/*.xctest`，USB installation_proxy 也未找到它。
- **WDA 不可用不等于无法操作 App Store**。先检查现有独立工具；不要把下载
  按钮全部推给用户，也不要为了控制 UI 改高敏 App 或其隔离状态。
- 点按后的截图超时不代表点按失败。先重开准确页面观察当前按钮；“打开”、
  进度圈或等待状态均不再点击，防止误开业务 App 或取消已提交的下载。
- 如独立工具无法执行，先确认签名和当前命名空间；不能自动放宽权限、信任
  证书或修改安全设置。新增签名/安装控制工具应单独评估和授权。
- 公开文档与提交不得包含连接地址、密码、UDID、个人路径或账户信息；截图和
  本次操作日志存入私有、被忽略的证据目录。

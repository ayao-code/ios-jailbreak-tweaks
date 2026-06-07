# TBAntiJBDetect

淘宝（com.taobao.taobao4iphone）越狱检测绕过插件，适用于 iOS 16 Dopamine rootless 环境。

当前版本：v1.0.0-beta1

## 功能

- 只注入淘宝 APP，不注入 SpringBoard 或系统进程。
- **零日志、零 CPU 开销、不耗电**（beta1 已关闭所有日志输出）。
- ObjC 层：hook `isJailBreak` / `isJailBroken` / `TBIsJailBreak` / `judgeJailbrokenCanPay` / `detectCurrentDeviceIsJailbroken` 等越狱检测方法，直接返回 NO。
- NSFileManager 层：`fileExistsAtPath:` / `contentsOfDirectoryAtPath:` 等文件检测 API 对越狱路径返回 NO。
- NSURL 层：`checkResourceIsReachableAndReturnError:` 对越狱路径返回不可达。
- UIApplication 层：`canOpenURL:` 对 `cydia://` / `sileo://` 等越狱 URL scheme 返回 NO。
- C 层 fishhook：`stat` / `lstat` / `access` / `fopen` / `open` / `openat` / `dlopen` / `opendir` / `readdir` / `getenv` / `_dyld_get_image_name` / `sysctlbyname` / `dlsym` / `dladdr` / `task_info` 全部拦截。
- dyld API 全面替换：隐藏所有越狱 dylib，使 `_dyld_image_count` / `_dyld_get_image_name` 只返回安全镜像。
- `task_info(TASK_DYLD_INFO)` hook：从内核层面隐藏 dylib 信息。
- 环境变量清理：只删除越狱相关变量（`DYLD_INSERT_LIBRARIES` / `_MSSafeMode` 等），不遍历全部。
- 完整覆盖 Dopamine rootless 核心路径 + 通用越狱工具路径。

## 兼容环境

- iOS 15–16
- Dopamine rootless 越狱
- arm64 / arm64e 设备
- 需要 `mobilesubstrate`

## 安装

下载 `ayao.tbantijbdetect_1.0.0_iphoneos-arm64.deb` 后安装：

```sh
dpkg -i ayao.tbantijbdetect_1.0.0_iphoneos-arm64.deb
```

安装后重启淘宝 APP 即可生效。

## 构建

```sh
cd plugins/tb-anti-jbdetect
THEOS=~/theos FINALPACKAGE=1 make clean package
```

## beta1 说明

- 首个测试版本，客户端越狱检测绕过已全部验证通过。
- 已知限制：服务端设备级风控（如"活动火爆"）无法通过客户端绕过解决，需等风控标记过期。
- 日志已完全关闭，如需调试可将 `Tweak.x` 顶部 `#define TB_DEBUG 0` 改为 `1`。

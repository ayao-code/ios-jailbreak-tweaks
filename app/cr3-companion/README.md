# CR3 Companion

越狱 iOS 16 前台工具，用于把系统无法预览的佳能 CR3 真正解码为高质量伴生 JPEG。

## 行为

- 手动扫描图库，只列出尚无伴生 JPEG 的 CR3。
- 使用内置 LibRaw 在手机本地解码，不依赖 Mac、SSH 或网络服务。
- 输出完整分辨率、sRGB、JPEG Q100。
- 继承拍摄时间、位置、方向、收藏、隐藏状态和可编辑用户相册关系。
- 保留 CR3，不直接读写 `Photos.sqlite`，不注入照片 App。
- 串行处理，每张结束后释放内存和删除临时文件；支持在当前照片完成后暂停，重新扫描即可续跑。
- 仅在 App 前台运行，不注册后台任务、定时器或守护进程。

## 构建

```sh
THEOS="$HOME/theos" make clean package FINALPACKAGE=1
```

LibRaw 0.21.5 的完整源码位于 `vendor/LibRaw/`，按其 CDDL/LGPL 双许可证保留原始许可证文件。本项目按 CDDL 条款使用未修改的 LibRaw 源码。

## 限制

- 手机本地 RAW 解码会消耗较多 CPU、电量和内存，批量处理时建议连接充电器并保持 App 在前台。
- LibRaw 默认显色与 Canon DPP、macOS Camera RAW 可能略有差异；Q100 只描述 JPEG 编码质量，不代表保留全部 RAW 可编辑信息。
- PhotoKit 会记录实际导入时间，但时间线按继承的拍摄时间排列在 CR3 附近。

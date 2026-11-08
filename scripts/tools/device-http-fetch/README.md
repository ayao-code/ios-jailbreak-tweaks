# 设备端 HTTP 文件拉取工具

用于已授权设备的大文件恢复传输。工具通过指定的 IPv4 地址和端口执行简单 HTTP GET，将响应写入目标路径的 `.incoming` 文件，边接收边计算 SHA-256；只有字节数和哈希均匹配时才原子改名为正式文件。已有完整文件会复用。

工具只负责缓存文件传输，不访问或修改照片图库。服务端应仅临时暴露本次已校验分块，使用完成后立即停止。

```sh
xcrun clang -target arm64-apple-ios16.0 \
  -isysroot "$HOME/theos/sdks/iPhoneOS16.5.sdk" \
  -fobjc-arc -O2 -Wall -Wextra -Wno-deprecated-declarations \
  -framework Foundation DeviceHTTPFetch.m -o /tmp/DeviceHTTPFetch
ldid -S /tmp/DeviceHTTPFetch
```

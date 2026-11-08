# 设备原生 HTTPS 连通性探测

独立短时命令行程序，使用 iOS NSURLSession 对六个固定公开网站执行 HEAD。
不发登录请求、不读取账号、代理节点或订阅，不保存响应、Cookie、密码或文件。
仅输出 HTTP 状态、错误代码、耗时、系统代理开关及 utun 数量；隧道存在不证明代理可用。
第三方路由可能按进程选择路径，HTTPS 探测不能证明 Telegram MTProto 或 X 登录可用。

构建：

```sh
xcrun clang -target arm64-apple-ios16.0 -isysroot "$HOME/theos/sdks/iPhoneOS16.5.sdk" \
  -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-unused-parameter \
  -framework Foundation -framework CFNetwork main.m -o /tmp/device-network-probe
ldid -S /tmp/device-network-probe
```

仅在授权设备临时运行，完成后删除设备端程序。编译或 TCP 成功不等于实际 App 网络功能验收。

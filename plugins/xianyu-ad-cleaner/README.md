# XianYuAdCleaner

闲鱼去广告插件，适用于 iOS rootless 越狱环境。

这个插件用于替代广告终结者里的 `XianYuAdKiller.dylib` 闲鱼模块。它只处理广告，不修改闲鱼 UI：

- 不 hook `FMTabBar`
- 不 hook `UITabBarAppearance`
- 不 hook `UIApplication` 状态栏
- 不写 `XYHomeAlpha` / `XYDetailAlpha`
- 不修改底部栏、导航栏、安全区、颜色或透明度

## 当前处理范围

- 拦截 `FMSplashModule` 的开屏广告展示方法。
- 清理类名或 accessibility 标识明显属于闲鱼开屏/广告的视图。
- 不对普通 `UITabBar`、`UINavigationBar` 或系统状态栏做任何处理。

## 构建

```sh
cd plugins/xianyu-ad-cleaner
THEOS=~/theos FINALPACKAGE=1 make clean package
```

安装本插件前，建议用 Choicy 禁用广告终结者里的 `XianYuAdKiller.dylib` 对闲鱼的注入，避免两个插件同时作用。

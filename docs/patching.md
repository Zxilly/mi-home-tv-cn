# 处理方式

原版 Google Play TV 包的关键构建参数为：

```text
package       com.xiaomi.smarthome.tv.global4
flavor        GOOGLE_PLAY
server tag    DE
third login   true
```

原版应用页面：

- Google Play：<https://play.google.com/store/apps/details?id=com.xiaomi.smarthome.tv.global4>
- 本次测试输入：APKPure 提供的 2.8.0.2 XAPK

仓库不包含原版 APK/XAPK，也不包含签名私钥。

补丁只改变区域，不把应用伪装成国行系统包：

1. 在 `App.initSmartHomeClient()` 内把默认 `serverTag` 从 `DE` 改为 `CN`。
2. 将 `BuildConfig.SERVER_TAG` 改为 `CN`。原有代码会据此执行
   `setMainLandApk(true)`。
3. 在 `SelectServerActivity` 的地区列表首项加入“中国大陆 / CN”。
4. 保留 `THIRD_LOGIN=true`，继续使用 global4 自带登录流程。
5. 版本名增加 `-cn1`，移除仅供 Play split 校验的 manifest 属性。
6. 重新构建 base，并将 base 和所有 split 用同一证书签名。
7. 使用 APKEditor 合并 split，生成可直接安装的 universal APK。

不要全局替换所有 `DE` 字符串。`App.getCurrentServer()` 内还有一处 `DE`，它是
服务器代码到路由编号的正常映射，修改会破坏德国区路由。

## 工具

- apktool 3.x
- Android SDK Build Tools（`zipalign`、`apksigner`）
- Python 3
- Java 17+
- 7-Zip
- [APKEditor](https://github.com/REAndroid/APKEditor) 1.4.9

构建脚本会从 APKEditor 官方 Release 下载固定版本并校验 SHA-256：

```text
A9CD40DF818845456BE6D696DE6110C89EDF4B0A0580CB83438ED6B25A366E67
```

私钥不进入仓库。默认使用当前用户的 Android debug keystore；若需要持续发布可覆盖
升级的版本，应自行保管固定 keystore，并通过 `-Keystore` 指定。

## 验证

发布前至少确认：

- 所有 split 和 universal APK 的签名证书一致；
- `apksigner verify` 与 `zipalign -c` 通过；
- universal APK 的 `pm path` 只有一个 `base.apk`；
- 冷启动进入 `MainActivity`；
- 中国区家庭和设备列表能够加载；
- 遥控器方向键焦点可移动。

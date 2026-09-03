# Mi Home TV CN

将 Google Play 版 Mi Home TV（`com.xiaomi.smarthome.tv.global4`）切换到中国大陆
服务器。应用保持 TV 横屏和遥控器操作，并与国行
`com.xiaomi.smarthome.tv` 共存。

## 使用

从 [Releases](https://github.com/Zxilly/mi-home-tv-cn/releases/latest) 下载
`MiHome-TV-global4-CN-2.8.0.2-cn1-universal.apk`：

```powershell
adb install MiHome-TV-global4-CN-2.8.0.2-cn1-universal.apk
```

如果已经安装 Google Play 原版，因签名不同需先卸载：

```powershell
adb uninstall com.xiaomi.smarthome.tv.global4
```

首次启动后按电视提示完成协议确认和登录。此版本为非官方修改包，不能通过
Google Play 原版直接覆盖升级。

## 构建

准备原版 `com.xiaomi.smarthome.tv.global4` 2.8.0.2 XAPK，然后运行：

```powershell
.\scripts\build.ps1 -InputXapk .\MiHome-TV-global4-2.8.0.2.xapk
```

详细处理方式见 [docs/patching.md](docs/patching.md)。

# ArkLores iOS / iPadOS 配置、构建与安装

> **未维护**：本文停在 v0.9.0。0.10、0.11 只在 Android 上开发和验证过（前台服务、启动图标、知识库安装路径都只有 Android 实现被测试）；在 iOS 上发布前需要重新验证。

本文适用于 ArkLores v0.9.0 的 iOS / iPadOS 本地开发、真机安装与验收。当前仓库已包含
iOS 工程、iPad 目标配置、启动页资源、浅色/深色 App 图标资源和运行时图标切换通道。

> 当前限制：iOS 构建、签名和安装必须在 macOS + Xcode 上完成。Linux 环境可以检查 Dart
> 代码和 Android 构建，但不能替代 `xcodebuild`、Xcode 签名或 iPad 真机安装。

## 快速开始

在 macOS 上连接 iPad，并确保 iPad 已解锁、信任当前电脑：

```bash
/path/to/flutter/bin/flutter doctor -v
/path/to/flutter/bin/flutter pub get
cd ios
pod install
cd ..
/path/to/flutter/bin/flutter devices
/path/to/flutter/bin/flutter run -d <iPad设备ID>
```

若只想生成本地调试构建：

```bash
/path/to/flutter/bin/flutter build ios --debug
```

首次安装建议使用 Xcode 打开工程并完成签名：

```bash
open ios/Runner.xcworkspace
```

在 Xcode 中选择 `Runner` target、自己的 Team、连接的 iPad，然后点击 Run。

## 环境要求

| 组件 | 当前要求 | 检查方式 |
| --- | --- | --- |
| macOS | 必需，不能用 Linux/Windows 替代 | `sw_vers` |
| Xcode | 安装完整 Xcode，并完成首次启动组件安装 | `xcodebuild -version` |
| Command Line Tools | 指向完整 Xcode | `xcode-select -p` |
| Flutter | 项目支持的 Flutter / Dart SDK | `flutter --version` |
| CocoaPods | iOS 插件依赖安装工具 | `pod --version` |
| Apple ID / Team | 个人设备安装需要签名 Team | Xcode -> Settings -> Accounts |
| iPad | 已解锁、信任电脑，开发者模式已开启 | `flutter devices` |

推荐先执行：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
flutter doctor -v
```

## 工程配置

iOS 工程关键配置：

| 配置 | 位置 | 当前状态 |
| --- | --- | --- |
| 最低系统版本 | `ios/Runner.xcodeproj/project.pbxproj` | iOS 12.0 |
| 设备族 | `TARGETED_DEVICE_FAMILY` | `1,2`，支持 iPhone 和 iPad |
| iPad 方向 | `ios/Runner/Info.plist` | 支持四个方向 |
| 主图标 | `AppIcon.appiconset` | 已存在 |
| 可切换图标 | `AppIconLight.appiconset` / `AppIconDark.appiconset` | 已存在 |
| 原生图标通道 | `ios/Runner/AppDelegate.swift` | 已存在 |
| CocoaPods | `ios/Podfile` | 已配置 |

## 真机安装

### 1. 设备准备

1. 用 USB 连接 iPad。
2. iPad 上点击“信任此电脑”。
3. iPadOS 16 或更新版本需要开启“开发者模式”：
   `设置 -> 隐私与安全性 -> 开发者模式`。
4. 重新插拔设备后检查：

```bash
flutter devices
```

### 2. 签名配置

打开：

```bash
open ios/Runner.xcworkspace
```

在 Xcode 中：

1. 选择 `Runner` target。
2. 打开 `Signing & Capabilities`。
3. 勾选 `Automatically manage signing`。
4. 选择自己的 Apple ID Team。
5. 如果 Bundle Identifier 冲突，把 `com.arklores.arklores` 改成自己的唯一 ID，
   例如 `com.<你的名字>.arklores.dev`。

个人免费 Apple ID 通常可以安装到自己的设备，但证书有效期和设备数量有限。

### 3. 运行安装

推荐首次用 Xcode Run。之后可用 Flutter CLI：

```bash
flutter run -d <iPad设备ID>
```

Release-mode 本地验收：

```bash
flutter build ios --release
```

Release 安装到个人 iPad 仍需要有效签名。若不是 TestFlight/App Store 分发，通常继续通过
Xcode 选择真机运行或 Archive 后手动安装。

## GameData 真机测试

App 不内置数据库。iPad 上不能使用 Android 的 `adb reverse`。如果要测试 GameData 下载，
必须使用 iPad 可访问的 URL。

推荐使用 HTTPS：

```bash
flutter run -d <iPad设备ID> \
  --dart-define=ARKLORES_GAMEDATA_DB_URL=https://example.invalid/arklores_gamedata_zh.db.gz \
  --dart-define=ARKLORES_GAMEDATA_DB_SHA256=<64位十六进制SHA256>
```

本地开发也可以用局域网 HTTP 服务，但 iPad 必须能访问开发机 IP：

```bash
python3 -m http.server 8765 --directory build/gamedata_mobile
flutter run -d <iPad设备ID> \
  --dart-define=ARKLORES_GAMEDATA_DB_URL=http://<Mac局域网IP>:8765/arklores_gamedata_zh.db.gz \
  --dart-define=ARKLORES_GAMEDATA_DB_SHA256=<64位十六进制SHA256>
```

安装后打开：`Settings -> Knowledge Base -> GameData 主知识库 -> 下载/更新`。

## iPad 验收清单

安装后至少检查以下场景：

| 场景 | 期望 |
| --- | --- |
| 冷启动 | 启动页、图标和首屏不闪白、不变形 |
| Wiki 浏览 | PRTS / Endfield / 自定义 Wiki 可加载 |
| 后台恢复 | 切出一段时间后返回，保留上次 tab 和页面 |
| 阅读模式 | 日间/夜间切换、字体缩放、退出阅读正常 |
| PRTS 剧情页 | 阅读模式显示单独 `LOG ALL` 按钮，点击后展示全部对话 |
| WebView 手势 | 边缘左/右划对应前进/后退，不退出 App |
| App 图标 | 设置中浅色/深色图标切换生效 |
| iPad 横竖屏 | 主要页面不溢出，工具栏不遮挡内容 |
| 分屏/台前调度 | 宽度变化后布局可用 |

## 常见问题

### 当前 Linux 电脑不能安装到 iPad

这是平台限制。iOS 真机构建依赖 Apple 的 `xcodebuild`、签名服务和设备调试栈，必须在
macOS 上运行。

### `pod install` 失败

先确认：

```bash
flutter pub get
cd ios
pod repo update
pod install
```

如果仍失败，删除派生产物后重试：

```bash
flutter clean
flutter pub get
cd ios
rm -rf Pods Podfile.lock
pod install
```

### Xcode 报 Bundle Identifier 不可用

把 `Runner -> Signing & Capabilities -> Bundle Identifier` 改成自己的唯一 ID。
修改后不要提交个人 Bundle ID，除非项目决定统一 iOS 包名。

### iPad 上提示无法验证开发者

在 iPad 上打开：

```text
设置 -> 通用 -> VPN与设备管理
```

信任你的 Apple ID 开发者证书。

### App 图标切换没有立即显示

iOS 会弹出系统确认框，且桌面刷新可能有延迟。先回到桌面等待几秒；仍未变化时重启 App
或重启设备再检查。

### HTTP GameData 下载失败

iPad 不能访问 Mac 的 `127.0.0.1`。请使用 Mac 的局域网 IP，或优先使用 HTTPS 远程地址。

## 本次环境验证记录

在当前仓库所在环境执行的检查结果：

```text
OS: Arch Linux
xcodebuild: not found
ios-deploy: not found
flutter devices: only Linux desktop detected
idevice_id -l: Unable to retrieve device list
```

因此，本环境无法完成 iPad 真机安装。可完成的跨平台验证仍应先运行：

```bash
flutter analyze
flutter test
```

最终 iPad 验收必须迁移到 macOS/Xcode 环境执行。

## 相关文档

- `docs/ANDROID_SETUP_GUIDE.md`
- `docs/GAMEDATA_BUILD_PIPELINE.md`
- `../CONTRIBUTING.md`
- <https://docs.flutter.dev/platform-integration/ios/setup>

# ArkLores — Android 构建环境配置指南

> 适用平台：Arch Linux（其他 Linux 发行版步骤类似）
> 目标：从零配置 Flutter Android 构建环境，生成 APK 并在真机上安装运行

---

## 快速开始（一键脚本）

项目提供了自动化脚本 `tools/setup.sh`，涵盖 SDK 安装、APK 构建、设备安装全流程：

```bash
# 进入交互式部署向导
./tools/setup.sh

# 非交互：构建 debug APK
./tools/setup.sh -a build -p android -m debug

# 非交互：构建 release APK
./tools/setup.sh -a build -p android -m release

# 非交互：注入已有 GameData 临时下载 URL
./tools/setup.sh --with-gamedata \
  --gamedata-url http://127.0.0.1:8765/arklores_gamedata_zh.db.gz \
  --gamedata-sha <sha256>
```

脚本会自动检测缺失的组件（Java、Android SDK、adb）并引导安装。详细步骤见下文。

---

## 脚本参考

| 用法 | 说明 |
| --- | --- |
| `./tools/setup.sh` | 进入交互式部署向导 |
| `./tools/setup.sh -a build -p android -m debug` | 仅构建 debug APK |
| `./tools/setup.sh -a build -p android -m release` | 仅构建 release APK |
| `./tools/setup.sh --with-gamedata --gamedata-source=/path/to/ArknightsGameData` | 构建并注入 GameData 临时下载参数 |
| `./tools/setup.sh --dry-run ...` | 只解析配置，不执行构建/安装 |
| `./tools/setup.sh --help` | 查看帮助 |

**环境变量**：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `ANDROID_HOME` | `~/Android/Sdk` | Android SDK 路径 |
| `FLUTTER_HOME` | `~/flutter` | Flutter SDK 路径 |

以下为分步手动教程——脚本执行的就是这些步骤，供排查问题时参考。

## 一、前置条件

| 组件 | 说明 | 检查命令 |
|------|------|---------|
| **Flutter SDK** | 位于 `~/flutter` | `~/flutter/bin/flutter --version` |
| **Java JDK** | ≥ 17（推荐 21） | `java -version` |
| **Android SDK** | 命令行工具 + platform-tools + build-tools | 见下文 |

> Java 通常已预装。如未安装：`sudo pacman -S jdk21-openjdk`

---

## 二、安装 Android SDK（轻量方案，无 Android Studio）

### 2.1 下载命令行工具

```bash
mkdir -p ~/Android/Sdk
cd ~/Android/Sdk
wget https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip commandlinetools-linux-*_latest.zip
rm commandlinetools-linux-*_latest.zip
```

### 2.2 整理目录结构

SDK Manager 要求工具位于 `cmdline-tools/latest/` 子目录：

```bash
mkdir -p ~/Android/Sdk/cmdline-tools/latest
mv ~/Android/Sdk/cmdline-tools/bin ~/Android/Sdk/cmdline-tools/latest/
mv ~/Android/Sdk/cmdline-tools/lib ~/Android/Sdk/cmdline-tools/latest/
mv ~/Android/Sdk/cmdline-tools/*.* ~/Android/Sdk/cmdline-tools/latest/
```

### 2.3 安装 SDK 组件

```bash
# 接受所有许可证
yes | ~/Android/Sdk/cmdline-tools/latest/bin/sdkmanager \
  --sdk_root=$HOME/Android/Sdk --licenses

# 安装必要组件
~/Android/Sdk/cmdline-tools/latest/bin/sdkmanager \
  --sdk_root=$HOME/Android/Sdk \
  "platform-tools" \
  "platforms;android-34" \
  "build-tools;34.0.0"
```

> `platforms;android-34` 是 Flutter 当前使用的目标 SDK 版本。
> 首次 `flutter build` 时 Gradle 会自动补齐缺失的版本（如 android-35）。

### 2.4 配置环境变量

```bash
echo 'export ANDROID_HOME=$HOME/Android/Sdk' >> ~/.zshrc
echo 'export PATH=$PATH:$ANDROID_HOME/platform-tools' >> ~/.zshrc
source ~/.zshrc
```

### 2.5 接受 Flutter 的 Android 许可证

```bash
~/flutter/bin/flutter doctor --android-licenses
```

### 2.6 验证

```bash
~/flutter/bin/flutter doctor
```

输出应包含：`[✓] Android toolchain - develop for Android devices`

---

## 三、构建 APK

### 3.1 Debug APK（开发测试用，≈80MB）

```bash
cd ~/ArkLores
export ANDROID_HOME=$HOME/Android/Sdk
~/flutter/bin/flutter build apk --debug
```

产物：`build/app/outputs/flutter-apk/app-debug.apk`

### 3.2 Release APK（正式使用，更小更快）

```bash
~/flutter/bin/flutter build apk --release
```

产物：`build/app/outputs/flutter-apk/app-release.apk`

> Release 包需要配置签名密钥。debug 包使用自动生成的 debug keystore，
> 无需额外配置即可安装。

---

## 四、安装到手机

### 方式 A：USB 数据线 + adb（推荐）

```bash
# 1. 手机开启「开发者选项」→「USB 调试」
# 2. 连接数据线，手机上同意调试授权
# 3. 检查设备
$ANDROID_HOME/platform-tools/adb devices
# 4. 安装
$ANDROID_HOME/platform-tools/adb install build/app/outputs/flutter-apk/app-debug.apk
```

### 方式 B：文件传输手动安装

1. 将 APK 传到手机（微信 / 数据线 / 网盘）
2. 手机文件管理器中点击 APK 文件
3. 允许「安装未知来源应用」

---

## 五、常见问题

### Q：构建报错 `JdkImageTransform` / AGP 相关

**原因**：Java 21 + Android Gradle Plugin < 8.2.1 不兼容

**解决**：升级 `android/settings.gradle` 中的 AGP 版本：

```gradle
plugins {
    id "com.android.application" version "8.2.2" apply false  // ≥ 8.2.1
    id "org.jetbrains.kotlin.android" version "1.9.24" apply false
}
```

### Q：`flutter doctor` 找不到 Android SDK

**原因**：`ANDROID_HOME` 环境变量未设置

**解决**：

```bash
echo 'export ANDROID_HOME=$HOME/Android/Sdk' >> ~/.zshrc
source ~/.zshrc
```

### Q：adb 找不到设备

**原因**：未开启 USB 调试或缺少 udev 规则

**解决**：

```bash
# 列出 USB 设备，找到手机的 vendor id
lsusb
# 创建 udev 规则（以 Google 设备为例）
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666"' | \
  sudo tee /etc/udev/rules.d/51-android.rules
sudo udevadm control --reload-rules
# 重新插拔数据线
```

---

## 六、参考

- [Flutter Android 安装文档](https://docs.flutter.dev/get-started/install/linux/android)
- [Android Studio 命令行工具](https://developer.android.com/studio/command-line)

# ArkLores Android 配置、构建与安装

本文适用于 ArkLores v0.8 开发与发布验收。当前工程版本来自 `pubspec.yaml`，Android 工程使用
API 36 编译，主知识源是单独下载的中文 GameData DB。

## 快速开始

推荐先检查环境，再使用脚本构建和安装：

```bash
/home/hhikr/flutter/bin/flutter doctor
./tools/setup.sh -a build,install -p android -m debug
```

`adb install -r` 会保留已安装 App 的数据。无参数运行 `./tools/setup.sh` 时，交互向导的
默认动作也是 `build + install`。只有需要 clean install 时才明确选择 `uninstall`；卸载会
删除 App 数据、已安装 GameData 和本地会话。

常用命令：

| 命令 | 用途 |
| --- | --- |
| `./tools/setup.sh` | 交互式构建/安装向导，默认保留 App 数据 |
| `./tools/setup.sh -a build -p android -m debug` | 仅构建 debug APK |
| `./tools/setup.sh -a build,install -p android -m debug` | 构建并覆盖安装 debug APK |
| `./tools/setup.sh -a uninstall,build,install -p android -m debug` | 明确执行 clean install |
| `./tools/setup.sh -a build -p android -m release` | 构建本地 release-mode 验收包 |
| `./tools/setup.sh --dry-run ...` | 只校验和显示参数，不检查环境或执行动作 |

APK 产物：

```text
build/app/outputs/flutter-apk/app-debug.apk
build/app/outputs/flutter-apk/app-release.apk
```

## 环境要求

| 组件 | 当前要求 | 检查方式 |
| --- | --- | --- |
| Flutter | 项目支持的 Flutter / Dart SDK | `flutter --version` |
| Java | JDK 17 或更新版本 | `java -version` |
| Android SDK | platform 36、build-tools 34.0.0、platform-tools | `sdkmanager --list_installed` |
| Android 设备 | 已开启 USB 调试并授权 | `adb devices` |

默认路径：

```text
FLUTTER_HOME=$HOME/flutter
ANDROID_HOME=$HOME/Android/Sdk
```

可通过同名环境变量覆盖。脚本在缺少 SDK 时会安装 command-line tools；已有 SDK 也会
检查并补齐 API 36 和当前已验证的 build-tools 34.0.0。

手动安装 SDK 组件：

```bash
$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager \
  --sdk_root="$ANDROID_HOME" \
  "platform-tools" \
  "platforms;android-36" \
  "build-tools;34.0.0"

/home/hhikr/flutter/bin/flutter doctor --android-licenses
```

## GameData 真机测试

App 不内置数据库。构建时通过以下参数配置可下载的 `.db.gz`：

```text
ARKLORES_GAMEDATA_DB_URL
ARKLORES_GAMEDATA_DB_SHA256
```

### 从本地 GameData 源构建

连接并授权 Android 设备后运行：

```bash
./tools/setup.sh \
  -a build,install \
  -p android \
  -m debug \
  --with-gamedata \
  --gamedata-source=/path/to/ArknightsGameData
```

脚本会构建并压缩 DB、计算 SHA256、启动临时 HTTP 服务，并优先配置：

```text
adb reverse tcp:8765 tcp:8765
```

此时注入 App 的 `http://127.0.0.1:8765/...` 通过 USB 转发访问开发机，而不是直接访问
手机本身。若不使用 adb reverse，添加 `--no-adb-reverse`，脚本会尝试使用局域网地址；
手机和电脑必须位于可互访网络。

`--gamedata-story-limit=N` 只适合快速 schema/smoke DB，不得用来代替完整 DB 检索验收。

### 使用本机已有下载资产

若 `.db.gz` 已由当前 builder 完整构建，可直接复用，不再次解析 GameData source：

```bash
./tools/setup.sh \
  -a build,install \
  -p android \
  -m debug \
  --gamedata-asset=build/gamedata_mobile/arklores_gamedata_zh.db.gz
```

交互向导的 GameData 第 2 项提供相同行为。脚本会执行 gzip 完整性检查、计算 SHA256、
启动临时 HTTP 服务、确认目标文件可通过本地 HTTP 访问并配置 adb reverse，但不会调用
`build_gamedata_database.dart`。App 安装器仍会在下载后校验 GameData schema version 和
必需表。

### 使用已有远程下载资产

推荐使用手机可访问的 HTTPS URL，并必须提供压缩文件 SHA256：

```bash
./tools/setup.sh \
  -a build,install \
  -p android \
  -m debug \
  --gamedata-url=https://example.invalid/arklores_gamedata_zh.db.gz \
  --gamedata-sha=<64位十六进制SHA256>
```

若 URL 使用 `127.0.0.1` 或 `localhost`，脚本必须检测到已连接设备并成功配置
`adb reverse`，否则会停止，避免生成手机无法下载的包。

仅临时开发且明确接受压缩包未校验风险时可以使用：

```text
--allow-unverified-gamedata
```

该选项不得用于 release 验收、分发或发布资产。

安装后打开：`Settings -> Knowledge Base -> GameData 主知识库 -> 下载/更新`。

## Release 签名边界

当前 `android/app/build.gradle` 的 `release` build type 仍使用 debug signing config。
因此：

- `-m release` 可以生成优化后的本地验收 APK；
- 该 APK 不是正式生产签名包；
- 脚本检测到 debug signing 时会显示警告；
- 正式发布必须另行配置受保护的 release keystore，且不得把 keystore、密码或
  `key.properties` 提交到仓库。

本指南和 `setup.sh` 不执行 tag、GitHub Release、asset 上传或 push。

## 常见问题

### 找不到设备

```bash
$ANDROID_HOME/platform-tools/adb devices
```

状态必须是 `device`。若为 `unauthorized`，解锁手机并确认 USB 调试授权。

### GameData 下载失败

依次检查：

1. URL 是否能从手机访问；localhost 是否已成功配置 adb reverse。
2. 临时 HTTP 服务是否仍在运行。
3. SHA256 是否对应压缩后的 `.db.gz`，而不是解压后的 DB。
4. Android 网络是否允许当前开发 URL；正式验收优先使用 HTTPS。

### 需要保留数据升级

不要选择 `uninstall`。使用：

```bash
./tools/setup.sh -a build,install -p android -m debug
```

### AGP 或 JDK 构建错误

先运行：

```bash
/home/hhikr/flutter/bin/flutter doctor -v
```

工程当前 AGP 和 Gradle 版本以 `android/settings.gradle` 与
`android/gradle/wrapper/gradle-wrapper.properties` 为准，不要仅根据旧教程盲目修改版本。

## 相关文档

- `docs/GAMEDATA_BUILD_PIPELINE.md`
- `docs/RETRIEVAL_QA.md`
- `docs/GIT_GUIDE.md`
- <https://docs.flutter.dev/get-started/install/linux/android>

# Android：构建、试装与发布

## 工具链

Flutter 3.47.5、Gradle 8.14.3、AGP 8.11.1、Kotlin 2.2.20、Java 17，compileSdk 36。

- Windows 开发机：Flutter 在 `C:\src\flutter\bin`；Android SDK 与 JDK 在 `C:\Users\hhikr\dev`（`android-sdk`、`jdk-17`，用
  `flutter config --android-sdk/--jdk-dir` 指定，没有写环境变量；`install_local.ps1` 在缺 `ANDROID_HOME`/`JAVA_HOME` 时自动指向这里）。
- Linux：`/home/hhikr/flutter/bin`；可用 `tools/setup.sh`（交互向导，构建/安装，可起本地 HTTP 服务提供知识库）。
- 云端会话没有 Android SDK（见 `CLOUD_DEV.md`）。
- Flutter 迁移器会往 `android/gradle.properties` 加 `android.builtInKotlin/newDsl=false`；提交前 `git checkout -- android/gradle.properties`。
- 改了 `android/` 下的 Kotlin/清单后，`flutter build apk --debug` 本机编译检查（debug 包不能发布）。

## 本机试装（不经 GitHub）

手机开 USB 调试并连上电脑：

```powershell
.\tools\install_local.ps1 -Build -Kb     # 构建 release APK（release key 签名、烘入 tools/release_gamedata.env 的 URL/SHA）、安装、拷知识库
.\tools\install_local.ps1                # 只安装最新的本地 APK
.\tools\install_local.ps1 -Kb -KbOnly    # 只拷知识库
.\tools\install_local.ps1 -DryRun
```

知识库 `build\gamedata_v5\arklores_gamedata_zh.db.gz` 被拷成应用目录里的 `arklores_gamedata_zh.db.download.gz`；打开 设置 → 知识库，
点“下载”即离线校验 SHA 并安装。**APK 必须是用这个 gz 的 SHA 构建的**（改了知识库就先改 `release_gamedata.env` 再 `-Build`）。

签名：`tools/arklores-release.jks` + `tools/android_signing.properties`（gitignored，绝不提交、绝不打印）。没有它们时本地
`flutter build apk --release` 会退回 debug key，这样的包不能覆盖安装正式版、也不能发布。

## 真机问答调试（0.14，`tools/phone_ask.dart`）

在电脑上向手机里的 App 提问，App 把界面上显示的内容实时传回终端：工作过程每一步（工具与参数、找到了什么、失败原因、子助手）、
思考、状态行（等待服务商等）、答案文字（替换/重写也标出来）、最后的状态与用量。不是界面的逐像素还原，是大致的文字。

```powershell
.\tools\install_local.ps1 -Build -Bridge      # 带桥构建并安装（只用于本机测试，发布的包里没有桥）
dart run tools/phone_ask.dart "问题"           # 提问并等答案
dart run tools/phone_ask.dart -i "问题"        # 答完后在终端里接着追问
dart run tools/phone_ask.dart                  # 只看：手机上手动提的问题也实时显示
dart run tools/phone_ask.dart --new --wiki=off --full "问题"   # 新对话、关 Wiki、打印工具的完整输出
```

- 原理：`--dart-define=ARKLORES_PHONE_BRIDGE=true` 的 App 每 3 秒尝试连接手机上的 `ws://127.0.0.1:47321`；`phone_ask.dart` 运行
  `adb reverse tcp:47321 tcp:47321` 并在电脑上监听，所以连接只经 USB 到达这台电脑，手机上不开端口。代码在 `lib/features/ai/phone_bridge.dart`。
- 问题像在输入框里输入一样提出（App 切到问答页），之后的追问沿用同一对话；`--wiki/--review/--digest/--delegate/--think=on|off` 改的是 App 里的回答选项（会保存）。
- 终端显示同时写入 `build/phone_sessions/<时间>.log`（文字）与 `.jsonl`（事件）；App 开着“保存 AI 对话记录”时，每题答完把会话文件
  （`conversation_<id>.json`）从手机拉到同一目录。
- Ctrl+C 一次取消当前问题，两次退出。App 被切到后台时系统可能暂停连接，回到前台会自动重连（问答本身在前台服务里继续）。
- 没有手机时 `--no-adb` 连本机运行的 App（例如 `flutter run -d windows --dart-define=ARKLORES_PHONE_BRIDGE=true`）。

## 发布（开发者明确同意后）

1. 改 `pubspec.yaml` 版本（Android build 号递增，v0.13.0 正式版是 32）与 `lib/shared/app_version.dart`，更新 CHANGELOG 与文档。
2. 知识库有变化：按 `GAMEDATA_BUILD_PIPELINE.md` §7 准备资产，`tools/release_gamedata.env` 指向将要创建的 Release。
3. 工作区干净（`coverage/` 已 gitignore），提交并推送功能分支。
4. `.\tools\release_app.ps1 -Version <v> -NotesFile <说明.md> [-Stable]`（Linux/云端：`tools/release_app.sh`，`STABLE=1`）：
   推 `release/v<v>` → `android-release.yml` 构建签名并校验证书指纹 `b1b09ebf…e364` → 下载 APK → 建 Release 并上传 APK。
5. 上传两个知识库的 gz 与 manifest 到同一个 Release（知识库没变也照传，一个 Release 带齐 APK、两个知识库和源码）；用公开地址 HEAD 一次确认 200。
6. 开 PR 把功能分支合回 `main`（开发者合并）；合并后删掉功能分支；撤下被正式版取代的预发布（Release 与 tag）；删掉 `release/v<v>` 分支（tag 指向同一提交）。

建 Release 的请求失败（v0.11.0 遇到 GitHub 500）时：APK 已在 `%TEMP%\arklores_release_<v>`，用 REST 补建 Release 并上传，不要重推 release 分支
（重推会重新构建，APK 哈希会变）。

## 常见问题

- 找不到设备：`adb devices` 状态要是 `device`；`unauthorized` 时在手机上确认授权。
- 知识库下载卡住：用 Release 页面手动下载 gz，改名为 `arklores_gamedata_zh.db.download.gz` 放进应用目录，再点“下载”。
- 磁盘：C 盘满时 `flutter test` 编译失败后会卡住很久；全量测试正常约 1 分钟，明显变慢先查剩余空间。

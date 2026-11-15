# 开发

ArkLores 是一个 Flutter 应用，只发布 Android 版。这篇写怎么在本机跑起来，以及用了哪些技术，代码放在哪里。提交规范见 [CONTRIBUTING.md](../CONTRIBUTING.md)。

## 跑起来

```bash
flutter pub get
flutter test --concurrency=2 --exclude-tags live
flutter analyze
flutter run
```

- `test/live/` 下是联网和调用真实模型的测试，默认不编译，会产生费用。运行方法见 [QA_CHECKLIST.md](QA_CHECKLIST.md)。
- 本机构建、试装与发布见 [ANDROID_SETUP_GUIDE.md](ANDROID_SETUP_GUIDE.md)，云端开发环境见 [CLOUD_DEV.md](CLOUD_DEV.md)。
- 本地 `flutter build apk --release` 没有签名文件时用 debug key 签名，不能用来发布。正式安装包由 GitHub Actions 构建签名。

## 技术栈

| 类别 | 选型 |
| --- | --- |
| 框架 | Flutter / Dart，Riverpod |
| 数据库 | SQLite（sqflite；建库和只读 SQL 用 FFI） |
| 知识库 | 每个游戏一个库：条目层、剧情原文与资料、可选的剧情向量 |
| AI | OpenAI 兼容的 Chat / Embedding API |
| 发布 | GitHub Actions 构建签名 APK；知识库由服务器上的脚本自动更新 |

## 目录

```text
lib/
  core/
    agent/      问答 Agent（LoreAgentLoop）、工具（tools/ 下是检索、年表与 Wiki 工具）、提示词
    gamedata/   知识库的安装与检索（两个游戏合成一个检索面）；build/ 是建库代码
    library/    资料页的查询
    userdata/   用户库（阅读历史、个人资料）
    llm/        Chat / Embedding 客户端
    wiki/       PRTS / Warfarin 的请求、页面段落、缓存与快照
    background/ 长时操作的前台服务保活
  features/     ai、library（资料页与阅读器）、materials、settings、wiki
  shared/       主题、界面语言（l10n/）、状态、共用部件
tools/          建库、更新、向量、终末地解包、发布脚本；kb_bot/ 是服务器上的自动更新
docs/           文档
test/           与 lib/ 一一对应的测试（见 test/README.md）
```

各模块怎么实现，从 [ARCHITECTURE.md](ARCHITECTURE.md) 开始读。

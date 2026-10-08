# ArkLores

> 明日方舟剧情阅读与问答助手（Arknights lore reader & assistant）

ArkLores 是一款面向《明日方舟》与《明日方舟：终末地》剧情爱好者的 Android 应用（Flutter）。它把游戏解包文本整理成本地知识库（每个游戏一个），
在上面提供可以阅读的资料页和带原文出处的剧情问答，并内置 PRTS 与终末地 Wiki 的浏览。

最新版本：[v0.11.0](https://github.com/hhikr/ArkLores/releases/tag/v0.11.0)

## 功能

- **资料**：书架（主线、SideStory、故事集、插曲、干员、集成战略、生息演算、图鉴）→ 故事集（章节、官方梗概、阅读进度）→ 条目
  （剧情、关卡、敌人、物品、奖章、肉鸽事件……），条目之间按游戏表里的关系互相链接；每页可搜索。阅读器记住位置与读过的次数。
  “我的资料”保存自己的笔记，只在本机。
- **问答**：一个工具型 AI Agent 直接查询本地知识库（只读 SQL、全库检索、整章阅读，可派出并行子 agent），答案每条都带可点开的原文出处；
  工作过程显示为时间线。支持任意 OpenAI 兼容的模型服务（默认智谱 `glm-5.3-flash`），可选配置向量服务做语义召回。
- **Wiki**：PRTS 与终末地 Wiki（fz.wiki / Warfarin）双站浏览、阅读模式、书签。
- **知识库更新**：从 Release 下载整包，或在 App 内检查上游变化、只下载变化的文件做增量更新。
- **终末地（0.12 开发中）**：第二个知识库——干员档案与语音、档案库文件、任务对话与通讯、短信，按游戏的任务分类排在资料页；问答会判断问题属于哪个游戏，看不出来时两个都查。

## 发布资产（v0.11.0 Release）

- `ArkLores-0.11.0.apk`：项目签名，可覆盖安装 v0.10.0 及之后的版本（从 v0.9 及更早版本升级需先卸载一次）。
- `arklores_gamedata_zh.db.gz`：知识库（schema 5，含剧情向量与故事目录，约 200 MB），SHA-256
  `695caa3e0e598ce92e7d588973bb6c00b3d6345171003c9532df16babf3eb0ec`。在 App 的 设置 → 知识库 中下载。
- `gamedata_manifest.json`：来源提交、计数、大小与哈希。

## 开发

```bash
flutter pub get
flutter test
flutter analyze
flutter run
```

本机构建、试装与发布见 [`docs/ANDROID_SETUP_GUIDE.md`](docs/ANDROID_SETUP_GUIDE.md)；开发约定见 [`CLAUDE.md`](CLAUDE.md) 与 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

| 类别 | 选型 |
| --- | --- |
| 框架 | Flutter / Dart，Riverpod |
| 数据库 | SQLite（sqflite；构建与只读 SQL 用 FFI） |
| 知识库 | 中文 GameData 条目层 + 全文/覆盖层 + 可选剧情向量 |
| AI | OpenAI 兼容 Chat / Embedding API |

```text
lib/
  core/
    agent/      问答 Agent（LoreAgentLoop）、工具、提示词
    gamedata/   知识库安装、检索；build/ 是建库代码（桌面与 App 共用）
    library/    资料页的查询
    userdata/   用户库（阅读历史、我的资料）
    llm/        Chat / Embedding 客户端
  features/     ai、library（资料页与阅读器）、materials、settings、wiki
  shared/       主题与共用组件（悬浮栏、按压反馈…）
tools/          建库、更新、补算、向量、发布脚本
docs/           文档（索引见 CLAUDE.md）
```

## 文档

- [`docs/AI_ARCHITECTURE.md`](docs/AI_ARCHITECTURE.md)、[`docs/R17_TOOL_AGENT.md`](docs/R17_TOOL_AGENT.md)：问答 Agent。
- [`docs/GAMEDATA_BUILD_PIPELINE.md`](docs/GAMEDATA_BUILD_PIPELINE.md)：知识库构建、更新、发布；
  [`docs/KNOWLEDGE_BASE_LESSONS.md`](docs/KNOWLEDGE_BASE_LESSONS.md)：建库经验与教训。
- [`docs/KNOWN_LIMITATIONS_AND_DEBT.md`](docs/KNOWN_LIMITATIONS_AND_DEBT.md)：已知限制。

数据来自社区解包仓库 [Kengxxiao/ArknightsGameData](https://github.com/Kengxxiao/ArknightsGameData)。游戏内容版权归 Hypergryph 所有。

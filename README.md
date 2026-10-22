# ArkLores

> 明日方舟剧情阅读与问答助手（Arknights lore reader & assistant）

ArkLores 是一款面向《明日方舟》与《明日方舟：终末地》剧情爱好者的 Android 应用（Flutter）。它把游戏解包文本整理成本地知识库（每个游戏一个），
在上面提供可以阅读的资料页和带原文出处的剧情问答，并内置 PRTS 与终末地 Wiki 的浏览。

最新版本：[v0.16.0](https://github.com/hhikr/ArkLores/releases/tag/v0.16.0)

## 功能

- **资料**：每个游戏一页（明日方舟 / 终末地 / 我的资料，点标签切换）。书架（明日方舟：主线、SideStory、故事集、插曲、干员、集成战略、生息演算、图鉴；
  终末地：照游戏任务面板的主线 / 探索 / 支线 / 活动 / 委派任务、情报档案库、干员、百科）→ 故事集或任务（章节、官方梗概、阅读进度）→ 条目，
  条目之间按游戏表里的关系互相链接；每页可搜索。长文用阅读字体排版（默认黑体，可在设置里换成霞鹜文楷），干员档案分段可折叠，剧情开头的官方梗概默认折叠；阅读器记住位置与读过的次数。
  “我的资料”保存自己的笔记，只在本机。
- **问答**：一个工具型 AI Agent 直接查询本地知识库（统一检索、整章阅读、只读 SQL），答案每条都带可点开的原文出处，出处由代码核对是否真的读过；
  一次检索同时查两个游戏的剧情、档案等资料和 PRTS / Warfarin Wiki（游戏原文优先，只有 Wiki 支持的说法会写明；可在输入框的选项里关闭）。
  答完之后可以点“提要”把长答案整理成几段，或点“复核”让另一次调用以读者身份提问。工作过程逐步列出每次查找的工具、参数和结果。
  支持任意 OpenAI 兼容的模型服务（默认智谱 `glm-5.3-flash`），可选配置向量服务做语义检索（没有时退回关键词并提示）。
- **终末地**（0.12）：第二个知识库——干员档案、语音记录与干员情报，情报档案库，敌人、武器、物品描述，以及全部剧情对话与过场台词
  （一个任务一篇，按任务步骤排列：每段放在游戏播放它的那一步，步骤目标作标题）；
  主线按章、进程排列，干员的角色纪事、Baker 话题、帝江号互动在干员页上。问答每次两个游戏都查。
- **Wiki**：PRTS 与终末地 Wiki（fz.wiki / Warfarin）双站浏览、书签；深色模式用站点自己的主题。
- **知识库更新**：从 Release 下载整包；明日方舟库还可以在 App 内检查上游变化、只下载变化的文件做增量更新。两者按游戏数据的新旧排先后：数据较新的在前，同一份数据时官方库在前。

## 发布资产

- [v0.16.0](https://github.com/hhikr/ArkLores/releases/tag/v0.16.0)：`ArkLores-0.16.0.apk`（项目签名，可覆盖安装 v0.10.0 及之后的版本；从 v0.9 及更早版本升级需先卸载一次）；
  `arklores_gamedata_zh.db.gz`：明日方舟知识库（约 119 MB，与 v0.15.x 同一份），SHA-256 `1b9e3505cf10eb6b852fcbacfa412fd312a31e85986333d2e6d1cbcf7be8d004`；
  `arklores_endfield_zh.db.gz`：终末地知识库（约 16 MB，2026-10-18 客户端，按任务步骤排列，含过场台词与段首梗概），SHA-256 `fc34c31aaa531555e09c19f700ca7dc6a987a470af634cecaa8f9e32fdefb965`；
  `gamedata_manifest.json`、`endfield_manifest.json`。新的终末地库要 v0.16.0 的 App。App 不会提示新版本，要自己来 Release 页下载 APK；知识库在 设置 → 知识库 里更新。
- 更早的版本与知识库见 [Releases](https://github.com/hhikr/ArkLores/releases) 与 [`CHANGELOG.md`](CHANGELOG.md)。
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
| 知识库 | 每个游戏一个库：中文条目层 + 剧情原文与资料 + 可选向量 |
| AI | OpenAI 兼容 Chat / Embedding API |

```text
lib/
  core/
    agent/      问答 Agent（LoreAgentLoop）、工具（含 tools/ 下的检索与 Wiki 工具）、提示词
    gamedata/   知识库安装、检索（两个游戏合成一个检索面）；build/ 是建库代码（明日方舟桌面与 App 共用，build/endfield/ 是终末地）
    library/    资料页的查询与标签
    userdata/   用户库（阅读历史、我的资料）
    llm/        Chat / Embedding 客户端
    wiki/       PRTS / Warfarin 的请求、页面段落、缓存与快照
    background/ 长时操作的前台服务保活
  features/     ai、library（资料页与阅读器）、materials、settings、wiki
  shared/       主题（theme/）、界面语言（l10n/）、状态（providers/）、共用组件（widgets/：页面框架、按钮与列表行等部件，见 docs/DESIGN.md）
tools/          建库、更新、补算、向量、终末地解包、发布脚本
docs/           文档（索引见 CLAUDE.md）
```

## 文档

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)：项目结构与各模块的实现方式。
- [`docs/ASK_AGENT.md`](docs/ASK_AGENT.md)：问答 Agent 现在怎么工作；[`docs/ASK_EXPERIMENTS.md`](docs/ASK_EXPERIMENTS.md)：问答试过的办法、实测表现与评估；
  [`docs/WIKI.md`](docs/WIKI.md)：Wiki 浏览与问答取证。
- [`docs/GAMEDATA_BUILD_PIPELINE.md`](docs/GAMEDATA_BUILD_PIPELINE.md)：两个知识库的构建、更新、发布；
  [`docs/KNOWLEDGE_BASE_LESSONS.md`](docs/KNOWLEDGE_BASE_LESSONS.md)：建库经验与教训；
  [`docs/ENDFIELD_STORY_ORDER.md`](docs/ENDFIELD_STORY_ORDER.md)：终末地剧情怎么按任务步骤排列。
- [`docs/KNOWN_ISSUES.md`](docs/KNOWN_ISSUES.md)：已知问题。
- [`CHANGELOG.md`](CHANGELOG.md)：各版本的变化。

明日方舟的数据来自社区解包仓库 [Kengxxiao/ArknightsGameData](https://github.com/Kengxxiao/ArknightsGameData)；终末地的数据从本机安装的游戏客户端解包
（[Variante/endfield_research_kit](https://github.com/Variante/endfield_research_kit) 的 AnimeStudio）。游戏内容版权归 Hypergryph 所有。

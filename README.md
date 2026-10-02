# ArkLores

> Arknights AI-enhanced reading companion - 明日方舟剧情智能助手

ArkLores 是一款面向《明日方舟》与《明日方舟：终末地》剧情爱好者的 Flutter 应用。
当前版本 v0.11.0 使用中文 GameData release asset 作为主知识源，提供带行级原文引用的
剧情问答与调查、梗概、事实核查、证据约束的角色扮演，以及 Wiki 阅读上下文转交到 AI workflow；
可选的剧情向量召回需要在设置中配置向量 API。

Latest release: [v0.10.0](https://github.com/hhikr/ArkLores/releases/tag/v0.10.0)

## 当前方向

- 中文 GameData 结构化知识库是主知识源。
- App 通过 GitHub Release asset 或开发期临时 URL 下载 `arklores_gamedata_zh.db.gz`。
- 检索使用 SQLite 结构化表、别名表、精确匹配、LIKE、FTS 和确定性剧情覆盖层；
  配置向量 API 后，剧情原文检索额外使用语义召回（只作定位线索，答案引用必须来自已读原文）。
- Wiki 只作为浏览与人工补充材料，不再作为 Agent 主检索路径。
- 用户导入资料功能暂缓，后续需重新设计为低可信来源。
- AI 设置包含 Chat API 与可选的向量 API 配置。
- Fact-check 对剧情命题使用 scope、实体和关系词交集检索；确定结论必须有直接 GameData
  evidence，证据不足时明确返回存疑或无法确认。
- Role-play 先解析 canonical character 和稳定 `entity_id`，只使用 GameData 检索作为角色事实依据；
  用户场景和生成对白不会被标记为官方游戏原文。
- Wiki 可将选中文字、页面标题和 URL 显式转交给 Summary / Fact-check；这些内容只作为
  用户阅读上下文，事实声明仍必须由 GameData 独立核验。

## 发布资产

v0.11.0 GitHub Release 包含：

- `ArkLores-0.11.0.apk`：Android release 包，使用项目签名密钥（可直接覆盖 v0.10.0；从 v0.9 及更早版本升级需先卸载一次）。
- `arklores_gamedata_zh.db.gz`：schema 4 中文 GameData DB（含可选剧情向量表与故事目录表），SHA-256
  `922e1a8159b7e097f2b0978cc895b7012c17009f0c91f15b98d384dd3b2e4bfa`。
- `gamedata_manifest.json`：来源、计数、大小、hash、向量与故事目录元数据。

## 开始使用

```bash
/home/hhikr/flutter/bin/flutter pub get
/home/hhikr/flutter/bin/flutter run
```

开发期真机测试 GameData 下载可通过：

```bash
/home/hhikr/flutter/bin/flutter run \
  --dart-define=ARKLORES_GAMEDATA_DB_URL=http://<host>:<port>/arklores_gamedata_zh.db.gz \
  --dart-define=ARKLORES_GAMEDATA_DB_SHA256=<compressed-db-sha256>
```

真机使用 localhost 时还需要 `adb reverse`；推荐直接使用下方 `tools/setup.sh`，详见
[`docs/ANDROID_SETUP_GUIDE.md`](docs/ANDROID_SETUP_GUIDE.md)。

也可以用统一安装向导从 GameData source 重建，或直接复用已有 `.db.gz`：

```bash
./tools/setup.sh
```

## 技术栈

| 类别 | 选型 |
| --- | --- |
| 框架 | Flutter / Dart |
| 状态管理 | Riverpod |
| 数据库 | SQLite / sqflite |
| 主知识库 | 中文 GameData 结构化 DB + FTS + 剧情覆盖层 + 可选向量 |
| AI 接入 | OpenAI-compatible Chat / Embedding API |
| Agent | Ask（auto / 调查 / 梗概 / 核查）+ Role-play；调查走 PlannerLoop，其余走 ReAct Loop |

## 项目结构

```text
lib/
  core/
    agent/       Agent、ReAct Loop、工具抽象
    gamedata/    GameData 安装、状态、结构化检索
    llm/         Chat API client
    rag/         非模型相关文本分块工具
    wiki/        Wiki 浏览/爬虫历史模块
  features/
    ai/
    materials/   当前为暂停态
    settings/
    wiki/
tools/
  build_gamedata_database.dart
docs/
```

AI 与检索架构见 [`docs/AI_ARCHITECTURE.md`](docs/AI_ARCHITECTURE.md)，
v0.9 运行原理快照见 [`docs/ARKLORES_V0.9_TECHNICAL_REPORT.md`](docs/ARKLORES_V0.9_TECHNICAL_REPORT.md)，
当前路线与跨版本约束见 [`docs/implementation_plan.md`](docs/implementation_plan.md)，
已知限制与技术债根因分析见 [`docs/KNOWN_LIMITATIONS_AND_DEBT.md`](docs/KNOWN_LIMITATIONS_AND_DEBT.md)。

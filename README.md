# ArkLores

> Arknights AI-enhanced reading companion - 明日方舟剧情智能助手

ArkLores 是一款面向《明日方舟》与《明日方舟：终末地》剧情爱好者的 Flutter 应用。当前 v0.4.5 主线已转向中文 GameData release asset 作为主知识源。

## 当前方向

- 中文 GameData 结构化知识库是主知识源。
- App 通过 GitHub Release asset 或开发期临时 URL 下载 `arklores_gamedata_zh.db.gz`。
- 检索使用 SQLite 结构化表、别名表、精确匹配、LIKE 和 FTS。
- Wiki 只作为浏览与人工补充材料，不再作为 Agent 主检索路径。
- 用户导入资料功能暂缓，后续需重新设计为低可信来源。
- AI 设置只保留 Chat API 配置。

## 开始使用

```bash
flutter pub get
flutter run
```

开发期真机测试 GameData 下载可通过：

```bash
flutter run \
  --dart-define=ARKLORES_GAMEDATA_DB_URL=http://<host>:<port>/arklores_gamedata_zh.db.gz
```

## 技术栈

| 类别 | 选型 |
| --- | --- |
| 框架 | Flutter / Dart |
| 状态管理 | Riverpod |
| 数据库 | SQLite / sqflite |
| 主知识库 | 中文 GameData 结构化 DB + FTS |
| AI 接入 | OpenAI-compatible Chat API |
| Agent | Dart ReAct Loop + `search_local_lore` |

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

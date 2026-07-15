# ArkLores Developer Notes

当前主线：中文 GameData release asset + SQLite structured retrieval + FTS。
当前开发版本：v0.8.0（未发布）；最新 release：v0.7.0；GameData schema：2。

## Do

- 使用 `/home/hhikr/flutter/bin/flutter`。
- 保护 `logs/`。
- 保持 GameData 为 Agent 主知识源。
- 保留 source path、raw id、content type、entity id。
- 默认 Agent 只使用 `search_local_lore`；Wiki 和用户文本只能作为浏览/上下文。
- 运行相关 tests / analyze 后再汇报。

## Do Not

- 不恢复旧 Wiki seed 运行链路。
- 不恢复旧用户资料索引链路。
- 不提交 API key、token、`.env`。
- 不直接 push `main` 或 `dev`。

## Useful Commands

```bash
/home/hhikr/flutter/bin/flutter test test/agent_test.dart
/home/hhikr/flutter/bin/flutter test
/home/hhikr/flutter/bin/flutter analyze
/home/hhikr/flutter/bin/dart run tools/build_gamedata_database.dart --help
HOME=/tmp /home/hhikr/flutter/bin/dart run tools/check_gamedata_retrieval.dart \
  --db=build/gamedata_mobile/arklores_gamedata_zh.db
```

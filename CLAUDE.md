# ArkLores Developer Notes

当前主线：中文 GameData release asset + SQLite structured retrieval + FTS。

## Do

- 使用 `/home/hhikr/flutter/bin/flutter`。
- 保护 `logs/`。
- 保持 GameData 为 Agent 主知识源。
- 保留 source path、raw id、content type、entity id。
- 运行相关 tests / analyze 后再汇报。

## Do Not

- 不恢复旧 Wiki seed 运行链路。
- 不恢复旧用户资料索引链路。
- 不提交 API key、token、`.env`。
- 不直接 push `main` 或 `dev`。

## Useful Commands

```bash
/home/hhikr/flutter/bin/flutter test test/agent_test.dart
/home/hhikr/flutter/bin/dart analyze lib test tools
/home/hhikr/flutter/bin/dart run tools/build_gamedata_database.dart --help
```

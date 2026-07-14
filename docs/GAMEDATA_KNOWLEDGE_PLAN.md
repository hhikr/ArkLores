# GameData Knowledge Plan

## Architecture Decision

v0.4.5 的主知识源是中文 GameData release asset。

可信度优先级：

1. GameData / 游戏原始文本
2. 指定 Wiki
3. 用户导入 Book

当前 App 主线只实现 GameData 本地结构化检索。Wiki 与 Book 不作为默认 Agent 检索路径。

## Distribution

GameData DB 由开发机离线构建，压缩为：

```text
arklores_gamedata_zh.db.gz
```

正式发布时与 APK 一起放入 GitHub Release。开发期可使用：

```text
--dart-define=ARKLORES_GAMEDATA_DB_URL=<url>
```

## Schema

- `gamedata_manifest`
- `entities`
- `entity_aliases`
- `entity_documents`
- `normalized_records`
- `story_lines`
- `lore_chunks`
- `entity_documents_fts`
- `lore_chunks_fts`

## Retrieval

`search_local_lore` 的顺序：

1. entity exact / alias lookup
2. entity document exact / LIKE
3. entity document FTS
4. lore chunk FTS
5. normalized record / lore chunk LIKE fallback

每条 observation 必须带：

- source kind
- source type
- retrieval type
- content type
- entity id
- title / section
- source path
- raw id
- trust hint

## Agent Mapping

| Tool | Source | Status |
| --- | --- | --- |
| `search_local_lore` | GameData structured DB | v0.4.5 主工具 |
| online Wiki browsing | Wiki WebView | 人工浏览与补充 |
| Book import | 用户资料 | 暂停，后续重新设计 |

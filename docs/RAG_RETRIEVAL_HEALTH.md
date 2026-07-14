# RAG Retrieval Health

v0.4.5 的检索健康标准只覆盖中文 GameData 结构化知识库。

## 检索顺序

1. 实体与别名精确匹配。
2. `entity_documents` 精确或 LIKE 匹配。
3. `entity_documents_fts`。
4. `lore_chunks_fts`。
5. `normalized_records` 与 `lore_chunks` LIKE fallback。

## 健康标准

- 已安装 `arklores_gamedata_zh.db`。
- `gamedata_manifest` 可读。
- `entities`、`entity_aliases`、`entity_documents`、`normalized_records`、`lore_chunks` 表存在。
- FTS 表存在并可返回中文查询结果。
- 空库、无结果、低置信结果必须向用户说明限制。

## 固定 smoke queries

- 阿米娅
- 莱茵生命
- 萨卡兹
- 罗德岛
- 源石技艺

这些查询应至少命中结构化实体、文档片段或原始记录之一。

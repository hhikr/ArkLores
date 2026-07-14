# RAG Stabilization Plan

v0.4.5 RAG 稳定化采用非模型结构化检索路线。

## Phase 1: FTS Search

- GameData build 生成实体、别名、文档、原始记录、剧情行、片段。
- SQLite FTS 覆盖 `entity_documents` 与 `lore_chunks`。
- App 检索优先实体与别名，再走 FTS 和 LIKE fallback。

## Phase 2: Structured RAG Refactor

- 删除旧 Wiki seed 运行路径。
- 删除旧用户资料索引链路。
- Summary Agent 只调用 `search_local_lore`。
- Observation 必须包含 source kind、source path、content type、raw id。
- 无库、无结果、低覆盖时给出可理解提示。

## Phase 3: Entity Disambiguation

Status: implemented in v0.4.5 structured RAG.

- `GameDataKnowledgeStore.findEntityCandidates()` reads `entities` and `entity_aliases`.
- `search_local_lore` detects multiple exact entity candidates when no `entity_id` is supplied.
- Ambiguous queries return candidate cards with `entity_id`, name, entity type, matched alias, match type, confidence, source type, and source path.
- Agent prompt requires the model to ask the user to choose a candidate, or call `search_local_lore` again with the chosen `entity_id`.

## Phase 4: Ranking

Status: implemented for GameData-only retrieval.

Ranking priority:

1. Entity document exact match.
2. Exact structured entity match.
3. Summary story context.
4. Structured entity chunks.
5. Structured raw records.
6. Entity document FTS.
7. Entity document LIKE.
8. Lore chunk FTS.
9. Record/chunk LIKE fallback.

`search_local_lore` now prints `Ranking Reason` for each result so Agent observations explain why an item was ranked.

GameData is the only active Agent source in v0.4.5. Wiki and Book are not active retrieval sources, so GameData remains the highest trust source by construction.

## Phase 5: Summary Agent Strategy

Status: implemented in tool contract and prompt.

- `search_local_lore` accepts `search_mode=summary`.
- Summary mode announces its retrieval plan in the observation.
- Summary mode prioritizes entity documents, then story context for the resolved entity, then raw records and FTS fallback.
- Summary Agent prompt tells the model to use `search_mode=summary` first.
- Observation output includes source kind, source type, retrieval type, ranking reason, content type, entity id, story id, source path, raw id, trust note, and truncation note.

## v0.4.5 Hardening

Status: implemented for the current GameData-only MVP.

- Query normalization keeps the original query while adding structured intent:
  - `语音` -> `operator_voice`
  - `档案` -> `operator_handbook_profile`
  - `秘录` -> operator record / story review search aliases
  - `模组` -> operator module / uniequip search aliases
  - `肉鸽` -> `集成战略` search aliases
- Entity-focused queries strip intent words such as `语音`, `档案`, `主线`, and `剧情` before entity lookup, so `阿米娅 语音` can resolve the `阿米娅` entity and then filter voice records.
- GameData installer validates downloaded DB files before replacing the installed DB:
  - required schema tables,
  - manifest `schema_version`,
  - nonzero entity / record / chunk counts.
- Retrieval QA checklist lives in `docs/v0.4.5_RETRIEVAL_QA.md`.

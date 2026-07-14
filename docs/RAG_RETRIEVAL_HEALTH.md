# ArkLores RAG Retrieval Health

This document defines the retrieval safeguards required before a knowledge
database or built-in embedding model is considered usable by ArkLores agents.
v0.4.5 and later use Chinese GameData as the primary knowledge source; v0.3
Wiki seed data remains a prototype / fallback source.

## Retrieval Strategy

ArkLores must not rely on pure vector search for entity queries. The production
search path is hybrid and source-aware:

1. Structured GameData lookup (`entities`, `story_lines`, `lore_chunks`).
2. Exact entity/title/alias match.
3. FTS / keyword match.
4. Vector search as semantic expansion.
5. Restricted Wiki search only as fallback / supplement.

GameData matches outrank Wiki and Book evidence. Title / alias matches outrank
vector-only matches. Vector search is a recall expansion, not the primary truth
source.

## Low-Information Chunks

The search layer filters low-information chunks from vector results. Examples:

- `分类：text`
- very short text fragments
- standalone skill names, such as `- 技能：收割`
- standalone talent names, such as `- 第一天赋：医疗班保护`

These fragments can remain in the database for citation completeness, but they
must not dominate top-K RAG context.

## Built-In Embedding Diagnostics

Run the diagnostic test manually before publishing a seed database or changing
the built-in model:

```bash
/home/hhikr/flutter/bin/flutter test test/builtin_embedding_diagnostics_test.dart --run-skipped
```

Inspect the printed cosine values. If unrelated texts are consistently above
`0.99`, the model or pooling strategy is not suitable for semantic retrieval.

The diagnostic currently checks:

- `阿米娅`
- `凯尔希`
- `罗德岛`
- `龙门`
- `apple banana`
- one Amiya-like lore sentence
- one unrelated Endfield sentence

## GameData Release Acceptance

Before publishing `arklores_gamedata_zh.db.gz`, run a retrieval smoke test
against the generated DB. The minimum required queries are:

- `阿米娅`
- `凯尔希`
- `罗德岛`
- `龙门`
- `第二次卡兹戴尔战争`
- `莱茵生命`
- `缪尔赛思`

Acceptance criteria:

- Entity queries must include the exact or expected entity/title in top 5.
- GameData results must appear before Wiki / Book results when both are present.
- Top-K must not be dominated by low-information chunks.
- Vector score ranges should not collapse around `0.999x` for unrelated queries.
- The manifest must record the embedding runner, model, dimension, and vector
  count.
- Citations must include `source_type` and either `source_path`, `source_url`,
  or story line offsets.

## Model Replacement Guidance

The current built-in model behaves like a weak or non-retrieval sentence model.
Do not tune prompts to compensate for a collapsed embedding space. GameData FTS
and structured lookup should remain usable even if embedding quality is poor.

Candidate replacement models:

- `BAAI/bge-small-zh-v1.5` for Chinese-first Arknights retrieval.
- `multilingual-e5-small` if Chinese/English mixed retrieval becomes more
  important and the tokenizer/runtime cost is acceptable.

Replacement requirements:

- Python seed builder and Flutter runtime must use the same tokenizer,
  pooling, normalization, and prompt prefix rules.
- If the model expects `query:` / `passage:` prefixes, apply them in both seed
  generation and app-side query embedding.
- Rebuild the full release seed DB after any model or pooling change.

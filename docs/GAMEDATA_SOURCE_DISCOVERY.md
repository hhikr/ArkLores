# GameData Source Discovery

GameData 来源调研目标：

- 明确社区解包仓库是否覆盖中文剧情与游戏文本。
- 遍历仓库文件，枚举剧情相关内容。
- 将内容分类到可构建结构化 DB 的 schema 中。
- 保留原文、来源文件路径、raw id、语言、游戏、内容类型和实体关系。

当前构建产物：

- `entities`
- `entity_aliases`
- `entity_documents`
- `normalized_records`
- `story_lines`
- `lore_chunks`
- `entity_documents_fts`
- `lore_chunks_fts`

# ArkLores 检索链路与 GameData 安装链路分析报告

> 事实依据报告（代码级，基于当前 main 分支源码逐行核对）。
> 范围：`lib/core/gamedata/*`、`lib/core/agent/*`、`lib/features/ai/evidence_observation.dart`、
> `lib/features/settings/knowledge_base_page.dart`、`lib/main.dart`、`lib/app.dart`、
> `tools/build_gamedata_database.dart`、`tools/check_gamedata_retrieval.dart`、`pubspec.yaml`。
> 用途：支撑 (a) `docs/AI_RETRIEVAL_OPTIMIZATION.md` P0/P1 落地评估；(b) App 内直接构建剧情数据库评估。

---

## 1. 检索链路全景

### 1.1 入口与预算参数

唯一 Agent 检索工具 `SearchLocalLoreTool`（`lib/core/agent/tools/search_local_lore.dart`）：

- 参数（`parameters`，26–64 行）：`query`（必填）、`top_k`（默认 5）、`content_type`、`entity_id`、
  `scope_id`、`search_mode`（enum：`general | summary | roleplay | evidence`）。
- 预算常量（10–11 行）：`_maxObservationChars = 4800`、`_maxContentExcerptChars = 700`。
- `execute`（67–137 行）流程：
  1. `query` 空 → 报错返回；`topK.clamp(1, 10)`（74 行）。
  2. `searchMode == 'evidence'` 且缺 `entity_id`/`scope_id` → 直接返回"需要先解析两个 ID"的引导观察
     （79–88 行）。
  3. 未带 `entity_id`/`content_type` 时先调 `store.findEntityCandidates(query)`（94 行），若
     `name_exact / canonical_alias_exact / alias_exact` 候选多于 1 个 → 返回歧义候选列表，不检索
     （92–104 行，`_formatDisambiguationCandidates` 231–262 行）。
  4. 调 `store.search(...)`（106–113 行），结果非空则 `_formatGameDataResults`（139–229 行）。
  5. 无结果时区分三种文案：evidence 模式无结果引导 / 一般无结果 / 库未安装（117–136 行）。
- 观察格式化（139–229 行）：每个结果输出 `=== Result #N (Score: x) ===` + 元数据行（Source Kind /
  Source Type / Retrieval Type / Ranking Reason / ID / Content Category / Content Type / Entity ID /
  Story ID / Title / Section / Source Path / Raw ID / Lines / Trust / Content Excerpt）+ 尾部注记。
  预算守卫：`remainingBudget = 4800 - buffer.length`，`<= 900` 时停止追加并统计 `omittedResults`
  （167–171 行）。
- `_excerpt`（264–268 行）：空白折叠后超 700 字符截断加 `[truncated]`。

### 1.2 GameDataQueryPlan：意图归一化与同义词扩展

`lib/core/gamedata/gamedata_query_plan.dart`，全部为纯函数：

- `GameDataQueryPlan.from`（40–64 行）：trim → 空白归一化（`\s+` → 空格，45 行）→
  `inferContentType`（72–79 行：语音→`operator_voice`、秘录→`operator_record_story`、模组→
  `operator_module`、档案→`operator_handbook_profile`、敌人→`enemy_profile`；显式 `explicitContentType`
  优先）→ `entityFocusedQuery`（81–87 行：移除 `queryIntentTerms` 中的意图词，117–133 行共 14 个词：
  语音/档案/秘录/模组/主线/剧情/故事/时间线/事件/章节/关卡/行动/相关/梗概/介绍）→
  `searchQueries` 集合（50–55 行：`{normalized, entityQuery, expandedQueryAliases(normalized),
  expandedQueryAliases(entityQuery)}` 去重）→ `detectStoryIntent`（26–28 行，正则
  `主线|剧情|故事|时间线|事件|章节|关卡|行动`）。
- 同义词扩展 `expandedQueryAliases`（89–115 行）：肉鸽→集成战略（并追加四个主题名）、集成战略→肉鸽、
  收藏品→`relic collection`、语音→`operator_voice charword`、档案→`operator_handbook_profile
  handbook`、秘录→`operator_record_story story_review`、模组→`operator_module uniequip`。
- `storySearchTerms`（135–160 行）：先取"query 中包含的实体名"，否则取非意图词，去重后最多 3 词。
- `ftsQuery`（208–214 行）：每词加双引号、空格连接（短语查询）。
- `searchTerms`（216–224 行）：空白切分 + 去重。
- `evidenceProximity`（226–244 行）+ `allOffsets`（246–254 行）：正文中实体名与关系词的最短字符距离。

### 1.3 GameDataKnowledgeStore：多阶段检索顺序

`lib/core/gamedata/gamedata_knowledge_store.dart`，入口 `search`（23–208 行）：

| 阶段 | 函数（行号） | SQL 形态 | 排序 | 截断 |
| --- | --- | --- | --- | --- |
| 0. evidence 短路 | `_searchScopedStoryEvidence`（43–55 行入口，862–922 行） | `lore_chunks`：`source_type='game_story' AND scope_type=? AND scope_id=? AND (content LIKE 实体名...) AND (content/page_title/raw_id LIKE 每关系词)` | SQL `ORDER BY story_id, raw_id` LIMIT 200，再在 Dart 内按 `evidenceProximity` 升序 | `LIMIT 200` 硬编码（897 行），最终 `take(limit)` |
| 1. 实体结构化查询 | `_searchEntities`（57–66 行，320–386 行） | 有 `entity_aliases` 表时 `LEFT JOIN` + `MIN(CASE rank)`（0=name 精确、1=canonical alias、2=alias、3=name LIKE、4=alias LIKE），无表时 legacy `aliases LIKE` | `ORDER BY rank, name` | `LIMIT limit` |
| 1b. 实体→结果 | `_entityRowsToResults`（388–431 行） | 每实体先 `_recordsForEntity(limit: 2)`；有记录 score 7600/6200（`entity_exact`/`entity_like`）；无记录 score 10000/8000 单条 | — | — |
| 2. 实体文档 | `_documentsForEntity`（613–642 行） | `entity_documents WHERE entity_id=?`（contentType 非空则跳过） | `document_type` CASE（`operator_profile_bundle` 优先） | `LIMIT limit` |
| 3. 剧情上下文（仅 summary/roleplay） | `_searchStoryChunksLike`（88–97 行，545–591 行） | `lore_chunks`：`(source_type='game_story' OR content_category='story') AND 每词 LIKE page_title/section/content/raw_id` | `content LIKE 首词` 优先，再 `page_title` | `LIMIT limit` |
| 4. 实体 chunk / record | `_chunksForEntity`（98–105 行，488–523 行）、`_recordsForEntity`（106–113 行，433–466 行） | `lore_chunks`/`normalized_records WHERE entity_id=?`（可加 content_type） | chunk：content_type CASE（档案0…语音6，其他7）+ section；record：content_type CASE（档案0/基础1/敌人2/其他3）+ section | `LIMIT limit` |
| 5. 文档 FTS/LIKE（无 content_type 时） | `_searchDocumentsFts`（116–135 行，644–677 行）、`_searchDocumentsLike`（127–134 行，679–728 行） | FTS：`entity_documents_fts MATCH ?` JOIN `entity_documents`（try/catch 静默降级）；LIKE：多词 AND 匹配 entity_name/title/summary/content | document_type CASE | `LIMIT limit*2` |
| 6. record LIKE | `_searchRecordsLike`（137–145 行，730–777 行） | 多词 AND LIKE title/entity_name/content/raw_id | `title=` 0、`entity_name=` 1、`title LIKE` 2、其他 3 | `LIMIT limit*2` |
| 7. content_type 宽回退（record） | `_recordsByContentType`（148–156 行，468–486 行） | `content_type=?` | `title, raw_id` | `LIMIT limit` |
| 8. 剧情上下文兜底（summary 或 story intent） | `_searchStoryChunksLike`（158–167 行） | 同阶段 3 | 同阶段 3 | `LIMIT limit*2` |
| 9. chunk FTS/LIKE | `_searchChunksFts`（169–189 行，779–812 行）、`_searchChunksLike`（180–188 行，814–860 行） | FTS：`lore_chunks_fts MATCH ?` JOIN `lore_chunks`（try/catch 静默降级）；LIKE：多词 AND LIKE page_title/section/content/raw_id | LIKE：`page_title=` 0、`page_title LIKE` 1、其他 2 | `LIMIT limit*2` |
| 10. content_type 宽回退（chunk） | `_chunksByContentType`（191–199 行，525–543 行） | `content_type=?` | `page_title, raw_id` | `LIMIT limit` |

汇总（201–207 行）：`byId`（`Map<String, GameDataSearchResult>`）用 `putIfAbsent` 去重，**先到先得**
（高优先级阶段先写，低优先级不覆盖），最后按 `score` 降序、`title` 升序排序并 `take(limit)`。

- 硬限制位置：`limit = topK.clamp(1, 10)`（38 行）；实体扇出 `entityIds.take(5)`（79 行）；
  evidence 候选 `LIMIT 200`（897 行）；各阶段 `limit * 2`。
- 结果模型 `GameDataSearchResult`（`gamedata_models.dart` 7–47 行）含 `id/score/retrievalType/
  sourceKind/sourceType/title/content/contentCategory/contentSubtype/contentType/entityId/storyId/
  section/sourcePath/rawId/lineStart/lineEnd/rankingReason`。
- `findEntityCandidates`（210–295 行）：别名表排名 SQL（246–282 行）或 legacy fallback（221–243 行），
  `candidateMatchType`（`gamedata_query_plan.dart` 9–24 行）。

---

## 2. Agent 编排

### 2.1 ReActLoop 配置与机制（`lib/core/agent/react_loop.dart`）

- 构造参数（48–58 行）：`maxIterations = 5`、`minimumToolCalls = 0`、`stepMaxTokens = 2048`。
- `run`（66–337 行）：
  - 系统提示 = 外部 systemPrompt + `reactFormatPrompt`（79–102 行，含全部工具名/描述/JSON Schema 与
    严格的 ReAct 键格式约束：每键新行、Action Input 必须严格 JSON、一次只输出一个 Thought/Action）。
  - 消息 = `[system, ...chatHistory, user(query)]`（105–109 行）。
  - 每轮 LLM 调用：`temperature 0.1`、`maxTokens = _stepMaxTokens`、`stop = ['Observation:', ...]`
    （126–137 行）；`wasTruncated` → error 事件并终止（145–152 行）。
  - 解析：`parseReActKey`（`react_parser.dart` 16–53 行）提取 Thought/Action/Action Input/Final Answer。
  - **minimumToolCalls 门禁**：模型提前给 Final Answer 或 Action 为空时，若 `completedToolCalls <
    _minimumToolCalls`，注入 `Observation: Error - A final answer requires at least N completed tool
    call(s)` 并 continue（184–191、216–224 行）。
  - 工具执行（239–285 行）：未注册工具 → error Observation 继续；`parseActionInput`（`react_parser.dart`
    69–98 行：先 `extractLeadingJsonObject` 后 jsonDecode，失败走 `parseLooseKeyValuePairs` 仅认
    `knownKeys`，再退化为单 `query`/`chunk_id`）；执行结果取 `ToolExecutionResult.observation`，异常 →
    `Error executing tool: $e` 观察；`completedToolCalls++`、`evidenceSummary.addObservation`、
    `observations.add`、`loopMessages.add('Observation: ...')`。
  - 循环耗尽未完成 → `buildFallbackPrompt(evidenceSummary)`（`evidence_summary.dart` 40–59 行）追加后
    再调一次 LLM（`temperature 0.2, maxTokens 3072`，294–298 行），解析 Final Answer。
- `_finalizeAnswer`（339–349 行）：**先 `applySourceGuard`（来源守卫），再跑
  `finalAnswerTransform`**；transform 签名 `(String answer, List<String> observations)`（11–14 行）。
- 最终输出：`_emitFinalAnswer`（358–367 行）按 `chunkSize = 120` 逐块 `finalAnswerToken` 事件 —
  **分块仅渲染决策，内容在分块前已完整生成并过完 transform**（注释 351–357 行明确说明）。
- 来源守卫 `applySourceGuard`（`evidence_summary.dart` 63–87 行）：答案声称 Wiki/Book/GameData 但本次
  会话 observations 无对应来源标记 → 追加 `> Source warning: ...` 块（正则 89–101 行）。
  `EvidenceSummary.addObservation`（16–37 行）用子串匹配统计 `hasGameData/hasWiki/hasBook/
  emptyOrErrorObservationCount`。

### 2.2 三个 Agent 的工作流差异

| | SummaryAgent | FactCheckAgent | RoleplayAgent |
| --- | --- | --- | --- |
| 文件 | `summary_agent.dart` | `fact_check_agent.dart` | `roleplay_agent.dart` |
| 工具注册 | 仅 `SearchLocalLoreTool(gameDataStore: null)`（19–21 行） | 仅 `_searchTool`（默认 SearchLocalLoreTool）（28 行） | `_CharacterBoundSearchTool` 包装（72–73 行，100–124 行）：强制注入 `entity_id` 与 `search_mode='roleplay'` |
| ReActLoop | `maxIterations: 4`，其余默认（35–39 行） | `maxIterations: 7, minimumToolCalls: 1, stepMaxTokens: 4096`（29–35 行） | `maxIterations: isFirstTurn ? 7 : 5, minimumToolCalls: 1, stepMaxTokens: 4096`（74–80 行） |
| 前置消歧 | 无（prompt 要求遇歧义停止询问，`agent_prompts.dart` 82 行） | 无（prompt 要求歧义→uncertain，47/61 行） | `resolveCharacter`（34–63 行）确定性消歧：单 exact→resolved、多 exact→ambiguous、单候选→resolved、无→notFound、库不可用→unavailable；`GameDataEntityCandidate` 持久化（`agent_provider.dart` 549–570 行） |
| finalAnswerTransform | 无 | `validateFactCheckVerdict` + `_withValidatedVerdict`（41–44 行） | 无 |
| prompt | base + knowledgeBaseRules + summaryInstructions | + factCheckInstructions | + roleplayInstructions + 会话 context（81–90 行） |

- **Fact-check 的 verdict transform 与来源守卫**（`fact_check_agent.dart`）：
  - `validateFactCheckVerdict`（49–85 行）：从答案解析 `[FACT_CHECK_VERDICT:(supported|refuted|
    uncertain|unavailable)]`（大小写不敏感）；**supported/refuted 要求 observations 含
    `Evidence Scope Match: yes` 且 `Evidence Level: direct candidate`**（`hasScopedDirectCandidate`），
    否则若有 `Source Kind: GameData` + `=== Result #`（`hasGameDataEvidence`）降级 uncertain，
    否则降级 unavailable；`uncertain` 在无证据且 `noCoverage`（无结果/未安装文案）时降级 unavailable。
  - `_withValidatedVerdict`（87–93 行）：把标记重写并强制放到答案首行。
  - 前端 `parseFactCheckVerdict`（95–103 行）从流式 token 解析 verdict（`agent_provider.dart` 244–250 行）。
- **最终回答如何输出**：三处一致 —— ReActLoop 在检测到 Final Answer（或 fallback）时先
  `_finalizeAnswer`（守卫 + transform），再 `_emitFinalAnswer` 按 120 字符分块发事件；Notifier
  （`agent_provider.dart`）把 `finalAnswerToken` 累积成消息正文（如 100–107、244–250、428–430 行），
  UI 渐进渲染。历史回灌：`SummaryChatNotifier.buildHistory`（144–174 行）把 step 重组成
  Thought/Action/Action Input/Observation 文本再喂回下一轮。

---

## 3. 安装链路（GameDataInstaller）

`lib/core/gamedata/gamedata_installer.dart`，完整流程：

1. **资产来源**：仅编译期 dart-define `ARKLORES_GAMEDATA_DB_URL` / `ARKLORES_GAMEDATA_DB_SHA256`
   （52–54 行）；`getReleaseAsset`（67–73 行）无 URL 返回 null。
2. **下载**：`installFromReleaseAsset`（75–132 行）— `http.Request('GET')` 流式读入内存
   `BytesBuilder`（97–108 行），`onProgress(received, total)` 回调；非 200 → StateError。
3. **SHA-256 校验**：仅当 asset 提供 `sha256` 时对**压缩字节**做 `sha256.convert` 大小写不敏感比对
   （110–117 行），失败 `checksum mismatch`。
4. **解压与大小校验**：`gzip.decode` 全量解压（119 行）；仅当提供 `uncompressedBytes` 时比对长度
   （120–125 行）。
5. **原子替换**：`installFromBytes`（134–154 行）— 写 `<db>.tmp`（141–143 行）→
   `_validateDatabase(tmp)`（144–149 行）→ 通过后删除旧文件（150–152 行）→ `tmp.rename`（153 行）。
6. **schema 校验**：`_validateDatabase`（185–255 行）—
   - 非空文件检查（187–189 行）；
   - 必需表清单（194–205 行）：`gamedata_manifest, entities, entity_aliases, entity_documents,
     normalized_records, story_lines, story_scopes, lore_chunks, entity_documents_fts, lore_chunks_fts`
     （`sqlite_master` 中 `type IN ('table','virtual')`）；
   - manifest 必须含 `schema_version` 且 **== '2'**（228–238 行，与 `tools/build_gamedata_database.dart`
     20 行 `_schemaVersion = 2` 对应）；
   - `entity_count / normalized_record_count / lore_chunk_count` 必须为正整数（240–251 行）；
     注意 **不校验 `story_line_count`**（manifest 有该键，build 工具 127 行）。
7. **manifest 读取**：`_readManifest`（170–183 行）— readOnly 打开 → `SELECT * FROM gamedata_manifest`
   → 转 key→value map → 关闭；异常返回空 map。`GameDataInstallStatus`（10–28 行）暴露
   `sourceCommit/builtAt/entityCount/recordCount/chunkCount`。

**DB 文件位置**（156–168 行）：`installDirectory` 优先；Android 用 `getExternalStorageDirectory()`，
否则 `getApplicationDocumentsDirectory()`；文件名固定 `arklores_gamedata_zh.db`（47 行）。与
`GameDataKnowledgeStore._resolveDbPath`（310–318 行）逻辑完全一致 —— 同一设备上安装与读取同一文件。

**关键细节 —— 是否持有句柄 / 安装是否关闭连接**：

- `GameDataKnowledgeStore` 懒打开并**缓存** `_db` 句柄（16、302–308 行，
  `sqflite.openDatabase(path, readOnly: true)`）；`close()`（297–300 行）**在 lib 内没有任何调用点**
  （grep 确认：仅 installer 内部与 store 自身的 open/close）。
- 安装器只开**自己的短生命周期句柄**（`_readManifest`/`_validateDatabase` 的 try/finally close），
  **不感知、不关闭 store 的连接**。知识库页 `_downloadGameData`（`knowledge_base_page.dart` 97–138 行）
  调 `installFromReleaseAsset(overwrite: true)` 后仅 `ref.invalidate(gameDataInstallStatusProvider)`。
- 后果：Android/iOS（POSIX）下 rename 可替换被打开的文件（旧 inode 存活到句柄关闭），但 store 会继续
  读**旧库**直到 `close()` 或进程重启；本项目仅 android/ios 平台（无 Windows 桌面目录），不存在
  Windows 共享冲突，但"替换后读到旧数据"的风险真实存在。此外每个 Agent/工具各自 `new
  GameDataKnowledgeStore()`（`search_local_lore.dart` 9 行、`summary_agent.dart` 19–21 行、
  `roleplay_agent.dart` 27–29 行），**多个句柄并存且全部不关闭**。

---

## 4. App 侧数据库访问方式

- **sqflite，无 sqlite3 FFI**：`pubspec.yaml` 仅 `sqflite: ^2.4.0`（+ `path_provider: ^2.1.0`、
  `path: ^1.9.0`）；lib 内所有 DB 访问都是 `package:sqflite/sqflite.dart`（store 5 行、installer 8 行；
  `bookmark_service.dart` 另开一个 sqflite 库，与 GameData 无关）。
- **连接管理**：`sqflite.openDatabase(path, readOnly: true)`（store 306 行；installer 173/193 行）；
  store 单例懒加载缓存，无连接池、无 WAL 管理；FTS 表存在性用 `_hasTable`（975–986 行，查
  `sqlite_master`）。
- **FTS5 在移动端**：构建期 `CREATE VIRTUAL TABLE ... USING fts5`（`build_gamedata_database.dart`
  312–334 行）——`entity_documents_fts` 用 `tokenize='trigram'`（322 行），`lore_chunks_fts`
  **无 tokenize（默认 unicode61）**（326–334 行）。sqflite 不捆绑 SQLite，Android/iOS 走系统库：
  FTS5 在较新系统可用；**trigram 需 SQLite ≥ 3.34.0（约 iOS 15+ / Android 13+ 的系统 SQLite）**，老设备
  上会抛错 —— store 对两个 FTS 查询都有 `try/catch` 静默返回空数组（660–676、797–811 行），属既有
  降级路径（代价：FTS 证据静默缺失，UI 表现为"无结果"）。另外 unicode61 对无空格中文近似整段连续匹配，
  实际召回主要靠 LIKE 回退路径。
- **路径获取**：`path_provider` 的 `getExternalStorageDirectory()`（Android 优先）与
  `getApplicationDocumentsDirectory()`，拼接 `arklores_gamedata_zh.db`（installer 156–168 行、
  store 310–318 行）。

---

## 5. 对 AI_RETRIEVAL_OPTIMIZATION.md P0/P1 的代码级可行性评估

### 5.1 新表字段支撑（P0 §4.1）

| 新表 | 现有数据能否支撑 | 证据 |
| --- | --- | --- |
| `entity_story_mentions` | **是**。构建期用 `entities.name`/`aliases`（build 187–198 行）、`entity_aliases`（200–209 行）建 trie，单遍扫描 `story_lines.content`（211–223 行：`content/line_index/story_id` 齐全）；scope 从 `story_scopes`（278–284 行）取。运行时只读 rawQuery，不依赖现有结果模型 | `story_lines` 无 `scope_id` 列，需 join `story_scopes`（story_id 为主键） |
| `story_chapter_profiles` | **是**。`speaker` 列存在（217 行）；entity_density/关键词命中/summary 全部构建期统计，运行时纯读 | — |
| `story_lines_fts` | **是**。`story_lines` 是普通表（`id TEXT PRIMARY KEY`，211 行），**未声明 WITHOUT ROWID → 隐式 rowid 存在**，外部内容 FTS 可用（文档 §4.1"实现注意"已确认可行）。**tokenizer 需明确**：与 `lore_chunks_fts` 一致（默认 unicode61）还是与 `entity_documents_fts` 一致（trigram，设备依赖，见 §4）；2 字符中文词 trigram 不索引 → 计划中 LIKE 回退必要 | — |
| `rare_terms` | **是**。纯构建期 bigram doc_freq 统计 | — |

schema v3 落地需同步改动的现有代码：`GameDataInstaller._validateDatabase` 的必需表清单（194–205 行）
与 `schema_version != '2'` 校验（234 行）；`tools/finalize_gamedata_assets.dart` 的 manifest 计数/hash；
`tools/build_gamedata_database.dart` 第 5 阶段与 `_writeManifest`（370–378 行）。store 侧 `_hasTable`
守卫可兼容 additive 变化（老库查询不炸）。

### 5.2 新工具接入 ToolRegistry 的机制清晰度（P0 §4.3 / P1 §5.1）

- 机制极简且**清晰**：`AgentTool` 抽象（`agent_tool.dart` 14–36 行，`name/description/parameters/
  execute/toJson`）+ `ToolRegistry.register/registerAll/getTool/allTools/toJsonList`（`tool_registry.dart`
  8–27 行）。新工具 = 新 `AgentTool` 子类，`execute` 里注入 `GameDataKnowledgeStore` 直接 `rawQuery`
  （复用其 `_open`/`_hasTable`）即可；格式化与预算模式照抄 `SearchLocalLoreTool`。
- 注意点：
  1. 三个 Agent 各自**独立构造 registry**（`fact_check_agent.dart` 28 行、`summary_agent.dart` 16–22 行、
     `roleplay_agent.dart` 72–73 行），新工具不会自动出现 —— 需在要用到的 Agent 里显式注册，或引入
     共享 registry/基类。
  2. observation 是**单字符串协议**，且 `evidence_observation.dart`（27–77 行）依赖
     `=== Result #N`、`Source Kind: GameData`、`Content Excerpt:` 等固定文本解析证据卡 —— 新工具若复用
     该格式会被解析成证据卡（可能不合语义）；若输出新格式（覆盖报告、原文行），要避免 `=== Result #`
     前缀，或接受其不进入证据卡（解析器对未知字段静默忽略，38–54 行）。
  3. `_CharacterBoundSearchTool`（roleplay_agent.dart 100–124 行）是"包装已有工具注入参数"的现成模板，
     P1 的 `collect_suspect_evidence` 等角色绑定场景可复用。

### 5.3 ReActLoop 扩展性（P0 §4.4 / P1 §5.2、§5.3）

- **迭代预算扩展：是，零改动**。`maxIterations / minimumToolCalls / stepMaxTokens` 已是构造参数且各
  Agent 已用不同值（4/7/5、0/1/1、2048/4096/4096）；P1 的 12–15 轮、4096+、`minimumToolCalls >= 4`
  直接传参。注意 `react_loop.dart` 53 行默认 2048 与 `chatCompletion` 默认（`llm_client.dart` 135 行）
  一致，P0/P1 需显式覆盖。
- **结构化步骤协议（S0–S8）：部分可行，机制受限**。循环内**没有步骤/阶段概念**，只有
  Thought/Action/Action Input/Final Answer 四键（`react_parser.dart` 16–53 行）。阶段门槛只能通过：
  (1) prompt 约束 + (2) `finalAnswerTransform` 代码级校验（对 `observations` 列表与答案文本做结构化解析）
  实现；或新建 `StoryInvestigationAgent`（照抄 `FactCheckAgent` 的装配模式）承载协议。"前置条件由工具
  返回计数校验"可以做到 —— 工具输出固定标记（如 `Coverage Count: N`、`Suspect Evidence: entity_id=...
  count=...`），transform 内正则比对 —— 但本质是 **stringly-typed 契约**，建议为新工具定义严格、稳定的
  观察文本格式并配套解析函数（可参考 `evidence_observation.dart` 的块解析）。
- **finalAnswerTransform 校验：可行且有先例**。签名 `(answer, observations)`（react_loop.dart 11–14 行）
  已够比对"已读范围报告"与"实际工具调用记录"；`validateFactCheckVerdict`（fact_check_agent.dart
  49–85 行）就是"transform 内做门禁/降级"的现成实现。P1 的 `[INVESTIGATION_VERDICT:...]` 重写、
  行级 provenance 校验（扩展 `applySourceGuard`）、已读范围比对均可同构实现。transform 只跑一次且作用于
  完整答案（非逐 token），与 120 字符渲染分块不冲突。
- 已读范围报告的来源事实：`observations` 是 `List.unmodifiable` 快照（348 行），包含每轮工具原始观察，
  transform 可基于它校验 —— 但**观察文本不含工具名**（只有内容），多工具混用时需靠内容标记区分。

### 5.4 分页（page_token）在当前 observation 协议中的可行性（P0 §4.3）

- **可行，无服务端状态**：observation 是单个字符串（`ToolExecutionResult.observation`，
  agent_tool.dart 3–11 行）。`read_story_lines` 可在观察文本尾部输出 `Next Page Token: <opaque>`，
  模型在下一轮 `Action Input` 原样回传；参数 schema 声明 `page_token` 后 `parseActionInput` 自动支持
  （`react_parser.dart` 83–97 行 knownKeys 机制；`coerceLooseValue` 对字符串透传，187–195 行）。
- 风险：模型对不透明 token 的忠实回传不保证（需 prompt 强制"原样回传，不得改写"）；token 建议用
  短、无空格、无歧义字符集（如 base36），并在观察里同时给出行区间提示便于模型校验。
- UI 侧：`evidence_observation.dart` 忽略未知字段，分页字段不影响证据卡解析。

---

## 6. 风险点：限制的实现位置与"读原文行"需要的改动

| 限制 | 实现位置（文件:行） | 增加"读原文行"能力的改动点 |
| --- | --- | --- |
| 观察预算 4800 字符 | `search_local_lore.dart:10` `_maxObservationChars = 4800`；守卫在 `_formatGameDataResults` 167–171 行（`remainingBudget <= 900` 停止 + `omittedResults` 注记） | 新工具（`read_story_lines`）建议**独立预算常量**（放宽到 ~8000–12000）或参数化该常量；同时注意 ReActLoop `stepMaxTokens`（`react_loop.dart:53`，默认 2048）决定模型单步生成上限（观察由系统注入不占生成 token，但累积上下文会膨胀） |
| excerpt 700 字符 | `search_local_lore.dart:11` `_maxContentExcerptChars = 700`；`_excerpt` 264–268 行 | 行级返回不受此限，但需新的行级格式化（每行 `line_index | speaker | content`）+ 独立预算 |
| top_k ≤ 10 | 工具 `search_local_lore.dart:74` `topK.clamp(1, 10)`；store `gamedata_knowledge_store.dart:38` `topK.clamp(1, 10)`；阶段内 `limit * 2`（121/130/140/163/173/182 行） | 新工具自定 `max_lines`/`max_results` 参数，不经过 `search` 的 clamp |
| evidence 候选上限 200 | `gamedata_knowledge_store.dart:897` `LIMIT 200`（`_searchScopedStoryEvidence`） | 长 scope 分页或放宽；P0 的 `collect_suspect_evidence` 需自己的分页参数 |
| 实体扇出上限 5 | `gamedata_knowledge_store.dart:79` `entityIds.take(5)` | 覆盖层（`search_story_coverage`）直接查 `entity_story_mentions`，不受此限 |
| FTS 静默降级 | `gamedata_knowledge_store.dart:660–676、797–811`（try/catch 返回空） | 新 FTS（`story_lines_fts`）若用 trigram，移动端老设备不可用 → 工具需显式探测并返回"降级为 LIKE"提示，避免把降级误读为无证据 |
| 安装不关 store 连接 | 无调用点；`gamedata_knowledge_store.dart:297–300` `close()` 存在但 lib 内无人调用；`knowledge_base_page.dart:97–138` 不关 | 建议安装前调 `store.close()`（或按文件 mtime/大小使缓存失效），否则替换后读到旧库 |
| 下载全量驻内存 | `gamedata_installer.dart:97–108`（BytesBuilder）+ 119 行（gzip.decode 全量解压） | DB 数十 MB 级，移动端可接受，但报告应注明峰值内存 |
| 校验缺口 | `gamedata_installer.dart:240–251` 只校验 3 个计数，不校验 `story_line_count`（manifest 键存在，build 127 行） | schema v3 新增表计数（`entity_story_mentions` 等）应补入校验 |
| 多轮上下文膨胀 | `agent_provider.dart:144–174`（buildHistory 重组 ReAct 文本回灌） | P1 12–15 轮 × 多页原文会显著增长上下文，需截断/压缩策略（计划未提及） |
| 行级引用的既有载体 | `gamedata_models.dart:44–45`（lineStart/lineEnd）、38（storyId）；`_chunkResult`/`_recordResult` 已填（knowledge_store 945–946、1003、1009–1010 行），`_documentResult` 未填（951–973 行） | `read_story_lines` 可复用 `storyId` + 行号作为引用格式，证据卡/守卫可扩展 |

---

## 附：关键事实速查

- sqflite 版本 `^2.4.0`；无 sqlite3 FFI；FTS5 表构建于 `build_gamedata_database.dart:312–334`。
- `story_lines` 约 40 万行（v0.9.0 manifest），**Agent 检索链路完全不读**（lib 内仅 installer 必需表清单
  出现；grep 确认 store/agent 无引用）；`check_gamedata_retrieval.dart:79–126` 的固定 QA 直接 rawQuery
  `lore_chunks` 验证 `act21mini + 米格鲁 + 死亡` scoped evidence。
- `story_scopes` 由构建器写入（build 856–864 行），scope 推导 `_storyScope`（1238–1245 行）：
  `activities/<id>` → `('activity', <id>)`，否则 `(<首段>, <首段>)` —— 与 fact-check prompt
  （`agent_prompts.dart` 47 行）"范围结果 Entity ID 即 scope_id（如 activity:stable_id）"一致。
- `GameDataQueryPlan` 纯函数、无 DB 依赖（`gamedata_query_plan.dart` 头注释），检索行为可单测 ——
  P0/P1 新增的覆盖/画像/rare_terms 逻辑同样应保持纯函数可测。
- 最终答案分块仅 120 字符/事件，为渲染决策（react_loop.dart 351–367 行）。

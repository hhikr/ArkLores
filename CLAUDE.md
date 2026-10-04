# ArkLores Developer Notes

当前主线：中文 GameData release asset + SQLite structured retrieval + FTS/LIKE
+ 可选剧情向量召回（R12）+ 可选故事目录与官方梗概（R14，`story_catalog`）；
剧情问答由工具型 Agent（R17，`LoreAgentLoop`）直接查库作答。向量、目录、梗概都只作定位线索，不作证据。
当前版本：v0.10.4（预发布，R13–R18）；知识库资产仍是 v0.10.1 Release 上的那份。
**版本号停在 0.10.x**：0.9 之后都是剧情问答工作流的迭代，v0.11.0 预发布已撤回；除非开发者明确说开启 0.11，
发版只升 patch（0.10.2…），Android build 号继续递增。
GameData schema：4（含确定性覆盖层，可选剧情向量表、可选故事目录表）。
知识库页会在已安装的官方资产与本 APK 指向的资产不同（`.asset_sha256` 标记）时提示更新。

## 当前进度（每轮结束时更新）

- v0.10.4（2026-10-03，R18，分支 `feature/r18-answer-quality`）：`release/v0.10.4`（b123e9d）已由 CI 构建签名成功，
  Release 页面需开发者手动创建（云端 403）。内容：§5.9 答案质量——审稿子 agent（读者视角，
  只提本故事后段揭示/其他故事层面的待核实问题，主 agent 回原文核实后重写）+ 按阶段整理（详细版折叠在 `[DETAILS]` 下，
  每段出处由代码合并，段数只软性提示）+ 重写后只有过程话时的兜底。复测数据见 `docs/R17_TOOL_AGENT.md` §2「R18」。
  **待开发者真机确认**：答案开头是否交代故事性质、整理段落的可读性、“详细经过”折叠与流式手感
  （v0.10.3 的 R17d 界面项也一并确认）。
- 开发可在本机（Windows）或云端（环境 ArkLores-Cloud，见 `docs/CLOUD_DEV.md`）进行。

## 文档索引

- `docs/CLOUD_DEV.md`：云端会话的环境、每次开始要跑的脚本、能做/不能做的事、发版。
- `docs/AI_ARCHITECTURE.md`：Agent 与检索架构（当前状态 + 演进简史）——改 agent/检索层前先读。
- `docs/R17_TOOL_AGENT.md`：剧情问答 Agent 的结构、工具、子 agent、出处核对与验收数据。
- `docs/KNOWN_LIMITATIONS_AND_DEBT.md`：已知限制与根因。
- `docs/RETRIEVAL_QA.md`：验收清单（离线 + 真机同链路）。
- `docs/GAMEDATA_BUILD_PIPELINE.md`：数据构建、向量、发布。
- `docs/R12_BOTTLENECK_ANALYSIS.md`：R12 决策记录。
- `docs/ARKLORES_V0.9_TECHNICAL_REPORT.md`：v0.9 审计快照（不再更新）。

## Do

- Linux 使用 `/home/hhikr/flutter/bin/flutter`；Windows 使用 `C:\src\flutter\bin\flutter`
  （已在 PATH）；云端会话里是 `/opt/flutter`（已链接到 `/usr/local/bin/flutter`）。
- **云端会话**（环境变量 `CLAUDE_CODE_REMOTE=true`）开始时先运行 `bash tools/cloud/session_start.sh`
  （git 作者、key 文件、pub get）；需要知识库时 `bash tools/cloud/fetch_gamedata.sh`。详见 `docs/CLOUD_DEV.md`。
- 保护 `logs/`。
- 保持 GameData 为 Agent 主知识源。
- 保留 source path、raw id、content type、entity id。
- 剧情问答 Agent 只查本地 GameData 库（`lore_tools.dart`），角色扮演只用 `search_local_lore`；Wiki 和用户文本只能作为浏览/上下文。
- 运行相关 tests / analyze 后再汇报。

## Do Not

- 不恢复旧 Wiki seed 运行链路。
- 不恢复旧用户资料索引链路。
- 不提交 API key、token、`.env`。
- 不直接 push `main` 或 `dev`。

## 发布与签名（v0.10.0 起）

- APK 由 GitHub Actions 构建：把要发布的提交推到 `release/<版本>` 分支即触发
  `android-release.yml`，产物在该次运行的 artifact 中。GameData 资产的 URL/SHA 在
  `tools/release_gamedata.env`，每次数据发版都要更新。
- App 预发布一条命令：先改版本号/文档并提交推送，再运行 `tools/release_app.ps1 -Version <v> -NotesFile <md>`（Windows，
  PAT）或 `tools/release_app.sh <v> <md>`（Linux/云端，`gh`）：推 `release/v<v>` → 等 CI → 下载 APK → 建预发布。
  发版前必须得到开发者明确同意。云端会话不能创建 Release（403），最后一步由开发者完成，见 `docs/CLOUD_DEV.md`。
- 签名用项目 release keystore（仓库 secrets：`ANDROID_KEYSTORE_BASE64` 等）；workflow
  会校验证书 SHA-256 为 `b1b09ebf…e364`。本地备份 `tools/arklores-release.jks` +
  `tools/android_signing.properties`（gitignored），绝不提交、绝不打印。
- 本地 `flutter build apk --release` 没有 `android/key.properties` 时会退回 debug key，
  这样的包不能发布。
- CI（`ci.yml`）在 PR 上跑 analyze 与 test。
- Android 工具链：Flutter 3.47.5、Gradle 8.14.3、AGP 8.11.1、Kotlin 2.2.20、Java 17
  （Flutter 3.47 的最低要求）；Linux 本地构建也需要升级到同一 Flutter 版本。
- `release/<版本>` 分支只放构建 APK 的那个提交：再推送会重新构建，产出的 APK 哈希也会变。

## 提交规范（贡献者只有 hhikr）

- 提交的 author / committer 只能是 hhikr。
- 提交信息中**禁止**出现 `Co-Authored-By` 或任何把 AI 写为作者/协作者的
  尾注或署名（如 "Generated with ..."）；未经开发者明确许可不得添加。
- 2026-10 已改写全部历史移除旧的 Claude 协作者尾注；不要再引入。
- `.claude/settings.json` 的 `attribution` 已关闭 Claude Code 自动加的协作者尾注、PR 署名和 `Claude-Session` 尾注；不要改回。
- 凭据（`tools/api_info`、`tools/*apiKey*`、`tools/github_pat`）不得提交、
  打印、写入 git 配置或 remote URL。

## 检索与数据设计原则（防桥段专项优化）

背景教训：`story_chapter_profiles.keyword_hits` 曾内置 20 个死亡/凶案词做
`content.contains` 命中统计，围绕"凶手问题"用例设计；该桥段在真实问题分布中
占比极小，专项优化覆盖面趋近于零，还会把模型锚定向单一方向（2026-08 已移除）。
任何 agent 改动检索/数据层前必须过以下检查：

1. **只做桥段无关的通用机制**：可达性（原文/行级可读）、确定性覆盖（出场枚举）、
   通用信号（IDF 稀有词、实体密度）、可对比的证据集。新特征对"任意剧情问题"
   仍应有意义；只对某一类桥段有意义的特征一律拒绝。
2. **先量化再立项**：新增检索特征前，评估该用例在真实问题分布中的占比；占比
   极小的用例只能作为验收样例（QA fixture），不得驱动 schema / 特征设计。
3. **禁止硬编码"场景词典"作为检索特征**：如"死亡/凶案词表"这类为具体剧情桥段
   定制的词表。模型推理需要场景知识时，交给 Agent 在通用检索结果上自行完成，
   不要在数据层预置方向。
4. **可复现且来源清晰**：每个检索特征必须解释得清它从哪些源字段、用什么确定性
   规则算出来；构建两次结果一致，便于增量对比。
5. **不制造隐性证据**：检索/画像字段只能是"浏览提示或定位线索"，绝不参与事实
   判定或推理打分；判定只能由 Agent 基于检索到的原文形成。

## 禁止特判（R13，开发者硬性要求）

**特判**：任何只对某一类问题或某种剧情桥段生效的代码分支、阈值、提示词步骤或输出
字段。反例（均已在 R13 删除）："至少比较 2 个嫌疑人才能下结论"的门槛、`culprit=`
结论信封、"仅当问题问谁导致时"的提示词步骤、为凶手/死亡类问题定制的工具命名。

1. 所有剧情问题走同一条流程（`StoryQaAgent` → `LoreAgentLoop`）：同一份系统提示、同一套工具、
   引用校验与 `[STORY_ANSWER: status=…]` 状态。
2. 唯一允许的差异：用户选择的模式（`AnswerStyle`：回答 / 梗概 / 核查）决定答案的
   **输出格式**（系统提示末尾的一段）。不得因此改变检索或判定规则。
3. 新增任何特判一律拒绝；以后也不许再写。修改后自查：

   ```bash
   grep -rnE "culprit|suspect|嫌疑|凶手|罪魁" lib/
   ```

   结果必须为空（`test/no_special_case_test.dart` 在 `flutter test` 中守卫这一点）。
   换成任意其他类型的问题（"怎样""什么关系""在哪"），逻辑路径应完全相同。

## 禁止针对验收样例编程（anti-fixture-hardcoding）

背景教训（R11，2026-08）：调查死循环修复曾以"导致特蕾西娅死亡的罪魁祸首是谁"
为真机验收样例。该样例必须只作为**测试 fixture 与人工验收场景**，绝不进入
产品逻辑。任何 agent 改动 agent/检索/数据层前必须自查：

1. **产品代码（`lib/`）不得出现具体实体名/实体 id/剧情桥段字面量作为判定分支
   或特征**：如"特蕾西娅→选魔王候选""凶手问题→xx"这类针对特定问题的特判。
   实体名只能出现在注释/示例文案/测试 fixture 中；判定必须消费运行时输入
   （当前 query、候选列表、状态），而非固定值。
2. **通用机制验证方法**：新逻辑若只对某个样例有效而对"任意剧情问题"无意义，
   一律拒绝（与上方第 1 条同理）。修改后可自测：把样例换成一个不相关实体
   （如"阿米娅的某件事是谁做的"）或虚构实体，逻辑路径应同样成立。
3. **测试 fixture 允许具体实体**（它们是模拟输入，不是产品逻辑），但不得把
   fixture 里的具体 id/名字复制进 `lib/` 的判定条件；测试断言只验证通用行为
   （如"选了候选而非无脑选第一个""重复搜索被终结"），不验证某个具体实体
   被特殊对待。
4. **自查命令**：改动后运行
   `grep -rn "特蕾西娅\|enemy_1554\|enemy_3006\|trap_762" lib/`，
   结果应只有注释/文案；任何出现在 `if`/`switch`/数据结构键/检索参数中的
   具体实体，都必须证明其通用性（如来自运行时候选列表）。

## Useful Commands

```bash
/home/hhikr/flutter/bin/flutter test test/agent_test.dart
/home/hhikr/flutter/bin/flutter test
/home/hhikr/flutter/bin/flutter analyze
/home/hhikr/flutter/bin/dart run tools/build_gamedata_database.dart --help
HOME=/tmp /home/hhikr/flutter/bin/dart run tools/check_gamedata_retrieval.dart \
  --db=build/gamedata_mobile/arklores_gamedata_zh.db
```

### Windows（开发机 2026-10 起）

- flutter / dart：`C:\src\flutter\bin`；git：codex 自带
  `C:\Users\hhikr\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd\git.exe`
  （同目录 `..\usr\bin` 下有 sh、sed；没有 gzip，压缩用 .NET `GZipStream`）。两者已加入用户 PATH；若当前 shell 没刷新，先执行
  `$env:Path = "C:\src\flutter\bin;<git cmd 目录>;$env:Path"`。
- 没有 `gh` 和 Android SDK：GitHub 操作用 REST API；APK 由 GitHub Actions 构建。
- 磁盘：C 盘曾满到 0 字节，`flutter test` 编译失败后卡住半小时。全量测试正常约 25 秒，明显变慢先查剩余空间。
- PowerShell 设置环境变量用 `$env:NAME='value'`，不支持 `NAME=value cmd` 前缀。
- sqflite FFI 会把相对 DB 路径解析到 `.dart_tool` 下，`ARKLORES_GAMEDATA_DB` 等路径要写绝对路径。
- 依赖 POSIX 文件替换语义的测试在 Windows 上跳过；临时目录用 `test/support/temp_dir.dart`
  的 `deleteTempDir`（文件锁时重试）。

```powershell
flutter test
flutter analyze
$env:ARKLORES_RUN_LIVE_ASK='true'; $env:ARKLORES_LIVE_EVAL='test/fixtures/investigation_eval.json'
$env:ARKLORES_LIVE_IDS='frostnova_end'
$env:ARKLORES_GAMEDATA_DB="$PWD\build\gamedata_mobile\arklores_gamedata_zh_vec.db"
flutter test test/live/ask_pipeline_live_test.dart
```

GitHub PAT 在 gitignored 的 `tools/github_pat`：只在单条命令内用
`git -c "http.extraHeader=Authorization: Basic <base64(x-access-token:PAT)>" ...` 或 REST
请求头使用；不得打印、写入 git 配置或 remote URL。

### 电脑端调查复现（不需真机，与 App 同一条链路）

改完 agent/检索层后，先在电脑上用真实 GameData DB + 真实 LLM 跑一轮，
再真机验证。复现工具是 opt-in 的 live 测试（R12 起取代旧的
`tools/run_investigation.dart`，后者重写了数据层、与 App 不一致，已删除）：

```bash
ARKLORES_RUN_LIVE_ASK=true \
ARKLORES_LIVE_QUERIES="导致特蕾西娅死亡的罪魁祸首是谁||另一个问题" \
flutter test test/live/ask_pipeline_live_test.dart
```

- 驱动的是 App 的 `askChatProvider`（`AskChatNotifier.sendMessage`，默认
  auto 模式 → `QuestionRouter` → 各 Agent → `GameDataKnowledgeStore` →
  `ChatSessionStore`）；只覆盖 `main.dart` 启动时注入的 provider（API 配置、
  向量配置、会话日志开关）和两个平台路径（DB、会话目录）。SQL 引擎换成
  sqflite FFI，其余每个 Dart 类都是 App 代码。
- 输出：`build/live_sessions/<...>/conversation_*.json`（与 App
  `chat_sessions/`、`logs/` 同格式）+ 每题 `*.summary.json` 指标。
- 追问类用例用 `ARKLORES_LIVE_CONVERSATION=true`：`||` 分隔的问题作为同一会话的连续轮次。
- 可选：`ARKLORES_LIVE_MODE=investigate|summarize|verify`、
  `ARKLORES_LIVE_EVAL=test/fixtures/investigation_eval.json`（批量评测）、
  `ARKLORES_LIVE_IDS=a,b`、`ARKLORES_LIVE_NO_EMBEDDING=true`（模拟无向量 key）、
  `ARKLORES_GAMEDATA_DB`、`ARKLORES_LIVE_OUT`。
- 配置从 gitignored 的 `tools/api_info`（API_KEY=/MODEL=/URL=）和
  `tools/embedding-apiKey.csv`（`openAiCompatible`、`apiKey`）读取。
  **绝不提交有效 key**；`tools/*apiKey*` 已加入 .gitignore。

**真实 API 测试的成本约束**（开发者要求，2026-10）：
- 先跑离线测试（mock LLM 复现问题），离线确认之后才动用真实 API。
- 每个方面最多挑 2 个最有代表性的用例（用 `ARKLORES_LIVE_IDS` 过滤），逐题串行跑；
  每题跑完先看结果，有问题立即停止。复杂和边际情况等基础用例通过后再测。
- 不要整批跑 30 题评测，也不要并行开多组评测，除非开发者明确要求。
- 每题的 `*.summary.json` 会记录 `usage`（调用次数和 token 数），用它评估成本。
- 遇到 provider 错误（如 402 余额不足）时，harness 会自动跳过剩余题目。
- 成本取舍（开发者要求，2026-10）：除非这一轮就是专门的降本改动，新机制带来的调用次数/token 增加只要不是
  数量级上的差异，就先不处理，优先答案质量；验收表里照常记录 usage 以便对比。

### 故事目录（可选表，R14）

`story_catalog`（故事集名、关卡号、章名、行动前/后、顺序、官方梗概）来自
`story_review_table.json` + `story/[uc]info/**`，全量/增量构建自动生成；给现有库补表：

```bash
dart run tools/build_story_catalog.dart --db=<db> --source=<ArknightsGameData 稀疏检出>
```

Agent 用 `outline` 看整个故事集的章节梗概，用 `sql` 关联它排序；App 用它把引用显示为故事名。
R15 起目录带 `start_time`（活动上线时间；主线、密录为空），`grep` 全库统计与 `outline` 按它排序 / 显示"上线 yyyy-MM"。

### 名字与身份（R15）

知识库**不判定"谁是谁"**（代号/真名、"？？？"、冒名、夺舍都是剧情解读，写死的身份标注会把错误
当事实喂给模型）。数据层只保证每一跳检索能走通：库中没有的写法给出读音感知的近似名
（`name_similarity.dart`，只陈述"字符串相近"，`sql`/`grep` 零命中时自动附上）；身份由 Agent 在问答时读原文确认。
不要新增别名/身份表来"修"某个具体角色。没有目录表的库照常可用（引用显示由路径推出的名字）。

### 工具型剧情 Agent（R17，唯一流程）

- `LoreAgentLoop`（`lore_agent_loop.dart`）：一个模型 + `lore_tools.dart` 的通用工具（只读 `sql`、`grep`、
  `read_story`、`find`、`outline`、`similar_names`，主 agent 另有 `delegate` 派出并行子 agent），messages 只追加
  （前缀缓存命中约 85–90%）。R8–R16 的 `PlannerLoop` 及其状态/提取器/writer/COVER 等工具已删除（git 历史可查）。
- 不要往这条链路里加手写的进度规则（预算提示、重读拒绝、代码规则复核、阅读计划）：R13–R16 证明这类规则只对样例有效。
  改进方向是工具的表达力、工具输出的信息量和提示词里的通用工作方式。
- 审稿子 agent（R18，开发者同意）不是上面说的复核：它是另一次模型调用，只看问题和去掉出处的答案，以读者身份
  提最多三个“整个故事或其他故事是否改变了答案的理解”的问题；它的了解只是线索，结论由主 agent 读原文决定，
  每题一轮，失败就放行。不要让它逐条核实细节（实测会白白多出十几次调用），也不要给它加针对某类剧情的检查项。
- 按阶段整理（R18）：答案 JSON 有 5 条以上正文时，主 agent 再写一轮 `{"stages":[{"text","from":[条目号]}]}`，
  出处由代码按 `from` 合并（`lore_answer_stages.dart`），模型不写出处；整理版在 `[DETAILS]` 上方，详细版折叠在下方。
  整理那一轮不留在对话里，追问时对话停在详细版 JSON。段数、字数只在提示词里软性提示（一般不超过十段左右），
  不加硬性数字限制或代码截断（开发者要求：硬限制会伤害质量）。
- 出处：`story_id:起始行-结束行` 或 `record:<normalized_records.id>`，代码核对必须是工具实际给模型看过的
  （`SeenLines`）。写错的名字靠“模型用自身知识构造查询 + 零命中如实报告 + 自动附近名”解决，不加别名表。
- 提示词与工具说明里**不放任何具体人物、章节、活动或剧情示例**（开发者要求，2026-10）：示例会把模型带向那类问题，
  等于特化优化。需要示意格式时只用占位符（`X`、`<story_id>`、`main_<章>`）；`lore_agent_test.dart` 守卫。
  R18 起也不写具体剧情手法的名字（梦境、幻觉、叙诡等），只写“故事后来揭示了另一种性质”这类对任意故事成立的说法；
  守卫覆盖审稿和整理的提示词。
- 答案写给玩家（R17b）：正文不提库/表/文件名/id，用自己的话叙述；出处在每条末尾，界面把它们放到该条下面的证据链，
  点行号打开原文阅读页（`story_reader_page.dart`）。
- 主 agent 的最终答案是 JSON（R17c，`lore_answer_json.dart`）：条目 = 正文 + 出处元组，代码边流式边转成 markdown。
  提示词只说“不要用引号引用台词”，不要写“哪些可以加引号”（开发者判断：写了模型就会刻意用）；照搬台词由代码检查、退回一次。
- 只读 SQL（`readonly_sql.dart`）：单条 SELECT/WITH、拒绝写/ATTACH/PRAGMA、只读连接、每次查询一个 isolate、
  超时用 `sqlite3_interrupt` 在 SQLite 内部中止（工作 isolate 等主 isolate 说 close 才关连接，避免中止已释放的连接）。

### 思考强度与流式（R16）

- 思考档位用 `llmClientProvider(ReasoningLevel.off|low|high)`（`llm_provider.dart`）。deepseek 不传参数
  时默认开启 high 档，所以每个角色都必须显式指定档位。现在全部默认 `off`；只有“深度思考”开关
  （`deepThinkingProvider`）让本问的 Agent 用 `low`。不要给剧情问答开 `high`：开发者实测剧情过度思考
  会延伸推测原文没写的内容。
- 各家的思考开关在 `OpenAICompatibleClient.reasoningFieldsFor`：deepseek（`thinking` + `reasoning_effort`）、
  百炼（`enable_thinking`）、智谱 GLM（`thinking`，无强度档，low = high，按 host `z.ai`/`bigmodel.cn` 或模型名 `glm*` 识别）；
  其他 provider 不发字段。智谱只接受 `tool_choice: auto`，所以对它不发 `none`（最后一轮和 R18 整理段落时
  模型仍可能调用工具：前者按答案处理，后者回退为只显示详细答案）。429 按 `Retry-After` 或 2/5/10 秒重试三次。
- 服务商因思考字段报 400/422（错误里提到 thinking/reasoning）时，该 client 去掉思考字段重发、之后不再发；
  拒绝 `stream_options` 时先去掉它再流式重发，仍被拒才改为非流式。
- **默认模型是智谱 `glm-5.3-flash`**（`https://api.z.ai/api/paas/v4`，2026-10 开发者决定：写作更好）。
  官方文档：它**不能关闭思考**（`thinking.type` 只支持 `enabled`）——所以每一轮都会思考，“深度思考”开关对它无效，
  上面“全部默认 off、不开 high”的约束在这个模型上做不到，答案是否因此推测过度要在真机/live 测试里看。
  已保存过设置的用户不受影响（URL、key、模型三项总是一起保存）。
- R17/R18 文档里的验收数据是 deepseek 测的，换模型后调用次数、token、缓存命中率都要重新测。
- 流式：`LLMClient.streamTurn`（带 tools；默认实现调用一次 `chatCompletion`，测试假 client 可直接覆盖它）。
  Agent 依次发 `status` / `toolCall` / `toolObservation` / `finalAnswerToken`… →（继续查资料或出处退回时
  `finalAnswerReset`）→ `finalAnswerReplace`（信封 + 核对后正文）。测试取答案用 `finalAnswerOf(events)`。
- 状态：没有核对通过的出处 → `not_covered`；模型写 `[COVERAGE: gaps]` 或到轮数上限 → `partial`；否则 `answered`。
- 界面（R17d，开发者要求）：问答列表**不随流式内容自动滚动**（只在发新问题时滚到底一次）；思考窗口固定高度、
  内部也不跟随；阅读位置上方的内容在流式中不得变高变矮。不要再加“贴底跟随”。
- 颜色：Endfield 的信号黄（`accentPrimary`）只做填充和粗线；文字、图标、细边框用 `accentText`，黄底上的前景用 `onAccent`。

### 剧情向量（可选表，R12）

`story_chunk_vectors` 是 schema 4 上的**可选附加表**（`schema_version` 不变，
没有该表的库照常可用，`find` 退化为关键词检索）。构建（可续跑、按内容哈希缓存）：

```bash
dart run tools/build_story_embeddings.dart --db=build/gamedata_mobile/arklores_gamedata_zh.db
```

manifest 记录 `embedding_model / embedding_dims / embedding_chunking`；App 只在
所配置的向量模型和维度与 manifest 一致时才启用语义检索。向量命中只是定位线索，
必须 `read_story` 读到原文后才能作为证据（检索原则 5）。

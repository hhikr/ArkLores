# 验收清单

> 每次改动后按范围选做。离线部分不花钱；真实服务的部分按 CLAUDE.md 的成本约束（测试模型 glm-5.3-flash，预计一轮超过 150 万 token 先问开发者）。
> 测试目录与夹具见 `test/README.md`。PowerShell 里路径写绝对路径（sqflite FFI 会把相对路径解析到 `.dart_tool` 下）。

## 1. 每次提交

```powershell
flutter analyze
flutter test --concurrency=2   # 约 1 分钟，全部离线
```

守卫测试（随 `flutter test` 运行）：

- `test/guards/no_special_case_test.dart`：`lib/` 里没有问题类型特判（`culprit|suspect|嫌疑|凶手|罪魁`）。
- `test/guards/floating_docks_test.dart`：`lib/` 里没有 `AppBar`。
- `test/guards/square_shapes_test.dart`：没有圆角、圆形、`_rounded` 图标和回弹曲线。
- `test/core/agent/lore_agent_loop_test.dart`：提示词与工具说明里没有具体人物/章节/活动名和剧情手法名。
- `test/shared/app_version_test.dart`：`app_version.dart` 与 `pubspec.yaml` 一致。

本地探针（对真实库的一次性测量、截图）放 `notes/probes/`（不提交、不在 `test/` 下，全量测试不编译它们），用 `flutter test notes/probes/<文件>` 单独跑。

## 2. 改了建库代码

| 检查 | 命令 / 做法 |
| --- | --- |
| 单元测试 | `flutter test test/core/gamedata`（生产 schema 夹具、小源码树 `support/source_fixture.dart`、`fake_github.dart`） |
| 规则影响面 | 在 `notes/` 写探测脚本对真实库计数（改前、改后各一次） |
| 真实库验收 | `$env:ARKLORES_RUN_DB_CHECK='true'; $env:ARKLORES_GAMEDATA_DB='<库>'; flutter test test/live/gamedata_v5_acceptance_test.dart` |
| 新建 = 增量 = 补算 | 一致性实验（`KNOWLEDGE_BASE_LESSONS.md` §4），改了建库结构时必做 |
| 与上一版逐表对比 | 新旧库每张表逐行比（2026-10-19 重建时的做法：只允许预期的差别和 `updated_at`） |
| 新名字 | `rederive_gamedata.dart` 末尾的 `unnamed kind:` 逐个去 prts.wiki 查 |
| 向量 | 迁移后向量条数与旧库一致，`--dry-run` 显示 0 块需要嵌入（或只有真正新增的） |
| 安装 | `$env:ARKLORES_RUN_ASSET_INSTALL='true'`（+ `ARKLORES_ASSET_URL/SHA`）跑 `test/live/release_asset_install_live_test.dart` |

终末地库：

| 检查 | 命令 / 做法 |
| --- | --- |
| 单元测试 | `flutter test test/core/gamedata/build/endfield test/core/gamedata/multi_game_retrieval_test.dart` |
| 重建 | `.\tools\unpack_endfield.ps1 -SkipUnpack`（客户端更新后去掉 `-SkipUnpack`）；它会改 `ENDFIELD_DB_SHA256`，不发布时还原 `tools/release_gamedata.env` |
| 真实库验收 | `$env:ARKLORES_RUN_EF_CHECK='true'; $env:ARKLORES_ENDFIELD_DB='<库>'; flutter test test/live/endfield_acceptance_test.dart`（安装器校验、`ef/` id、每篇有条目/集合/目录、无标记与男女双写、没有原样输出的 `{id:` 文字对象、图鉴里没有零散文档、每项调查带报告、一个任务一篇、章节分组、步骤标题后面有对话、“未定位的对话”在最后、每个任务的集合都有剧情、向量覆盖） |
| 按步骤排列 | 和不加 `--data` 建的库逐篇比：去掉 `step`/`stage`/`unplaced` 行后每篇的行（多重集合）相同、故事一篇不少；改了排列规则时读 `story_order_report.md` 里改动涉及的任务（`ENDFIELD_STORY_ORDER.md` §5–6） |
| 换了客户端 | 和上一份库逐表、逐集合比：新增与删除的集合和故事、行数变少的故事（看是不是选项或内容真的变了）、未实装书架的增减（新进未实装的要确认没有任务定义播放它的对话） |
| 确定性 | 建两次逐表比对 |
| 读起来对不对 | 挑两三个任务对照 warfarin.wiki / fz.wiki 的同一任务页 |
| 向量 | 重建后先 `build_story_embeddings.dart --migrate-from=<旧库> --dry-run` |

## 3. 改了问答 Agent / 检索工具

离线（mock LLM）：

- `test/core/agent/lore_agent_loop_test.dart`：只读 SQL、工具输出、只追加、出处核对与退回、子 agent、文本协议回退、折叠、追问与重读、查证“没有查到”。
- `test/core/agent/coverage_test.dart`、`line_picker_test.dart`、`lore_tools_test.dart`、`test/core/gamedata/*`：取材、检索工具、检索面。
- `test/core/llm/openai_client_test.dart`：各服务商的怪癖、429 重试、中断请求。
- `test/features/ai/*`：答案气泡、工作过程、出处、输入框。
- Wiki：见 `WIKI.md` §9。

**离线召回测试**（免费；改了第一批查找、取材、检索时必做）：

```powershell
$env:ARKLORES_RUN_RECALL_EVAL='true'
$env:ARKLORES_GAMEDATA_DB="$PWD\build\gamedata_rebuild\arklores_gamedata_zh.db"
$env:ARKLORES_ENDFIELD_DB="$PWD\build\endfield\arklores_endfield_zh.db"
$env:ARKLORES_RECALL_VECTORS="$PWD\build\recall_eval\query_vectors.json"
$env:ARKLORES_RECALL_VARIANTS='planner+coverage30,planner+c2-45'   # 可选
$env:ARKLORES_RECALL_IDS='slum_fate,talulah_after'                 # 可选
flutter test test/live/recall_eval_test.dart                      # 报告在 build/recall_eval/report.md
```

- 查询向量已缓存；`ARKLORES_RECALL_EMBED=true` 才调向量服务补新的查询（花钱，量很小）。
- `ARKLORES_RECALL_PICK=true` 加挑行方案（调真实模型）；`ARKLORES_RECALL_CARDS=<build/scene_cards>` 加场景卡方案。
- 金标在 `test/fixtures/recall_eval.json`；库要用带 act52side 的（v0.14.0 起的明日方舟库），更旧的库金标检查会失败。

**真实模型**（`test/live/ask_pipeline_live_test.dart`）：

```powershell
$env:ARKLORES_RUN_LIVE_ASK='true'; $env:ARKLORES_LIVE_QUERIES='问题一||问题二'
$env:ARKLORES_LIVE_CONVERSATION='true'          # 可选：几问连成一段对话
$env:ARKLORES_GAMEDATA_DB='<库>'; $env:ARKLORES_ENDFIELD_DB='<库>'
flutter test test/live/ask_pipeline_live_test.dart
```

`ARKLORES_LIVE_EVAL` / `ARKLORES_LIVE_IDS` 选评测题；`ARKLORES_LIVE_NO_EMBEDDING=true` 模拟无向量。输出在 `build/live_sessions/`（会话 JSON、`*.summary.json`）。

| 项 | 预期 |
| --- | --- |
| 出处 | 全部是工具给模型看过的 |
| 负例 | 未覆盖的实体/事件说“没查到”，状态 `not_covered` |
| 无向量 | `search` 退回关键词并写明原因 |
| 成本 | 记录 `usage`；缓存命中占输入 80% 以上 |
| 宽问题 | 跨多个故事集的人物经历：关键阶段齐全 |
| 写错的名字 | 按库中写法作答并说明 |
| 追问 | 第二问开头有代码重读上一答引用的行 |
| Wiki | 库里有原文的事实引原文；Wiki 出处只用在库里没有的内容并写明 |

比较两版代码时每边跑几次：单次运行波动很大，answered 的比例不是质量指标（`ASK_EXPERIMENTS.md` §1）。

## 4. 改了界面

- 对应的 widget 测试（`test/features/**`、`test/app_test.dart`），窄屏与大字下无溢出。
- 资料页布局截图：`$env:ARKLORES_SHOT_DIR='<目录>'; flutter test test/features/library/library_ui_test.dart`（Ahem 字体，只看布局）。
- WebView、前台服务、输入法焦点、滚动手感：只能真机（由开发者自己看）。

## 5. 发版前

- 第 1 节全部通过；知识库有变化时做第 2 节的真实库验收与安装。
- `tools/release_gamedata.env` 指向将要创建的 Release 资产，SHA 与 gz 一致，`GAMEDATA_DB_COMMIT` / `GAMEDATA_DB_COMMIT_DATE` 与库一致。
- 本机 `tools/install_local.ps1 -Build -Kb` 装一遍，开发者真机确认。

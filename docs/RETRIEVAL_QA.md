# 验收清单

> 每次改动后按范围选做。离线部分不花钱；真实 API 部分按 CLAUDE.md 的成本约束（开发者同意、每方面最多 2 个用例、逐题串行）。
> 测试目录结构与夹具见 `test/README.md`。

## 1. 每次提交

```bash
flutter analyze
flutter test        # 约 1 分钟，全部离线
```

守卫测试（随 `flutter test` 运行）：

- `test/guards/no_special_case_test.dart`：`lib/` 里没有问题类型特判（`culprit|suspect|嫌疑|凶手|罪魁`）。
- `test/guards/floating_docks_test.dart`：`lib/` 里没有 `AppBar`（页面用 `FloatingScaffold`）。
- `test/guards/square_shapes_test.dart`：没有圆角、圆形、`_rounded` 图标和回弹曲线。
- `test/core/agent/lore_agent_loop_test.dart`：提示词与工具说明里没有具体人物/章节/活动名、没有具体剧情手法名。
- `test/shared/app_version_test.dart`：`app_version.dart` 与 `pubspec.yaml` 一致。

## 2. 改了建库代码

| 检查 | 命令 / 做法 |
| --- | --- |
| 单元测试 | `flutter test test/core/gamedata`（夹具用生产 schema 与小源码树 `support/source_fixture.dart`，GitHub 用 `fake_github.dart`） |
| 规则影响面 | 在 `notes/` 写探测脚本对真实库计数（改前、改后各一次） |
| 真实库验收 | `$env:ARKLORES_RUN_DB_CHECK='true'; flutter test test/live/gamedata_v5_acceptance_test.dart`（`ARKLORES_GAMEDATA_DB` 指向库，绝对路径） |
| 固定检索 | `dart run tools/check_gamedata_retrieval.dart --db=<库>` |
| 新建 = 增量 = 补算 | 一致性实验（`KNOWLEDGE_BASE_LESSONS.md` §4），改了建库结构时必做 |
| 新名字 | `rederive_gamedata.dart` 末尾的 `unnamed kind:` 逐个去 prts.wiki 查 |
| 向量 | 迁移后向量条数与旧库一致，`--dry-run` 显示 0 块需要嵌入（或只有真正新增的） |
| 安装 | `$env:ARKLORES_RUN_ASSET_INSTALL='true'`（+ `ARKLORES_ASSET_URL/SHA`）跑 `test/live/release_asset_install_live_test.dart`，桌面完整下载安装一遍 |

### 终末地库（0.12）

| 检查 | 命令 / 做法 |
| --- | --- |
| 单元测试 | `flutter test test/core/gamedata/build/endfield test/core/gamedata/multi_game_retrieval_test.dart`（合成的小表组） |
| 重建 | `.\tools\unpack_endfield.ps1 -SkipUnpack`（客户端更新后去掉 `-SkipUnpack`），会更新 `ENDFIELD_DB_SHA256` |
| 真实库验收 | `$env:ARKLORES_RUN_EF_CHECK='true'; flutter test test/live/endfield_acceptance_test.dart`：安装器校验、`ef/` id、每篇剧情有条目/集合/目录、无标记与男女双写、名字不是 id、内容计数、一个任务一篇且以分段行开头、主线任务带章节分组、向量覆盖每篇且落在原文行内 |
| 确定性 | 建两次逐表比对（两次构建应完全一致） |
| 读起来对不对 | 挑两三个任务对照 warfarin.wiki / fz.wiki 的同一任务页：选项的位置与分支回应、段落种类、有无漏段（`test/live/scratch` 下的查看脚本，不提交） |
| 向量 | 重建后先 `build_story_embeddings.dart --dry-run`：结构改动不该让 `to embed` 变多（切块在 `section` 处断开，文字不变就命中缓存） |

## 3. 改了问答 Agent / 检索工具

离线（mock LLM）：

- `test/core/agent/lore_agent_loop_test.dart`：只读 SQL 边界与超时中止、各工具输出、只追加的请求、出处核对与退回、子 agent、文本协议回退、上下文折叠、追问。
- `test/core/agent/tools/search_story_lines_test.dart`、`test/core/gamedata/*`：关键词/向量/RRF、近似名、目录。
- `test/core/llm/openai_client_test.dart`：各服务商的怪癖（`LLM_PROVIDERS.md`）。
- `test/features/ai/*`：答案气泡、工作过程时间线、出处、输入框。
- Wiki（0.13）：`test/core/wiki/*`、`test/core/agent/lore_agent_wiki_test.dart`、`test/features/ai/wiki_citations_test.dart`；
  联网（免费）：`$env:ARKLORES_RUN_WIKI_CHECK='true'; flutter test test/live/wiki_live_test.dart`（两站各搜一次、读一页）。

真实 API（opt-in，花钱）：`test/live/ask_pipeline_live_test.dart`，用法见 CLAUDE.md。验收项：

| 项 | 预期 |
| --- | --- |
| 出处 | `story_id:行号` 或 `record:<id>`，全部是工具给模型看过的 |
| 负例 | 未覆盖的实体/事件说“没查到”，状态 `not_covered` |
| 无向量 key | `ARKLORES_LIVE_NO_EMBEDDING=true` 时 `find` 退回关键词并写明原因 |
| 成本 | 记录 `usage`；缓存命中应占输入 80% 以上 |
| 宽问题 | 跨多个故事集的人物经历：关键阶段齐全，可能派子 agent |
| 写错的名字 | 按库中写法作答并在开头说明 |
| 追问 | `ARKLORES_LIVE_CONVERSATION=true`：第二问能引用第一问读过的行 |
| Wiki（0.13） | 库里有原文的事实引用原文；Wiki 出处只用在库里没有的内容，正文写明“据 Wiki 整理”；Wiki 不可用时照常作答 |

## 4. 改了界面

- 对应的 Widget 测试（`test/features/**`、`test/app_test.dart`），窄屏与大字下无溢出。
- 资料页布局截图：`$env:ARKLORES_SHOT_DIR='<目录>'; flutter test test/features/library/library_ui_test.dart`（Ahem 字体，只看布局）。
- WebView（Wiki）、前台服务、输入法焦点、滚动手感：只能真机。

## 5. 发版前

- 第 1 节全部通过；知识库有变化时第 2 节的真实库验收与安装。
- `tools/release_gamedata.env` 指向将要创建的 Release 资产，SHA 与 gz 一致。
- 本机 `tools/install_local.ps1 -Build -Kb` 装一遍（开发者真机确认）。

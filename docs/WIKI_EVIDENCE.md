# Wiki 检索与证据（0.13）

问答 Agent 除了本地知识库，还可以联网查两个游戏的 Wiki，把读到的段落作为第三种出处。本文是设计、实现位置与维护说明。
Agent 怎样用见 `R17_TOOL_AGENT.md`，界面上的 Wiki 浏览见 `WIKI_SITE_ADAPTATION.md`。

## 1. 定位：二手资料，不取代原文

- 本地知识库是游戏解包原文，仍是剧情事实的依据；Wiki 是社区编写的整理与解读，可能有错漏，也可能有库里没有的内容
  （游戏外的官方资料、库之后才上线的内容、整理好的人物关系与设定）。
- 提示词（`loreWikiGuide`）要求：能在库里读到原文的引用原文；Wiki 用来定位、补充库里确实没有的内容、对照核实；
  两者不一致时以原文为准、两处都写明；只有 Wiki 支持的说法在正文里写明“据 Wiki 整理”。
- 同一套出处核对：Wiki 段落只有 `wiki_read` 实际展示过的才能引用（`SeenLines`），照搬原句同样退回改写。不加任何针对题型的规则。

## 2. 站点选择

| 游戏 | 站点 | 接口 |
|---|---|---|
| 明日方舟 | PRTS（prts.wiki，MediaWiki） | `api.php`：`list=search`（主命名空间）搜索；`action=parse&prop=text\|revid` 取页面 HTML 与修订号 |
| 终末地 | Warfarin Wiki（warfarin.wiki） | `api.warfarin.wiki/v1/cn/search?q=` 全文搜索（JSON，结果带 type/slug）；页面 `warfarin.wiki/cn/<type>/<slug>` 服务端渲染，读 `<main>` |

终末地选 Warfarin 而不是 fz.wiki：Warfarin 有公开的 JSON 搜索接口、页面服务端渲染、有简体中文版，覆盖干员、任务剧情、Baker、情报档案；
fz.wiki 没有找到公开接口，且 2026-10-09 在开发机上连不上（命令行超时，浏览器显示站点的“离线”页）。App 的 Wiki 标签默认的终末地站点也是 Warfarin。
以后要加 fz.wiki，只需实现一个 `WikiSource`。

请求都带可识别的 User-Agent（`wikiRequestHeaders`）：PRTS 的 API 对匿名与浏览器式 UA 返回 403，带项目 UA 正常（2026-10-09 实测）。

## 3. 页面 → 段落

`wiki_html_text.dart`（`package:html`），只用通用规则：标题开小节；段落、列表项各一段；表格每行一段（单元格用 ` | ` 连）；
去掉脚本、样式、按钮、图片、导航框、目录、编辑链接、脚注标记、隐藏元素；**多半是数字的行不收**（属性/倍率表，属于玩法文字）。
不写任何站点或页面的专门版式。Warfarin 干员页仍会留下一些只有名词的短段（材料名、技能名），由 Agent 用 `section` 跳过。

## 4. 页面 id、版本与快照

- 页面 id：`wiki:<站点>:<页面键>@<版本>`。页面键：PRTS 是 pageid，Warfarin 是 `<type>/<slug>`；版本：PRTS 是修订号，Warfarin 是正文的 SHA-1 前 8 位。
- 出处：页面 id 加段号，`wiki:prts:1751@434838:132-135`；答案 JSON 里写 `["<页面 id>", 起始段, 结束段]`，与剧情出处同形（`lore_answer_json.dart`）。
- 每次取到的版本存为快照（`WikiSnapshotStore`，App 文档目录 `wiki_snapshots/`，每版一个 JSON，超过 400 个删最旧的）：
  页面之后被编辑、离线、重启后，引用仍显示 Agent 当时读到的段落。快照只在本机，别的设备上打开同一会话时提示“没有保存在本机”，可去 Wiki 看当前版本。
- 同一页面 30 分钟内不重复请求（`WikiLookup.cacheTtl`）。

## 5. 代码位置

| 部分 | 文件 |
|---|---|
| 模型、id、出处格式 | `lib/core/wiki/wiki_page.dart` |
| HTML → 段落 | `lib/core/wiki/wiki_html_text.dart` |
| 两个站点 | `lib/core/wiki/wiki_sources.dart` |
| 缓存与快照 | `lib/core/wiki/wiki_lookup.dart`；provider `wiki_provider.dart` |
| 工具 `wiki_search` / `wiki_read` | `lib/core/agent/tools/wiki_tools.dart` |
| 提示词 | `loreWikiGuide`（`lore_agent_prompts.dart`，只在开启时并入） |
| 出处核对、引语检查、审稿标签 | `lore_agent_loop.dart`（`wikiCitationPattern`） |
| 开关 | `AnswerOptions.wiki`（输入框“回答选项”菜单的“Wiki 资料”，默认开） |
| 答案里的出处 | `investigation_ui.dart`（`AnswerBlock.wikis`）、`story_answer_body.dart`（证据卡的 Wiki 行、`WikiCitationSheet`）、`chat_bubble.dart`（出处树、工作过程） |
| 在 Wiki 标签打开 | `wikiOpenRequestProvider`（`handoff_provider.dart`），`WikiBrowserPage` 监听 |

## 6. 失败与离线

网络错误、超时（20 秒）、HTTP 错误都变成 `WikiUnavailable`，工具返回“<站点> 暂时无法访问（原因）。请只用本地知识库作答”，
时间线把这一步标为出错；提示词要求不反复重试、在 gaps 里说明。关掉“Wiki 资料”时工具和提示词那一节都不出现，与 0.12 的行为相同。

## 7. 验收

- 离线：`test/core/wiki/*`（HTML 规则、两个站点的请求与解析用 `MockClient`、快照与缓存）、`test/core/agent/lore_agent_wiki_test.dart`
  （工具输出、出处核对与退回、引语检查、Wiki 不可用时继续作答）、`test/features/ai/wiki_citations_test.dart`（解析、时间线、证据卡与快照弹窗、在 Wiki 打开）。
- 联网（免费）：`$env:ARKLORES_RUN_WIKI_CHECK='true'; flutter test test/live/wiki_live_test.dart`，两个站点各搜一次、读一页。
- 真实模型：`ask_pipeline_live_test.dart` 默认就带 Wiki 工具。
- 界面截图：用真实页面快照渲染证据卡与引用弹窗（本地 scratch 测试，加载文楷字形），布局正常。
- 真机（2026-10-09，发版前同一构建）：只看到“回答选项”里的 Wiki 开关；带 Wiki 出处的答案还没在手机上看过（`KNOWN_LIMITATIONS_AND_DEBT.md` §6）。

### 2026-10-09 真实模型验收（`tools/api_info` 的模型，复核与提要开着）

| 问题 | 工具 | 结果 |
|---|---|---|
| 阿米娅档案里提到的萨卡兹君王奎隆是谁？与阿米娅的关系（第一次） | sql 24、grep 5、read_story 10、find 1；**没有用 Wiki** | 答案只依据原文，结尾写“档案里没检索到奎隆”（库里没有阿米娅的升变档案，PRTS 有）→ 提示词加一条通用规则：库里换写法仍查不到时，先查一次 Wiki 再下“没有记载” |
| 同上（加规则后） | sql 38、grep 5、read_story 5、wiki_search 2、wiki_read 1；49 次调用，提示 104 万 token（缓存 96%） | answered；主体全部引原文，只用 Wiki 补了库里没有的一点并写明“据 PRTS Wiki 整理”，Wiki 出处通过核对。Wiki 上仍没找到升变档案那一页（搜索命中别的页面） |
| 终末地佩丽卡的中文配音演员、在终末地工业负责什么 | sql 5、grep 9、read_story 1、wiki_search 2、wiki_read 2；21 次调用，48 万 token（缓存 92%），117 s | answered；配音只有 Wiki 有，引 Warfarin 段落并写明来自玩家 Wiki；职务与经历全部引库里原文 |

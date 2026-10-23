# Wiki：浏览与问答取证

> App 里 Wiki 有两种用法：**Wiki 标签**用 WebView 浏览站点（§1–3）；**问答**联网查 Wiki，把读到的段落作为二手出处（§4–9，0.13 起）。

## 1. 浏览：站点与标签

| ID | 来源 | 前端 | 主题机制 |
| --- | --- | --- | --- |
| `prts` | PRTS Wiki | MediaWiki | 站点自带的黑夜模式：`skin-theme-clientpref-night/day` class |
| `endfield` | 终末地 Wiki（设置里选 fz.wiki 或 Warfarin） | 按当前 URL 选站点策略 | 见 §2 |

- 终末地 Wiki 只占一个标签。设置页编辑来源时，URL 输入框下方有 `Warfarin` 与 `fz.wiki` 预设；旧版分别保存的 `endfield-warfarin` / `endfield-fz` 折叠为一个 `endfield` 来源。
- 代码：`features/wiki/wiki_browser_page.dart`（`flutter_inappwebview`）、`wiki_site_adapter.dart`（按 hostname 选策略）、`wiki_appearance.dart`、书签 `bookmark_service.dart`。

## 2. 浏览：主题桥接

只修改站点已经定义的主题状态，不对第三方页面做全量反色。桥接脚本在 WebView 的 document-start 运行，并把当前模式短暂存在 sessionStorage，减少导航与重载时的白闪。

- **PRTS**：只在 `html` 与 `body` 上切 `skin-theme-clientpref-night` / `-day`（去掉 `-os`），document-start 时先切 `html`；不注入任何样式（2026-10-17 起）。站点改了切换方式时要跟着改；没在真机上核对。
- **fz.wiki**：站点自己维护 `endfield-wiki-theme` localStorage，根节点用 `data-theme="light|dark"`；只设置这个属性、同步持久化状态与 `theme-color`。
- **Warfarin**：CSS 用 `.dark` 切换一组语义变量；只切 `html.dark`、设置 `color-scheme` 与 `theme-color`，不直接覆盖变量。

## 3. 浏览：顶栏、底栏与从问答打开

- App 的顶部站点栏（`MainTopBar`）和底部标签栏盖在网页上，网页铺满屏幕。网页不能从外部留白，所以 `_applyDockInsets` 注入样式：给 `html` 上下加两条栏高度的 padding，并把站点自己 `fixed`/`sticky` 的栏同样平移；每次 build 用 `_syncDockInsets` 同步高度。**新增站点时要真机确认它的固定栏没被盖住。**
- 答案里的 Wiki 出处弹窗有“在 Wiki 中打开”：写 `wikiOpenRequestProvider`（站点 id + 网址）并切到 Wiki 标签，`WikiBrowserPage` 按站点 id（找不到时按域名）选标签加载；标签没恢复好时先记下。
- 阅读器模式与“转交给 AI”已在 2026-10-17 删除：长文在资料页里读，问答自己会查 Wiki。剧情模拟器、图鉴交互、动态数据表保留为站点原生组件。

## 4. 取证：定位

- 本地知识库是游戏解包原文，是剧情事实的依据；Wiki 是社区编写的整理与解读，可能有错漏，也可能有库里没有的内容（游戏外的官方资料、库之后才上线的内容、整理好的人物关系）。
- 0.14 起 Wiki 与本地库是**同级的检索来源**：`search` 同时给出 Wiki 页面。**答案仍区分来源**（开发者决定）：出自 Wiki 的说法写明“据 Wiki 整理”，原文能印证的同时引原文，冲突时两处都写、以原文为准（`loreWikiGuide`）。
- 同一套出处核对：Wiki 段落只有 `wiki_read` 实际展示过的才能引用（`SeenLines`）。

## 5. 取证：站点接口

| 游戏 | 站点 | 接口 |
|---|---|---|
| 明日方舟 | PRTS（prts.wiki，MediaWiki） | `api.php`：`list=search`（主命名空间）；`action=parse&prop=text\|revid` 取页面 HTML 与修订号 |
| 终末地 | Warfarin（warfarin.wiki） | `api.warfarin.wiki/v1/cn/search?q=` 全文搜索（JSON，带 type/slug）；页面 `warfarin.wiki/cn/<type>/<slug>` 服务端渲染，读 `<main>` |

- 终末地选 Warfarin：有公开 JSON 搜索接口、服务端渲染、简体中文，覆盖干员、任务剧情、Baker、情报档案。fz.wiki 当时没找到公开接口、开发机上连不上；2026-10-21 已能连上，并有 JSON 接口（见 `KNOWN_ISSUES.md` §6）。要加 fz.wiki 时实现一个 `WikiSource`。
- 请求带可识别的 User-Agent（`wikiRequestHeaders`）：PRTS 的 API 对匿名与浏览器式 UA 返回 403，带项目 UA 正常。

## 6. 取证：页面 → 段落、id、快照

- `wiki_html_text.dart` 只用通用规则：标题开小节；段落、列表项各一段；表格每行一段（单元格用 ` | ` 连）；去掉脚本、样式、按钮、图片、导航框、目录、编辑链接、脚注、隐藏元素；**多半是数字的行不收**（玩法数据）。不写站点或页面的专门版式。
- 页面 id：`wiki:<站点>:<页面键>@<版本>`。PRTS 的页面键是 pageid、版本是修订号；Warfarin 是 `<type>/<slug>`、版本是正文 SHA-1 前 8 位。
- 出处：页面 id 加段号，`wiki:prts:1751@434838:132-135`；答案 JSON 里写 `["<页面 id>", 起始段, 结束段]`。
- 每次取到的版本存为快照（`WikiSnapshotStore`，App 文档目录 `wiki_snapshots/`，每版一个 JSON，超过 400 个删最旧的）：页面之后被编辑、离线、重启后，引用仍显示 Agent 当时读到的段落。快照只在本机。
- 同一页面 30 分钟内不重复请求（`WikiLookup.cacheTtl`）；同一个站点同一个词的搜索合并成一次请求；`search` 等 Wiki 最多 8 秒。

## 7. 取证：代码位置

| 部分 | 文件 |
|---|---|
| 模型、id、出处格式 | `lib/core/wiki/wiki_page.dart` |
| HTML → 段落 | `lib/core/wiki/wiki_html_text.dart` |
| 两个站点 | `lib/core/wiki/wiki_sources.dart` |
| 缓存与快照 | `lib/core/wiki/wiki_lookup.dart`；provider `wiki_provider.dart` |
| 工具 `wiki_search` / `wiki_read` | `lib/core/agent/tools/wiki_tools.dart` |
| 提示词 | `loreWikiGuide`（`lore_agent_prompts.dart`，只在开启时并入） |
| 出处核对 | `lore_agent_loop.dart`（`wikiCitationPattern`） |
| 开关 | `AnswerOptions.wiki`（输入框选项面板的“Wiki 资料”，默认开） |
| 答案里的出处 | `features/ai/investigation_ui.dart`、`widgets/story_answer_body.dart`（`WikiCitationSheet`）、`widgets/chat_bubble.dart` |

## 8. 取证：失败与离线

网络错误、超时（20 秒）、HTTP 错误都变成 `WikiUnavailable`，工具返回“<站点> 暂时无法访问（原因）。请只用本地知识库作答”，工作过程把这一步标为出错。关掉“Wiki 资料”时工具和提示词那一节都不出现。

## 9. 验证

- 浏览（每次改站点适配）：`flutter test test/features/wiki/`；真机分别看 fz（亮/暗、页内跳转、重载）、Warfarin（亮/暗、语言路由、干员页）、PRTS（亮/暗、页内跳转）。
- 取证离线：`test/core/wiki/*`、`test/core/agent/lore_agent_wiki_test.dart`、`test/features/ai/wiki_citations_test.dart`。
- 联网（免费）：`$env:ARKLORES_RUN_WIKI_CHECK='true'; flutter test test/live/wiki_live_test.dart`，两个站点各搜一次、读一页。
- 真实模型（2026-10-09）：库里没有的内容（阿米娅档案里的一个名字），没有规则时不查 Wiki；加“换写法仍查不到先查一次 Wiki”后会查，只用 Wiki 补库里没有的一点并写明来源，但 49 次调用、104 万输入。
  佩丽卡的配音只有 Wiki 有：引 Warfarin 段落并写明来源，职务与经历引库里原文。

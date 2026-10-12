# 2026-10-12 真机反馈与问答会话的调查

> 配套 `docs/KNOWN_LIMITATIONS_AND_DEBT.md` §8。本文只记录调查过程与证据，问题的现状与优先级以该文档为准。
> 调查只读了代码与会话记录，没有改动代码，也没有运行 App。

## 一、问答：“佩丽卡 幕后高层”跨游戏时间线题

同一问题、同一模型（glm-5.3-flash），六个会话只有措辞与“多参考明日方舟”等附加要求不同。会话 ID 为前 8 位。

| 会话 | 状态 | 迭代 | 工具调用 | 明日方舟库查询 | 耗时 |
| --- | --- | --- | --- | --- | --- |
| 48421c72 | 取消（ASK_CANCELED，无答案） | 32 | 31 | 1 次（`search game=arknights`） | 191 s |
| c16c423d | completed，partial | 40 | 39 | 2 次 | 477 s |
| 2b0dcb66 | completed，partial | 10 | 9 | 0 | 114 s |
| 3aa263ab | completed，partial | 19 | 18 | 0（问题里明说“多参考明日方舟”） | 170 s |
| 8237d54f | completed，partial | 22 | 21 | 0 | 222 s |
| d6c7cd2e | completed，partial | 7 | 6 | 0 | 61 s |

### 观察到的问题

1. **明日方舟库几乎不被查。** 六次里 0–2 次，没有一次围绕 M3、凯尔希、博士的身份去查。3aa263ab 的问题明说要参考明日方舟，仍然 0 次。
2. **没有从“样子”推到人物。** 模型把“你的样子——”当成悬念本身，只在终末地库和 Warfarin 里反复搜“创始人”，没有去找“谁的样子会让佩丽卡认不出”。
3. **先定猜测、再找证据。** 8237d54f 的 `wiki_search` 直接搜“创始人 猜测 博士 特蕾西娅”，3aa263ab 搜“终末地 特蕾西娅”。这些名字来自玩家社区的猜测，原文里没有。
4. **M3 与凯尔希的联系没有被串起来。** 只有 c16c423d 搜过一次“M3 罗德岛 凯尔希 博士”，也没有读到能证明联系的档案。
5. **“时间不多了”没有与角色状态对照。** 原文只有这句，要与凯尔希的存续状态（明日方舟侧）对照，模型没有去查。
6. **Wiki 跑偏。** 3aa263ab 读了 PRTS《Mon3tr》两段，然后推到“预言家/非人存在”，离问题很远。
7. **答案主体是玩家猜测。** 2b0dcb66 等把社区说法写成主要结论，与“Wiki 只补库里没有的、并写明”的原则不符。

### 明日方舟库里的证据

- `story_lines` 中“凯尔希”与“复活”同现的行只有 1 条（`obt/main/level_main_14-04_end.txt`）。
- “时间不多了”在明日方舟库里很多，多为通用台词。
- 结论：“凯尔希复活后以泰拉人身份存续、不再长寿”这一说法，库里的依据需要读实体条目、档案或主线原文确认，不能只靠这一句台词。

### 理想路径的拆解

1. 锁定终末地中的高位人物（M3、华法林）并否定。这一步已经做到。
2. 用“样子让佩丽卡惊讶”去找：谁的样子她认得、并且与高位人物相似。需要读佩丽卡与 M3、华法林的互动，而不是只搜“创始人”。
3. 没被要求查明日方舟时，也主动去明日方舟库搜这种本质联系（M3 与凯尔希，管理员与博士）。这需要工具层的通用提示或搜索规划，不能写成针对这道题的分支。
4. 对候选人去查各自的状态（凯尔希复活后的身份与寿命），再与“时间不多了”对照。
5. 排序给出结论。

约束（CLAUDE.md）：不加“凯尔希/博士”的判断分支，不加跨游戏时间线模式。改进只能是通用的，并且要先离线复现，真实模型测试要先问开发者。

## 二、界面反馈

### 1. 问答里资料弹窗渲染的是原始 markdown（bug）

- 故事引用：`lib/features/ai/widgets/story_answer_body.dart` 的 `openStoryReader` 直接 push 阅读器页面。
- 资料引用：同文件 `showCitedRecord` 弹出 `_RecordSheet`（约 579 行），用 `SelectableText(r.content)` 显示原文，没有 markdown 渲染，也没有用资料页的 `ProfileText`，所以 `## 基础信息` 原样露出（截图可见，干员档案尤其明显）。
- Wiki 引用：`showCitedWiki` 也是弹窗（`WikiCitationSheet`）。

### 2. 故事与资料的打开方式不统一

- 资料统一为跳资料页：`lib/features/library/entry_page.dart` 的 `EntryPage(entryId:)` 已经用 `ProfileText`，应该能正确渲染。
- 需要先确认：问答里的记录 id（`record:ef/…`）与 `entries.id` 是否一一对应，没有查证。
- `openEntry` 需要 `LibraryEntry`，直接用 `EntryPage(entryId:)` 即可。
- Wiki 引用是否也跳 Wiki 标签，需要开发者决定。

### 3. 长文阅读器没有进度

- `lib/features/ai/story_reader_page.dart` 已有 `totalLines: _lines.length`，标题区（`title`）没有显示读到的行号。
- 方案：标题旁加环形进度，显示“行号 / 总行数”；需要取当前可见行，阅读页是惰性列表，行号已有。

### 4. PRTS 黑夜模式与阅读器模式

- `lib/features/wiki/wiki_reader_scripts.dart`（约 800 行注入 JS）、`wiki_reader_css.dart`、`wiki_reader_mode.dart`、`wiki_toolbar.dart`（阅读器按钮 `Icons.chrome_reader_mode`）。
- 站点已有自己的新版黑夜模式，本 App 仍是硬改 DOM；资料页已存在，阅读器模式的暴力适配没有必要。
- 删除前先查 `docs/WIKI_EVIDENCE.md`、`docs/WIKI_SITE_ADAPTATION.md` 有没有依赖。

### 5. Wiki “转交给 AI”

- `lib/features/wiki/wiki_browser_page.dart` 约 784 行 `showModalBottomSheet<WikiAiTarget>`。
- 问答 Agent 已有 `wiki_search` / `wiki_read`，手动转交基本没有必要。删除，或改为把当前页作为问答上下文，待定。

### 6. 悬浮 UI 自动隐藏（需要方案）

- `lib/shared/widgets/floating_bar.dart`（`FloatingBar`、`FloatingScaffold`）常驻。
- PRTS 页的 dock 为了不挡住站点的条，下移了：`wiki_browser_page.dart` 的 `_syncDockInsets` / `_applyDockInsets` 通过注入样式给网页留出上下边距。
- 方案：
  - A. 单击唤起，翻页或静止约 3 秒收回。误唤起风险较高，与选字冲突。
  - B. 上下滑收起，停止后展开。误触少，发现性差。
  - C. 只在顶部或底部边缘热区唤起。误触最少，手势较细。
- 技术要点：阅读页用 `NotificationListener<ScrollNotification>`；WebView 上要通过 JS 通道把滚动事件传回 Flutter；收起时网页内边距要同步变化，需要防止抖动。

## 三、建议的处理顺序（待开发者确认）

1. 修 `_RecordSheet` 的原始 markdown，或直接改为跳资料页。
2. 统一打开方式（资料进资料页，故事进阅读器）。
3. 阅读器进度标注。
4. 删除阅读器模式与“转交给 AI”（先确认没有依赖）。
5. 悬浮 UI 手势（先选方案）。
6. 问答的跨库推理（最大的一项，先离线复现，真实模型测试先问开发者）。

## 四、未验证的事项

- 资料记录 id 与 `EntryPage(entryId:)` 是否一一对应。
- 凯尔希复活的原文依据，明日方舟库里只找到 1 条相关台词，尚未在实体条目里核实。
- 真机界面只看了截图，没有运行。

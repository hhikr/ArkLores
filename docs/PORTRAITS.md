# 剧情立绘（0.20）

明日方舟剧情里每句台词显示的立绘：建库时记下来（知识库里的几张可选表），图片放在单独的“立绘包”里，
阅读器的说话人和问答答案里的名字可以点开立绘卡片。终末地没有立绘数据。

## 1. 剧本里的立绘

剧本有两套写法：

```text
[Character(name="char_002_amiya_1#5")]                          旧写法：一个或两个人（name / name2），focus=1/2 选谁在说
[Character(name="char_002_amiya_1#5", name2="char_010_chen_1#2", focus=2)]
[Character]                                                     清空
[charslot(slot="l", name="avg_4137_udflow_1#4$1", focus="l")]   新写法：左中右三个位置，focus 选位置
[charslot]                                                      清空全部
[name="某人"]台词                                                 说话的一行
```

- 立绘名 = `<立绘>#<表情>$<服装>`。一个立绘的所有表情、服装叫它的**差分**；界面上的“一个立绘”是一个 `<立绘>`，差分归在它下面。
- **规范写法**（库里、立绘包里、代码里一律用它，与 Arkwaifu 相同）：去掉所有空白、转小写，再补全——没有 `#` 补 `#1`，没有 `$` 补 `$1`。
  `char_002_amiya_1#5` → `char_002_amiya_1#5$1`。代码：`lib/core/gamedata/build/portrait_names.dart`（`SpriteName`）。
- 通用立绘很多（一个路人立绘被几十个名字用过），“用这个立绘的说话人”照实列出、按句数排，不判断是不是同一个人（身份不由代码判断）。

### 1.1 一句台词显示哪张（状态机）

每个文件开头清空：位置 → 立绘名，以及焦点（不确定 / 无 / 全部 / 某个位置）。

| 命令 | 状态变化 |
| --- | --- |
| `[Character]`，或有括号但没有 `name`/`name2` | 清空位置，焦点不确定 |
| `[Character(name=A, name2=B, focus=F)]` | 位置 1、2 放 A、B；`F` 是 1/2 → 那个位置；其他值 → 无；没有 `F`：只有一个位置有人 → 那个位置，否则不确定 |
| `[charslot]` | 清空位置，焦点不确定 |
| `[charslot(slot=S, name=N)]` | 位置 S（left/right/middle 记作 l/r/m，没写是 m）放 N；N 为空串 → 清掉这个位置 |
| `[charslot(slot=S)]`（没有 name、也没有 focus） | 清掉位置 S |
| `[charslot(slot=S, focus=F)]`（没有 name） | 只改焦点 |
| `charslot` 的 `focus` | 位置名 → 那个位置；`n`/`none` → 无；`a`/`all` → 全部；没写且这次放了人：放完只有一个位置有人 → 那个位置 |

有说话人的台词显示：焦点是某个位置且那里有人 → 那个人；焦点不确定且恰好一个位置有人 → 那个人；其他 → 没有立绘。
旁白、字幕、文档、选项、标题一律没有立绘。约 88% 有说话人的台词能确定立绘。

## 2. 知识库里的表（可选，只有明日方舟库有）

旧 App 不读这些表，加表不用提高渠道文件的 `min_app_build`。代码：`lib/core/gamedata/build/portrait_index.dart`。

| 表 | 内容 |
| --- | --- |
| `story_line_portraits` | 每句显示的立绘（`story_id`、`line_index`、`sprite`），只记有立绘的台词 |
| `portrait_sprites` | 每张差分：所属立绘、表情号、服装号、句数 |
| `portrait_groups` | 每个立绘：对应的干员条目（`operator_entry_id`）、句数、说话人数、差分张数、最常用的差分 |
| `speaker_portraits` | 说话人 × 立绘：句数、篇数、这个人在这个立绘里最常用的差分 |
| `speaker_names` | 每个说话人：句数、立绘数、最常用的立绘与差分、`owns_group`、`highlight`、`mentions` |

- `operator_entry_id`：立绘 id 符合 `^(?:char|avg)_(\d+)_([a-z0-9]+)` 时，候选是 `operator:char_<数字>_<名>`，**`entries` 里确有这一行**才填。按 id 规则对应，不按名字猜；`avg_npc_…` 永远为空。
- 派生表完全由 `story_line_portraits`、`story_lines.speaker`、`entries` 算出，构建两次结果一致；manifest 记 `portrait_index_version = 1`、行数与立绘数。
- **问答可以标出的名字**（`highlight = 1`）：至少 2 个字（按 Unicode 码点）、含字母（排除“？？？”）、有立绘的台词 ≥ 3 句、`owns_group = 1`（至少一个立绘以它为主要说话人，占该立绘 ≥ 50% 的句数），
  且正文里出现的次数 ≤ 3 × 自己说话的句数（`mentions`；否则多半是族群、称谓、常用词或更长的词的一部分）。2026-10 的库上有 1,049 个。

四条构建路径都写这些表：全量构建与 App 内完整构建在导入剧情时写 `story_line_portraits`，最后调 `rebuildPortraitIndex`；
增量更新删、写变化的故事后重算；给已有库补立绘用 `tools/build_portrait_index.dart --db=<库> --source=<源目录>`
（逐篇重新解析，只有每行 `kind|speaker|content` 与库里相同才写，不同的跳过并列出；不碰向量）。
`reimportChangedStories` 的签名**不含**立绘，否则所有故事都会被当成变化、丢掉向量。

## 3. 立绘包

`arklores_portraits_zh.db`，一个 SQLite 文件，不压缩发布（WebP 已经压过）；和知识库放在同一个 `gamedata-channel` Release，渠道文件里是 `arknights_portraits` 一项（url、sha256、size、生成它的知识库提交、`pack_version`、`min_app_build`）。

### 3.1 来源

图片来自 [Arkwaifu](https://arkwaifu.cc)（源码 MIT，图片 CC BY-NC 4.0，版权归鹰角网络）。它公开发布一个元数据 SQLite（`arkwaifu.sqlite3`），
`narrative_image_assets` 表里 `category = 'character'` 的 `asset_id` 就是规范写法（但**保留剧本原来的大小写**，要去空白、转小写后再比），`object_key` 指向合成好的整张差分（PNG）。
下载地址是 CDN 前缀 + **再做一次 URL 编码**的 `object_key`（key 里的 `%23` 要变成 `%2523`）。

- 原图约 8 GB，只下载一次存本机缓存（`build/portraits_src/`），并发不超过 4、断点续传；以后只下变了或新增的。这是别人的服务，不要反复整批下载。
- 覆盖：库 `17759cc` 的 10,228 张差分有 10,210 张；缺的 18 张在 `avg_npc_598_1`、`avg_npc_604_1`、`char_empty_b`（共 265 句），App 退回那个立绘最常用的一张。

### 3.2 格式

| 表 | 内容 |
| --- | --- |
| `portrait_bases` | 每套“立绘 + 服装”一张底图（`base_id = <立绘>$<服装>`、宽高、底图是哪张差分、WebP） |
| `portrait_images` | 每张差分怎么画：`base_id` 为空 = 整张存在 `webp`；否则底图 + 补丁（`x`、`y`、补丁 WebP），补丁为空 = 与底图相同；`blank = 1` = 整张透明，什么都不画 |
| `pack_manifest` | `pack_version=1`、`source=arkwaifu`、`source_artwork_version`、`kb_commit`、`sprite_count`、`missing_count`、`max_height`、`built_at` |
| `pack_groups` | 每套图的输入签名，只给打包脚本做增量用，App 不读 |

### 3.3 打包（`tools/portraits/`，Python + Pillow，本机跑）

```powershell
# 按知识库的清单把缺的原图下到本机缓存（--arkwaifu-db 给一份已下载的 arkwaifu.sqlite3）
python tools/portraits/fetch_arkwaifu.py --kb=<知识库> --cache=build/portraits_src --arkwaifu-db=<arkwaifu.sqlite3>
# 打包（默认从 --out 处的旧包拷贝没变的套）
python tools/portraits/build_portrait_pack.py --kb=<知识库> --cache=build/portraits_src --out=build/portraits/arklores_portraits_zh.db
# 抽样对比原图与包里的图，出一张对照图
python tools/portraits/check_portrait_pack.py --pack=build/portraits/arklores_portraits_zh.db --cache=build/portraits_src --sheet=<输出.png>
```

1. 清单以知识库的 `portrait_sprites` 为准，按立绘 + 服装分组。
2. 一组用同一个裁切框（所有图不透明区域外框的并集），等比缩到高 800（不放大）。
3. 底图 = 组里句数最多的差分（WebP 质量 80）。
4. 其余差分与底图逐像素比（RGBA 最大差 ≤ 6 算相同），不同区域的外框四边各扩 4 像素：没有不同 → 同底图；外框 ≤ 底图面积的一半 → 存补丁（质量 85）；更大 → 存整张。
5. 整张透明 → `blank = 1`（看图片，不写名字表）。Arkwaifu 没有的不写，列进缺失报告。
6. **增量**：每套图的签名（成员差分、各自的 `object_key` 与缓存文件大小、底图、高度）与上一个包相同的，行原样拷过来；新包写完才替换旧包。
   全量约 53 分钟（4 进程），知识库只多几十套时一两分钟；单元测试保证增量结果与从头打包逐字节相同。

2026-10 实测：10,210 张差分、1,950 套，包约 186 MB；可见像素平均误差 3–5 / 255，没有接缝。

## 4. App 的入口

| 部分 | 代码 |
| --- | --- |
| 查询（表不存在时返回空，界面入口不出现） | `lib/core/library/portrait_queries.dart`、`portrait_provider.dart` |
| 读立绘包（只读、按文件 stamp 重开） | `lib/core/gamedata/portrait_pack.dart` |
| 画一张差分（底图画满，补丁用 `BlendMode.src` 替换像素；合成结果缓存最近 24 张） | `lib/shared/widgets/portrait_image.dart` |
| 下载、校验、替换、删除（复用知识库的断点续传；校验 SHA、`pack_version` 与非空；替换中断后自动恢复） | `lib/core/gamedata/portrait_pack_installer.dart`、`portrait_pack_provider.dart` |
| 知识库页的“剧情立绘”卡片（两个游戏都有；终末地只有一句说明） | `lib/features/settings/portrait_pack_card.dart` |
| 立绘卡片、预览与列表页 | `lib/features/library/portrait_sheet.dart`、`portrait_speakers_page.dart`、`speaker_portraits_page.dart`、`portrait_preview.dart`、`portrait_stories_page.dart` |
| 阅读器的说话人 | `lib/features/library/portrait_speaker_name.dart`、`story_reader_page.dart` |
| 问答答案里的名字 | `lib/features/ai/speaker_highlight.dart`、`widgets/story_answer_body.dart` |

- 取图顺序：要的那张 → 不在包里时用这个立绘最常用的一张 → 都没有时斜线纹占位加一句话；`blank` 的差分写“这一句的立绘是空的。”
- 首次打开时，只有**阅读器里点某一句的说话人**显示那一句的确切差分（卡片上写表情、服装号）；问答和两个列表页一律显示最常用的一张。
- 阅读器：明日方舟的故事、知识库有立绘表时，名字可以点开旁边的小卡片，点“更多”打开大卡片。标题字体 14 号、无下划线；深色用 `accentText`，浅色墨字下面垫强调色色块。热区扩到 48×48、行高不变。附属对话用原故事的 id 和行号查。
- 问答：作答结束后按段落扫答案正文，每个名字每段只标第一次出现；最左最长匹配，跳过行内代码、已有链接、标题行、尖括号；英文名只按整词匹配。
  样式是正文颜色加 2 px `accentPrimary` 下划线（开发者 2026-10-26）。点名字先显示旁边的小卡片；预览不取焦点，问答输入框的键盘保持展开。只引了终末地剧情的答案不标。
  设置“回答里不标干员名”（默认关）：打开后，最常用立绘对应干员条目的名字不标（2026-10 的库上 1,049 个里有 316 个）。
- 立绘预览：名字下方显示高约 160 px 的图、名字、句数与“更多”；下方放不下时放上方，左右留 16 px。点外面、滚动、返回时关闭，同时只有一张。
- 立绘卡片：名字、立绘图、句数与差分张数、表情与服装号，以及“还有谁使用了这个立绘？”、“这个人还有哪些立绘？”、有干员条目时的“干员资料”。大图下方按服装、表情排列同组全部差分，横向懒加载，选中项用 `trace` 线框；点缩略图切换大图和编号。从台词打开时先选中该句差分。底部署名“立绘：Arkwaifu（CC BY-NC 4.0）/ 鹰角网络”。
- “某人的立绘”列表（`SpeakerPortraitsPage`）点一个立绘，打开那个立绘的大卡片（`showPortraitGroupSheet`）：卡片不写名字，因为说话人的列表里有别人的立绘（开发者 2026-10-26）；卡片上“谁在用这个立绘？”和“某人用这个立绘的剧情”。“立绘的说话人”列表点一个名字仍直接进剧情列表。
- 剧情列表：说话人 × 立绘 → 每篇剧情的标题、所属故事集、句数 → 阅读器，定位并高亮该组合在这篇里的首次台词。查询连接 `story_line_portraits`、`story_lines`、`portrait_sprites`，说话人去两端空格后匹配，按篇取 `MIN(line_index)` 与句数；目录标题和排序复用 `StoryCatalogEntry.label` 与 `storyReleaseKey`。沿用已有的立绘与台词索引。
  从资料页打开的页面用毛玻璃换页，从问答打开的用普通推入。

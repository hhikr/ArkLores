# 剧情立绘与剧情美术（0.20）

明日方舟剧情里每句台词显示的立绘，以及每篇剧情在哪里换场景、出 CG、出特写：建库时记下来（知识库里的几张可选表），
图片放在单独的“剧情美术包”里。阅读器的说话人和问答答案里的名字可以点开立绘卡片；阅读器在剧情里排出场景与 CG，
特写按剧本的位置合成到画面上；资料页的故事集列出它的剧情美术；所有图都能全屏看。终末地没有立绘和美术数据。

## 1. 剧本里的立绘

剧本有两套写法：

```text
[Character(name="char_002_amiya_1#5")]                          旧写法：一个或两个人（name / name2），focus=1/2 选谁在说
[Character(name="char_002_amiya_1#5", name2="char_010_chen_1#2", focus=2)]
[Character]                                                     清空
[charslot(slot="l", name="avg_4137_udflow_1#4$1", focus="l")]   新写法：左中右三个位置，focus 选位置
[charslot]                                                      清空全部
[CharacterCutin(widgetID="1", name="char_010_chen_1#2", …)]     画面上横条里的人（通讯、远处的声音）
[CharacterCutin(widgetID="1", fadetime=0.5)]                    撤下横条
[name="某人"]台词                                                 说话的一行
```

- 立绘名 = `<立绘>#<表情>$<服装>`。一个立绘的所有表情、服装叫它的**差分**；界面上的“一个立绘”是一个 `<立绘>`，差分归在它下面。
- **规范写法**（库里、美术包里、代码里一律用它，与 Arkwaifu 相同）：去掉所有空白、转小写，再补全——没有 `#` 补 `#1`，没有 `$` 补 `$1`。
  `char_002_amiya_1#5` → `char_002_amiya_1#5$1`。代码：`lib/core/gamedata/build/portrait_names.dart`（`SpriteName`）。
- 通用立绘很多（一个路人立绘被几十个名字用过），“用这个立绘的说话人”照实列出、按句数排，不判断是不是同一个人（身份不由代码判断）。

### 1.1 一句台词显示哪张（状态机）

每个文件开头清空位置 → 立绘名、焦点（不确定 / 无 / 全部 / 某个位置），并重置 CG 遮挡状态和横条。
两种写法改的是**同一个舞台**（左 l、中 m、右 r 三个位置）：同一篇里常常先用 `Character` 放一个人，再用 `charslot(slot="m")` 换人。
索引版本 2 把两者当成两套位置，换上来的人和原来的人同时“在场”，焦点停在原来的人身上（一篇里连续五个人的台词都记成同一个立绘），版本 3 改正。

| 命令 | 状态变化 |
| --- | --- |
| `[Character]`，或有括号但没有 `name`/`name2` | 清空位置，焦点不确定 |
| `[Character(name=A, name2=B, focus=F)]` | 清空位置；只写了一个名字 → 放在中；写了两个 → A 左、B 右（名字不是立绘也占位置）；`F` 是 1/2 → A/B 的位置；其他值 → 无；没有 `F`：只有一个位置有人 → 那个位置，否则不确定 |
| `[charslot]` | 清空位置，焦点不确定 |
| `[charslot(slot=S, name=N)]` | 位置 S（left/right/middle 记作 l/r/m，没写是 m）放 N；N 为空串 → 清掉这个位置 |
| `[charslot(slot=S)]`（没有 name、也没有 focus） | 清掉位置 S |
| `[charslot(slot=S, focus=F)]`（没有 name） | 只改焦点 |
| `charslot` 的 `focus` | 位置名 → 那个位置；`n`/`none` → 无；`a`/`all` → 全部；没写且这次放了人：放完只有一个位置有人 → 那个位置 |
| `[Image(image=I)]` / `[Image]`、`[Image(fadetime=…)]` | `image` 非空时 CG 遮挡舞台；没有 `image` 或为空串时撤下 CG。遮挡期间仍更新位置和焦点，但台词不记立绘；命令和参数名不区分大小写 |
| `[CharacterCutin(name=N)]` | 横条里是 N，接下来的台词记 N（舞台上的人还在，只是不说话） |
| `[CharacterCutin]` 没有 `name`；或任何 `Character`/`charslot` 命令 | 横条不再说话，回到舞台的焦点（舞台命令之后横条可能还挂着，但说话的是舞台上的人） |

有说话人的台词显示：CG 遮挡 → 没有立绘；横条在说话 → 横条里的人；焦点是某个位置且那里有人 → 那个人；焦点不确定且恰好一个位置有人 → 那个人；其他 → 没有立绘。
旁白、字幕、文档、选项、标题一律没有立绘。`ImageTween`、`ImageRotate` 只调整图片，不切换遮挡状态。`Background` 与分层 `cgitem` 不作为全屏 CG 遮挡命令。
`Blocker`（纯色幕）也不遮挡立绘：剧本在 `Blocker(a=1)` 黑幕期间照常换人、换焦点几十行（如 `level_main_03-02_end`），幕在立绘下层。
索引版本 3 的本地库中，374,396 句有说话人的台词有 328,071 句能确定立绘（87.63%）。

剩下的“别人的台词记在某人立绘上”是剧本本身的演出：说话人不在画面上（画外音、黑幕里的声音），舞台焦点仍停在上一个人身上，例如阿米娅立绘下的 Ace、W、闪灵各 1 句。
这类不按说话人改（开发者 2026-10-26：确实有模仿别人说话的人）。通用路人立绘被几十个名字共用，也照实列出。

### 1.2 场景、CG 与特写（美术事件）

与立绘同一遍解析（`story_script.dart`），每篇记下美术事件（`story_art_events`，§2）：

| 命令 | 事件 |
| --- | --- |
| `Background(image=X)`；`largebg`/`gridbg`/`verticalbg`（`imagegroup`，拼接图，记 `layout` = row / grid2 / column） | `background` X；没有 image 是撤下背景（`image` 为空）。和上一个背景相同的不记 |
| `Image(image=X)` / 没有 image 而 CG 开着 | `cg` X / `cg_off`（与立绘的 CG 遮挡同一条规则、同一处代码） |
| `cgitem(image=X, …)` / `hidecgitem` | `item` / `item_off`：特写图层，带位置 `x`、`y`、缩放 `scale`、透明度 `alpha`、层次 `layer` |

- **图层按文字行结算**（美术索引版本 2）：两句台词之间的命令全部执行完，只记下一句出现时的最终状态；参数优先级 `pto → pfrom → 上一次的值`；
  只有可见状态变了才写 `item`/`item_off`，`alpha ≤ 0.01` 算撤下。换背景、换 CG 不清空图层，只有 `item_off`（或剧本结束）撤下。不处理旋转（全库 6 条命令）。
- 每个文件开头状态清空；文件结束时 CG 还开着不补 `cg_off`。纯色、场景编号、“回到同一张不算切换”都不在库里算，App 按包里的 `solid` 算（库里只记剧本写了什么）。
- 2026-10 本机库（索引版本 2）：18,947 个事件，`background` 15,207、`cg` 1,991、`cg_off` 1,527、`item` 117、`item_off` 105。

## 2. 知识库里的表（可选，只有明日方舟库有）

旧 App 不读这些表，加表不用提高渠道文件的 `min_app_build`。代码：`lib/core/gamedata/build/portrait_index.dart`、`story_art_index.dart`。

| 表 | 内容 |
| --- | --- |
| `story_line_portraits` | 每句显示的立绘（`story_id`、`line_index`、`sprite`），只记有立绘的台词 |
| `portrait_sprites` | 每张差分：所属立绘、表情号、服装号、句数 |
| `portrait_groups` | 每个立绘：对应的干员条目（`operator_entry_id`）、句数、说话人数、差分张数、最常用的差分 |
| `speaker_portraits` | 说话人 × 立绘：句数、篇数、这个人在这个立绘里最常用的差分 |
| `speaker_names` | 每个说话人：句数、立绘数、最常用的立绘与差分、`owns_group`、`highlight`、`mentions` |
| `story_art_events` | 美术事件（§1.2）：`story_id`、`seq`、`at_line`（事件之后第一句的行号）、`kind`、`image`（规范写法：去空白、转小写；拼接图按剧本顺序用 `/` 连起来）、`layout`，特写另有 `x`、`y`、`scale`、`alpha`、`layer` |

- `operator_entry_id`：立绘 id 符合 `^(?:char|avg)_(\d+)_([a-z0-9]+)` 时，候选是 `operator:char_<数字>_<名>`，**`entries` 里确有这一行**才填。按 id 规则对应，不按名字猜；`avg_npc_…` 永远为空。
- 派生表完全由 `story_line_portraits`、`story_lines.speaker`、`entries` 算出，构建两次结果一致；manifest 记 `portrait_index_version`（现在是 7）、行数与立绘数，`story_art_index_version`（现在是 2）与事件数。
  立绘索引版本 2 增加 CG 遮挡规则，版本 3 合并两种舞台写法并加入横条，版本 4–7 只改 `highlight` 的规则；旧索引须从原始剧本补算。
- **问答可以标出的名字**（`highlight = 1`，版本 7，开发者 2026-10-27）：凡是配着立绘说过话的说话标签都标——称谓、群体、共用立绘、正文里常用的词、以问号结尾的都算；
  只排除三种：一个字（按 Unicode 码点）、不含字母（“？？？”）、几个人合说（含 `&`、`＆`、`/`）。`mentions`（正文里出现的次数）照旧计算，不再参与判断。
  2026-10 本机库：5,122 个说话人里标出 5,028 个。之前几版的门槛（句数、主要说话人、提及次数）漏掉了大量真名字，开发者决定放宽，误标交给用户的屏蔽词（§5.2）。

四条构建路径都写这些表（美术事件与立绘同一遍解析、同一个补算工具）：全量构建与 App 内完整构建在导入剧情时写 `story_line_portraits`，最后调 `rebuildPortraitIndex`；
增量更新删、写变化的故事后重算；给已有库补立绘用 `tools/build_portrait_index.dart --db=<库> --source=<源目录>`
（逐篇重新解析，只有每行 `kind|speaker|content` 与库里相同才写，不同的跳过并列出；不碰向量）。
`reimportChangedStories` 的签名**不含**立绘，否则所有故事都会被当成变化、丢掉向量。

## 3. 剧情美术包

`arklores_story_art_zh.db`（`pack_version = 2`），一个 SQLite 文件，不压缩发布（WebP 已经压过）；和知识库放在同一个 `gamedata-channel` Release，渠道文件里是 `arknights_story_art` 一项
（url、sha256、size、生成它的知识库提交 `kb_commit`、`pack_version`、`min_app_build = 43`），env 是 `STORY_ART_*`（`GAMEDATA_BUILD_PIPELINE.md` §7）。
0.20 开发中曾叫“立绘包”（`arklores_portraits_zh.db`，`pack_version = 1`，从没发布）；App 发现旧文件就删掉。
一个包装下全部立绘与美术：以后任何一块更新都要重下整包（断点续传），这是开发者 2026-10-27 定的。

### 3.1 来源

图片来自 [Arkwaifu](https://arkwaifu.cc)（源码 MIT，图片 CC BY-NC 4.0，版权归鹰角网络）。它公开发布一个元数据 SQLite（`arkwaifu.sqlite3`），
`narrative_image_assets` 表里 `category = 'character'` 的 `asset_id` 就是规范写法（但**保留剧本原来的大小写**，要去空白、转小写后再比），`object_key` 指向合成好的整张差分（PNG）。
下载地址是 CDN 前缀 + **再做一次 URL 编码**的 `object_key`（key 里的 `%23` 要变成 `%2523`）。

- 原图约 8 GB，只下载一次存本机缓存（`build/portraits_src/`），并发不超过 4、断点续传；以后只下变了或新增的。这是别人的服务，不要反复整批下载。
- 立绘覆盖：库 `17759cc` 的差分有 10,207 张在包里；缺的 18 张在 `avg_npc_598_1`、`avg_npc_604_1`、`char_empty_b`（共 265 句），App 退回那个立绘最常用的一张。
- 美术：同一个元数据里 `category` 为 background / illustration / item 的图；CG 的标题与描述来自 Arkwaifu 的中文相册。同名可以在几个类别里各是一张不同的图，App 按事件种类依次找（背景：background → illustration → item；CG：illustration → background → item；特写：item → illustration → background）。
  知识库事件里的 2,629 张图缺 2 张，缺的场景只显示标签行。

### 3.2 格式

| 表 | 内容 |
| --- | --- |
| `portrait_bases` | 每套“立绘 + 服装”一张底图（`base_id = <立绘>$<服装>`、宽高、底图是哪张差分、WebP） |
| `portrait_images` | 每张差分怎么画：`base_id` 为空 = 整张存在 `webp`；否则底图 + 补丁（`x`、`y`、补丁 WebP），补丁为空 = 与底图相同；`blank = 1` = 整张透明，什么都不画 |
| `art_images` | 主键（`category`, `image_id`），`image_id` 与 `story_art_events.image` 相同（拼接图是带 `/` 的整串）；`width`、`height`、`solid`（缩到 64 px 宽后所有像素与平均色相差 ≤ 6）、`webp` |
| `art_titles` | `image_id`、`title`、`description`、`group_key`（同一相册组的几张共用标题） |
| `pack_manifest` | `pack_version=2`、`source=arkwaifu`、`source_artwork_version`、`kb_commit`、`sprite_count`、`missing_count`、`max_height`、`built_at`、`art_count`、`background_count`、`illustration_count`、`item_count`、`solid_count`、`title_count`、`art_missing_count` |
| `pack_groups` | 每套图的输入签名，只给打包脚本做增量用，App 不读 |

美术的规格：背景宽 ≤ 1280；CG 长边 ≤ 1600（竖长图宽 ≤ 1280、高不限）；特写保留原图尺寸与透明（合成时要按原尺寸放到舞台上）；WebP 质量 80。
拼接图：Arkwaifu 有同名的合成图就用它，没有就按 `layout` 拼（row 横排、column 竖排、grid2 两列逐行）。

### 3.3 打包（`tools/portraits/`，Python + Pillow，本机跑）

```powershell
# 按知识库的清单把缺的原图下到本机缓存（--arkwaifu-db 给一份已下载的 arkwaifu.sqlite3）
python tools/portraits/fetch_arkwaifu.py --kb=<知识库> --cache=build/portraits_src --arkwaifu-db=<arkwaifu.sqlite3>
# 打包立绘与美术（美术部分在 story_art.py，美术原图缓存 --art-cache，默认 build/story_art_src/；默认从 --out 处的旧包拷贝没变的套）
python tools/portraits/build_portrait_pack.py --kb=<知识库> --cache=build/portraits_src --out=build/story_art/arklores_story_art_zh.db
# 抽样对比原图与包里的图，出一张对照图
python tools/portraits/check_portrait_pack.py --pack=build/story_art/arklores_story_art_zh.db --cache=build/portraits_src --sheet=<输出.png>
```

1. 清单以知识库的 `portrait_sprites` 为准，按立绘 + 服装分组。
2. 一组用同一个裁切框（所有图不透明区域外框的并集），等比缩到高 800（不放大）。
3. 底图 = 组里句数最多的差分（WebP 质量 80）。
4. 其余差分与底图逐像素比（RGBA 最大差 ≤ 6 算相同），不同区域的外框四边各扩 4 像素：没有不同 → 同底图；外框 ≤ 底图面积的一半 → 存补丁（质量 85）；更大 → 存整张。
5. 整张透明 → `blank = 1`（看图片，不写名字表）。Arkwaifu 没有的不写，列进缺失报告。
6. **增量**：每套图的签名（成员差分、各自的 `object_key` 与缓存文件大小、底图、高度）与上一个包相同的，行原样拷过来；新包写完才替换旧包。
   全量约 53 分钟（4 进程），知识库只多几十套时一两分钟；单元测试保证增量结果与从头打包逐字节相同。

7. 美术：清单 = 知识库 `story_art_events` 里出现的全部 `image`，按 §3.2 的规格缩放、判断 `solid`；增量同样按签名拷贝没变的行。

2026-10 实测（本机包 2026-10-27，知识库 `17759cc`）：立绘 10,207 张差分、1,949 套；美术 2,627 张（背景 1,028、CG 1,488、特写 111，纯色 3，CG 标题 1,240）；
整包 396,136,448 字节。立绘可见像素平均误差 3–5 / 255，没有接缝。

## 4. App 的入口

| 部分 | 代码 |
| --- | --- |
| 查询（表不存在时返回空，界面入口不出现） | `lib/core/library/portrait_queries.dart`、`portrait_provider.dart`、`story_art.dart`、`collection_story_art.dart` |
| 读剧情美术包（只读、按文件 stamp 重开；一次查完一批图的尺寸与 `solid`，不解码图片） | `lib/core/gamedata/story_art_pack.dart` |
| 画一张差分（底图画满，补丁用 `BlendMode.src` 替换像素；合成结果缓存最近 24 张） | `lib/shared/widgets/portrait_image.dart` |
| 画一张美术图（按显示宽度解码，不超过存的宽度）、合成图层 | `lib/shared/widgets/story_art_image.dart`、`story_art_composite.dart` |
| 下载、校验、替换、删除（复用知识库的断点续传；校验 SHA、`pack_version` 与非空；替换中断后自动恢复；删掉开发期的旧立绘包文件） | `lib/core/gamedata/story_art_pack_installer.dart`、`story_art_pack_provider.dart` |
| 知识库页的“剧情美术”卡片（两个游戏都有；终末地只有一句说明；新用户导览里也有一步） | `lib/features/settings/story_art_pack_card.dart` |
| 立绘卡片、预览与列表页 | `lib/features/library/portrait_sheet.dart`、`portrait_speakers_page.dart`、`speaker_portraits_page.dart`、`portrait_preview.dart`、`portrait_stories_page.dart` |
| 阅读器的说话人 | `lib/features/library/portrait_speaker_name.dart`、`story_reader_page.dart` |
| 阅读器里的场景、CG 与当前画面 | `lib/features/ai/reader_story_art.dart`、`story_reader_page.dart` |
| 全屏查看器（剧情画面与立绘） | `lib/features/library/story_art_viewer.dart` |
| 资料页的剧情美术 | `lib/features/library/collection_page.dart`、`collection_art_page.dart` |
| 问答答案里的名字、逐段放出、屏蔽词 | `lib/features/ai/speaker_highlight.dart`、`widgets/story_answer_body.dart`、`widgets/answer_reveal.dart`、`widgets/block_name_card.dart`、`lib/features/settings/blocked_names_page.dart` |

- 取图顺序：要的那张 → 不在包里时用这个立绘最常用的一张 → 都没有时斜线纹占位加一句话；`blank` 的差分写“这一句的立绘是空的。”
- 首次打开时，只有**阅读器里点某一句的说话人**显示那一句的确切差分（卡片上写表情、服装号）；问答和两个列表页一律显示最常用的一张。
- 阅读器：明日方舟的故事、知识库有立绘表时，名字可以点开旁边的小卡片，点“更多”打开大卡片。标题字体 14 号、无下划线；深色用 `accentText`，浅色墨字下面垫强调色色块。热区扩到 48×48、行高不变。附属对话用原故事的 id 和行号查。
- 问答：见 §5.2。
- 卡片上的入口（还有谁使用、这个人还有哪些立绘、剧情、干员资料）在卡片上面推入新页，卡片留着：返回回到卡片（开发者 2026-10-26）。
- 立绘预览：名字下方显示高约 160 px 的图、名字、句数与“更多”；下方放不下时放上方，左右留 16 px。点外面、滚动、返回时关闭，同时只有一张。
- 立绘卡片：名字、立绘图、句数与差分张数、表情与服装号，以及“还有谁使用了这个立绘？”、“这个人还有哪些立绘？”、有干员条目时的“干员资料”。大图下方按服装、表情排列同组全部差分，横向懒加载，选中项用 `trace` 线框；点缩略图切换大图和编号。从台词打开时先选中该句差分。底部署名“图片：Arkwaifu（CC BY-NC 4.0）/ 鹰角网络”（全部美术同一句）。
  大卡片的大图和小卡片的图都能点开全屏（只画人物，放在两条栏之间、没有卡片底色），全屏里左右翻页时大卡片的选中跟着变；缩略图列表仍只切换大卡片。
- “某人的立绘”列表（`SpeakerPortraitsPage`）点一个立绘，打开那个立绘的大卡片（`showPortraitGroupSheet`）：卡片不写名字，因为说话人的列表里有别人的立绘（开发者 2026-10-26）；卡片上“谁在用这个立绘？”和“某人用这个立绘的剧情”。“立绘的说话人”列表点一个名字仍直接进剧情列表。
- “立绘的说话人”列表把**路过的说话人**收进底部一行（“另有 N 人出现很少，主要立绘在别处”，点开展开，编号接着排）：在这个立绘上不超过 2 句，或只在一篇里、少于 6 句（`passingCount`），且自己最常用的立绘（`speaker_names.top_group`）是别的立绘，第一名永远不收（开发者 2026-10-26）。多半是画外音、黑幕里的声音，焦点还停在舞台上的人身上；也包括身份揭晓前的“？？？”与模仿别人的说话人，所以只收起、不删，索引照旧。
  2026-10 的索引版本 3 库上 858 组（1,760 句）。收起的一行下有小字“出现次数过少，可能是画外音”。
  “这个人还有哪些立绘”（`SpeakerPortraitsPage`）同样收起：这个人用得很少的立绘（同一条 `passingCount`，不是他最常用的那张）收进底部一行，第一张永远不收。只看篇数或句数（只有一篇、只有一句）不能用：只出现在一篇里的 4,744 组中有 3,561 组就是说话人自己唯一的立绘。
- 剧情列表：说话人 × 立绘 → 每篇剧情的标题、所属故事集、句数 → 阅读器，定位并高亮该组合在这篇里的首次台词。查询连接 `story_line_portraits`、`story_lines`、`portrait_sprites`，说话人去两端空格后匹配，按篇取 `MIN(line_index)` 与句数；目录标题和排序复用 `StoryCatalogEntry.label` 与 `storyReleaseKey`。沿用已有的立绘与台词索引。
  从资料页打开的页面用毛玻璃换页，从问答打开的用普通推入。

## 5. 剧情美术在 App 里

没有美术包、终末地、这篇没有事件时，阅读器与资料页和以前完全一样（判断黑幕要看图，没有图就不显示半套）。装了包默认显示图；0.21 起可在设置里改成“只标出”或“不显示”（见 §5.1 末尾）。

### 5.1 阅读器与查看器

- **排画面**（`story_art.dart` 的 `arrangeStoryArt`，`reader_story_art.dart`）：事件按行号换算成阅读器的位置；附属对话按来源剧情分组，编号在整个阅读器里连续数。美术项不进行号与“第几行 / 共几行”，所有按行找位置的地方只找台词行。
  - **场景**：标签行“场景 03”（与分段标签同一种）+ 高 56 的横图（cover、右下切角，点开查看器）。纯色背景与撤下不算场景；只隔着纯色回到同一张不算新场景；同一行上连着换的几张合成一组；第一句之前的场景也显示。包里没有的背景只出标签行、不可点。
  - **CG 段**：出现到撤下是一块面板——“CG 02 / 05”、图（竖长图限高 1.25 × 宽、从顶裁，下面斜线纹带“竖长图，点开看全部”）、相册标题与描述、分隔线、段内台词，收口处底边加向右下错开的斜线纹影子。编号按这篇里第一次出现的顺序，同一张再出现用原编号；段内换图插一张新图，同一相册组不再写标题。
    面板拆成列表的多项（顶、每一句、收口），每项画自己那一段的边框与底色，长段懒加载（58 句的段不放进一个 `Column`）。引用高亮的块在画面插入点与 CG 结束处断开。
  - **图层合成**（`story_art_composite.dart`）：舞台 1920×1080；特写的位置、尺寸都是 1280×720 的单位，乘 1.5（`storyArtLayerPixelScale`）放到舞台上，舞台中心加 `(x, -y)`，按 `scale`、`alpha`、`layer` 叠放。有图层的场景显示完整 16:9 舞台；底图被撤下时是黑底（和游戏一样），缺的图层跳过。图层变化出一张同编号的新画面；剧本结束时图层一起撤下。
  - **进度面板的当前画面**：行号那一行下面固定高 48 的一行（64×36 缩略图、“场景 03 / 07”或“CG 02 / 05 标题”、箭头）。当前画面 = 面板上沿以上最后一行所在的 CG 段，否则之前最后一个场景；第一个场景之前写“还没有出现场景”。拖滑块时每次跳行后重新量，换图时留着旧图。
- **全屏查看器**（`openArtViewer(context, pages:, initial:)`）：推入的新页，固定深色，`InteractiveViewer` 1–4 倍；左右滑看这篇的全部画面；顶部关闭与“场景 03 / 07”，底部标题、描述、“回到剧情这里”（阅读器跳到这一画面之后的第一行，放在状态栏下沿）与署名；点图让开或唤回两栏。同一个查看器也用来看立绘（§4）。

显示设置：设置 → 知识库与资料 → 剧情美术，默认“图片”。“只标出”保留场景、CG、特写的位置、编号和相册文字，不加载图片；“不显示”不读取美术事件。设置只影响阅读器及其进度面板，不影响故事集美术页、立绘卡片和主动打开的全屏查看器。未安装美术包时也能保存选项，安装后生效。

### 5.2 问答答案里的人名

- 名字表：`speaker_names.highlight = 1`（§2），再去掉用户的屏蔽词；顶栏的下划线开关关着时为空（`highlightNamesProvider`）。开关和屏蔽词存在本机（`NameLinks`：`ask_name_links`、`ask_blocked_names`）。
  设置“回答里不标干员名”（默认关）：打开后，最常用立绘对应干员条目的名字不标。
- 匹配（`SpeakerMatcher`）：按段落扫答案正文，同一个名字只标第一次出现；最左最长匹配，跳过行内代码、已有链接、标题行、尖括号；英文名只按整词匹配。只引了终末地剧情的答案不标。
  名字表变了（开关、屏蔽、知识库换了）时已经显示的答案立即重标。下划线不存进会话，每次显示时算：规则和屏蔽词改了，旧答案也跟着变。
- 样式是正文颜色加 2 px `accentPrimary` 下划线（开发者 2026-10-26）。点名字先显示旁边的小卡片（这个人最常用的立绘）；预览不取焦点，问答输入框的键盘保持展开。
- 长按带下划线的名字：命中的是带点击的那段文字、而且在名字表里，才在名字旁边弹出“屏蔽这个名字？”小卡片（`showAnchoredCard`，与立绘小卡片同一套定位与展开）；确认后加入屏蔽词，所有答案立即去掉这个名字的下划线。
  设置 → AI 服务 → “下划线屏蔽词”可以手动输入添加（重复的写在输入框下）、点 × 删除。
- **逐段放出**（`answer_reveal.dart`）：流式作答时最后一段（还在写的）不显示，下一段出现或作答结束才定下来；定下来的段先标好名字、按完整 Markdown 排版，再按实际行高一行一行擦开（24 px 渐隐边）。
  约 120 字 / 秒，单段最长 1.2 秒；排队超过两段时加倍，答完后剩下的按三倍放完。出处从第一帧就留出位置，文字放完后淡入。打开已有的对话、恢复旧会话、展开已有细节、减少动态效果时直接显示；停止或出错时把队列放完。

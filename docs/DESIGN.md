# 界面设计（0.17 起）

0.17 把全 App 的界面换成一套工业风的设计：纸面与墨色、一种强调色、可点的东西切一个角、宽体英文配粗体中文、细线分区、短而硬的动效。
本文写这套设计在 ArkLores 里怎么定、在代码里在哪、改界面时要守的规则。界面里的人机交互约定（触控区、对比度、焦点、减少动效）也在这里。

## 1. 外观设定

```text
强调色：浅色 #F8D439（信号黄）／深色 #0BA0D0（方舟蓝）——沿用 0.16 两个主题的强调色（开发者 2026-10-22）
纸色：中性（浅 #F4F4F2，深 #191919）；切角：标准（小 7–8，面板 14–26）；底纹：两角的等高线；密度：标准；动效：完整（系统要求减少动效时全部关闭）
页面类型：问答空状态与导览是"展示"（大字标）；资料首页带一块数字看板；其余都是"阅读"（安静的列表与正文）
```

- 两个主题各有一种强调色，只表示三件事：**当前位置**（选中的标签、当前页码、引用的行）、**可以操作**（主要按钮）、**需要注意**（提示小旗、未作答的状态）。
  强调色只做**填充**（例外：2026-10-26 开发者指定，问答答案里可点的名字用 2 px `accentPrimary` 下划线，字保持正文色）；浅色主题里黄色不当线、不当字（白底上看不见），"标出当前位置的线"用 `trace`（浅色为墨、深色为蓝）。
- **红色只给删除**（`danger`）。出错、警告、失败一律是强调色小旗加墨字；判定结果不用红绿（成立 = 墨色实线框，不成立 = 强调色块）。
- 不用投影、发光、渐变、圆角。

## 2. 代码在哪

| 文件 | 内容 |
| --- | --- |
| `shared/theme/app_theme.dart` | `AppThemeTokens`（全部颜色 token 的含义）、`sairaStyle`、`AppType` 扩展：`ui()` 界面字、`eyebrow()` 装饰小标（原创文字）、`field()` 数字与日期、`heading()` 标题、`text()` 正文 |
| `shared/theme/endfield_theme_tokens.dart` / `ark_theme_tokens.dart` | 浅色 / 深色两套完整取值（深色不是反色） |
| `shared/theme/cut_border.dart` | `CutBorder`：切角形状（可点的东西才用） |
| `shared/theme/motion.dart` | `Motion`：三条曲线（`snap` 出现、`mech` 擦入与所有退出、`ease`）、各档时长、`Motion.of()`（减少动效时为 0） |
| `shared/widgets/ef_widgets.dart` | 部件：`TriStrip` 三色条、`Hatch` 斜线纹、`Eyebrow`、`SectionTitle`、`IndexTag` 编号、`FactsRow` 字段行、`FilterBlock` 筛选块、`AppButton`（normal / go / danger / quiet，按下擦入、busy 铺斜线纹）、`SquareIconButton`、`NoticeBox` 提示、`EmptyState` 空状态、`SegmentProgress` / `BusyMark` / `LoadingView` 分段进度、`SquareSwitch`、`SegmentedChoice`、`AppSlider` 共用滑块、`Figure` 大数字、`InkPanel`、`PressRow` 按压行、`TraceRail` / `FoldBlock` / `FoldTile` 左侧 trace 线与展开、`ActionRow`、`showAppSheet` + `SheetFrame` / `PlainSheet`、`showAppDialog` + `AppDialog`、`confirmAction`、`showToast` |
| `shared/widgets/dock_scaffold.dart` | `DockScaffold`（控件浮在底部的推入页：阅读器）、`DockAction`、`floatingDockRoom` |
| `shared/widgets/page_frame.dart` | `PageScaffold`（推入页的顶栏）、`MainTopBar` + `TopTab` + `TopBarTitle`（四个主标签页的顶栏）、`AppTabBar`（底部标签栏）、`DockPanel`（盖在内容上的控件板）、`pagePadding` |
| `shared/widgets/theme_aware_card.dart` | 面板：可点时右下切角、按下时底边擦入强调色 |
| `shared/widgets/smooth_page_route.dart` | 换页：**只有资料页**（`smoothPageRoute(frosted: true)`：资料页里打开的集合、条目、阅读器、阅读历史）用毛玻璃，其他页面（设置、知识库、问答里打开的出处等）整页从右推入（同样 280 ms、`snap`，前缘一条 2px `trace` 线，下面的页变暗），立即构建（开发者 2026-10-25）。毛玻璃：玻璃（模糊加一层纸色，前缘一条 2px `trace` 线）从右推入（`Motion.coverIn` 280 ms，`snap`，一点就动），下面的页面只变暗、不左移（左移会在玻璃后面留出一条空白）；**玻璃盖满屏幕之后才在它后面构建新页面**（第一帧排版再久，屏幕上也只是静止的模糊画面），画完第一帧玻璃就地变清（把这一帧拍成快照、一次算出 sigma 8 / 5 / 3 / 1.5 四张模糊图，依次交叉淡入，最后一张淡出露出页面，纸色一起退去；不要每帧重算整屏模糊——手机上每帧 9–15 ms、120Hz 下一抽一抽；也不要只拿一张模糊图淡出——淡到一半字就清楚了，不像对焦；`Motion.reveal` 900 ms，`ease`，按帧推进、一帧最多推进 25 ms，慢帧只让它慢一点、不跳一截），页面对焦出来。返回是整页向右滑出（240 ms，`mech`），下面的页早已建好、不用盖板。整页画进自己的层（`RepaintBoundary`）只做平移 |
| `shared/widgets/press_feedback.dart` | `PressHold`：可点部件的按下状态——手指落下等待 `kPressTimeout`（100 ms），期间移动超过 `kTouchSlop` 不显示反馈；快速点按在抬起时显示，反馈至少保持 `Motion.press`，已显示后拖动超过阈值立即松开；`PressBuilder` 是给没有自己状态的部件（标签、小标签、闭包里的行）用的同一件事；`pressTint` 是块、标签、行统一的按下颜色（底色上盖一层 10% 的墨） |
| `main.dart` `buildAppTheme` | Material 自带部件的主题（按钮、输入框、对话框、菜单、开关……都改成这套样式） |

字体：界面字是 **Saira**（`assets/fonts/Saira.ttf`，SIL OFL，许可证同目录），可变字体，字重和宽度一律通过 `sairaStyle` 设轴；中文落到内置的**思源黑体**（`NotoSansSC`，可变字重，每台手机一样），缺字才用系统字体。
页面大标题（`heading()` 22 号及以上）用最粗的 900，像游戏里的大白字；其余标题 700。
装饰小标（`eyebrow()`：分区上的英文标签、底栏小字；不加 `// `，原创文字里斜杠是个实心方块）用游戏里的**原创文字**（`cipherStyle`，`EndfieldByButan`，CC BY-NC 4.0，见 `assets/fonts/README.md`）：只有拉丁字母、数字和少量标点，是装饰，旁边总有中文说同一件事；要读的字（剧情里的种类标签等）不用它。
资料页里列表行的名字和组标题与书架的名字一样用粗体标题（`heading(16)`），不用正文字。
阅读字体可在设置里选（默认黑体 = 思源黑体，可换霞鹜文楷），选项的名字用各自的字体写（`readingFontSample`）；token 是 `readingFontFamily`，长文一律用 `readingStyle()`。
内置的两个中文字体是子集（GB2312 + 两个知识库与 App 文案里出现的字，约 9100 字，各约 4 MB）：重建知识库后用 `tools/subset_fonts.py` 从完整字体重新裁一次。

## 3. 写界面时的规则

- **新页面**：推入的页面用 `PageScaffold`（顶栏有返回、标题、操作），主标签页用 `MainTopBar`。全 App 不用 `AppBar`（守卫测试）。列表用 `pagePadding` 让出顶栏和底栏。
  单手读的页面（现在只有剧情阅读器，开发者 2026-10-26）用 `DockScaffold`（`shared/widgets/dock_scaffold.dart`）：控件是浮在正文上、靠近屏幕底部的几块分开的板（离两边 12 px、离手势条 8 px、彼此隔 8 px），不是一条连到底边的实心栏。板是面板色加细框，能点的切一个角，按下时填强调色，不用意义不明的灰块。左边返回，中间标题板（标题、下面一行状态、右边箭头，进度线沿板的下沿），右边每个操作一块 48×48 的板。往后拖正文时板滑出屏幕下方，往回拖、到开头或结尾、点正文空白处时回来，再点一次让开（和 Wiki、问答的栏一样，`BarsFollower(away:)`，状态由页面自己存，不动主界面的栏）。正文铺到屏幕底，结尾留出 `floatingDockRoom`。标题打开的面板同样是一块浮板，放在控件上方、同宽，从下往上展开；面板开着时控件不让开。
- **能点的东西切一个角**（`CutBorder`、`AppButton`、`IndexTag`、可点的 `ThemeAwareCard`）；不能点的容器是直角。
- **一组操作只有一个主要按钮**（`ButtonKind.go`，静止就是强调色）；删除用 `ButtonKind.danger`，并先用 `confirmAction(danger: true)` 问一句；其余用 normal / quiet。
- **列表**是细线分隔的行（`LibraryRow` / `ActionRow` / `PressRow`），不是卡片网格；行里有编号、日期、计数时用 `field()` 排出来，都是真实数据。
- **分隔符**用 `/` 或竖线（`FactsRow`），不用 `·`。
- **英文小标**是中文标题的直译（`// SHELVES` / 书架）；想不出贴切的英文就只写中文或用编号。
- **加载**用 `LoadingView` / `BusyMark`（分段条，不知道进度时一段亮格走动，完成即停），不用转圈（守卫测试）。
- **栏让出屏幕**（0.19.1，Wiki 与问答）：往后拖内容时顶栏收到状态栏下、底栏滑出，往回拖或回到顶部时回来（`MainTopBar(hides: true)`、`BarsAway`、`BarsFollower`，`shared/providers/bars_provider.dart`）。只做平移，内容不重新排版；坐在底栏上的东西（问答输入框、Wiki 工具按钮）包一层 `BarsAway(distance: tabBarRoom(context))` 一起下移。资料页、设置不收起。Wiki 的站点固定栏通过 CSS 变量同步当前占位，收起与恢复均使用 `BarsAway` 的时长和曲线；减少动效时立即切换。
- **铺到系统栏下**（0.20）：状态栏、导航栏透明，图标深浅跟 App 的主题（不跟系统）。顶栏背景从屏幕最顶上画起，收起时连状态栏那一块一起移出，内容透到状态栏下；不加渐变或遮罩。
  没有底栏的页面，列表最后留出 `viewPadding.bottom`（`pagePadding` 已含）；底部弹出、对话框的背景画到底边，内容避开手势条。
- **问答输入框**（0.20，`ask_composer.dart`）：没有焦点时一行（选项、草稿第一行、发送），整条除按钮外点哪里都给输入框焦点；有焦点时两行（文字在上、按钮一排在下，按钮之间的空白也给焦点），可展开到半屏、全屏。
  回车一律换行，只用发送按钮发。两种形态用同一个 `TextField`（固定的 `Stack` 结构，不重建），否则一切换形态焦点就丢、键盘收回。输入框所在区域从顶栏下沿到当前页面底边提供有限约束；页面底边由 `Scaffold` 随键盘缩短，不重复扣减键盘高度。上下文提示先占空间，输入框在剩余空间内展开，全屏仍避开顶栏。面板用 `ClipRect` 裁切，尺寸动画期间文字不能画到框外。
- **可以点的人名**（0.20，开发者 2026-10-26）：答案里字保持正文色，用 2 px `accentPrimary` 下划线。阅读器里不用下划线，能点的名字用 `heading(14)`（Saira，700）；深色用 `accentText`，浅色用 `textPrimary`，字高下方约 40% 垫 `accentPrimary` 填充。不能点的名字仍用 `ui(14, weight: 700, color: textSecondary)`。名字行高保持 20 px，热区扩到 48×48，不改正文排版。
- **名字旁的立绘预览**：竖长的小卡片（172×300，不超过半屏高）：整身立绘占满上部，底下一条放名字、句数与小号“更多”。在名字下方 6 px，放不下时放上方，左右留 16 px（所以卡片可能在名字的右下、左下、右上、左上）。“更多”打开大卡片；第一下点外面只关卡片，滚动、返回也关，同时只有一张。预览不取焦点；出现时从名字展开（`Motion.dialogIn`）：靠名字的那条边先从名字所在的位置向两边拉开，接着卡片从这条边展开，在名字下方往下、在上方往上（放在上方时卡片按下沿定位，不按上沿）；退出淡出，减少动效时立即切换。
- **立绘**（0.20）：立绘区是展示内容，直角、不可点、面板色底，图片 contain、底对齐；没有图时斜线纹加一句话。见 `PORTRAITS.md` §4。
- **阅读器的查找**：底部弹出只有内容那么高：输入框、下面一句说明会列出什么（没有结果时写没有结果），有结果时列表最高到键盘以上空间的 60%。不要给它固定高度，否则键盘下面是一大片空白。
- **立绘换图**：`PortraitImage` 换了另一张立绘时，新图做好之前继续显示上一张（同时仍持有上一张的 provider，图片不会在显示中被释放），不在两张之间露出空底。
- **阅读器的进度面板**（0.20）：点底部的标题板展开行号、百分比、所在步骤、当前行与 `AppSlider`（滑块在面板最下面，挨着拇指）；再点标题、点正文或按返回键收起。拖滑块或点轨道按行跳转，每帧最多处理一次定位，松手保存进度并保留面板。手指在滑块上时（松手后再等一个 `Motion.wipe`）不按屏幕上的行重算进度：屏幕上第一行是所在那组的第一行，比手指指的差一两行，重算会把滑块拉回去、来回抽动；`AppSlider` 拖动时也不跟外部取整后的值。滚动正文时面板保留，滑块跟随当前行。工具栏的定位按钮仍用于回到引用行。
- **滑块**（`AppSlider`）：48 px 高触控区、28 px 粗轨道、右下切角；已填部分用 `accentPrimary`、未填部分用 `divider`，填到滑块中线。滑块是 40×40 的墨色方块（`textPrimary`，右下切角，上下各伸出轨道 6 px），中间两道握纹，按住时握纹变强调色（开发者 2026-10-26：要大方块，不要细指针）。拖动直接跟手；点轨道与外部改值使用 `Motion.row` / `Motion.snap`，减少动效时立即到位。可选等距分档，换档用轻触感；拖动时回调 `onChanged`，松手或点轨道后回调 `onChangeEnd`。支持键盘方向键与读屏加减，当前值用 `field()` 显示在滑块上方或右侧。现在只有阅读器的进度面板用它；设置里的档位用分段选项（开发者 2026-10-26），标题只写设置名称。
- **左侧的 trace 线**（0.20 复核）：它是一条会延展的线，不是变粗的块。宽度固定 3 px（`traceRailWidth`），动的只有长度：`TraceRail` 从上往下伸到所在内容的全高（`snap`），收回时从下往上（`mech`）。
  - 列表行按下（`PressRow`）：线沿行落下、行右移 6 px，抬起收回。点了以后线在 `Motion.press` 内伸满，并一直留到新页面盖过来（`Motion.coverIn + Motion.row`）再收回：跟着按压收回时，快点一下线只伸到一半就往回缩，新页面已经盖上来了。状态行、展开头这类不该动的行用 `shift: false`，按下只盖一层薄墨。
  - 展开的东西（`FoldBlock`：`FoldSection`、`FoldTile`、工作过程的每一步、思考过程、GitHub 令牌）：按下时线沿头部落下，展开时随内容的 `AnimatedSize` 一起往下伸，**展开期间常驻**，收起时随内容收回。头部打开前后不变（工作过程的参数预览一直在），只有内容从下面进来。懒加载的档案（`ProfileSliver`）每行画自己那一段，连成一条。
  - 当前项：差分缩略图里当前的一张、阅读器的续读行、引用的资料段落常驻一条；换选择时旧的收回、新的落下。续读行的线画在左边距里，不把那一行挤进去。
  - 不要再用 `AnimatedContainer(width: 0→4)` 画按下线，也不要用 Material 的 `ExpansionTile`（用 `FoldTile`）。时间线不用 `IntrinsicHeight`（展开的长输出每帧要排两次版，会卡）。展开的内容第一帧就要排完版：工作过程里超过 3000 字的输出按 30 行一段放进懒加载的列表（`SelectionArea` 里仍能选字），否则几万字在展开的第一帧一次排完，线和内容直接跳出来（收起时已经排好，所以收起不卡）。
- **按钮的大小**：画出来比触控区小。`AppButton` 普通 42 高、`small` 34 高（触控区都是 48）；`SquareIconButton` 画 38×38。卡片、列表行里的次要操作用 `small`，一组只一个 `go`。
- **点空白处唤回栏**（0.20，Wiki 与问答）：栏让开后，点内容里不能点的地方（正文、空白；不是按钮、链接、行）唤回顶栏和底栏，再点一次让开（在页面顶部不让开）。只认点按结束：问答里是列表外层的 `GestureDetector.onTap`（里面能点的东西先赢，拖动归列表），Wiki 里是页面脚本的 `click`（浏览器不为滚动、长按发 click；落在链接、控件、带处理器的元素上或选了字时不算），都走 `BarsFollower.tapped`。
- **补充资料页**（0.20 复核）：标签已经写着“补充资料”，页内不再重复大标题；开头一句用途、两个小号导入按钮（新建在顶栏 +，个人资料为空时空状态里也有）。每条资料一行：名字和字段（种类 / 是否参与问答 / 索引状态）点开阅读，右边开关选它参与问答，下面一排小号次要操作（来源说明、编辑、重试或取消索引）。来源说明是说明文字，不用 `NoticeBox`；个人资料正文用阅读字体，不套卡片。资料原文打开时，引用的段落从顶栏下沿开始，不被顶栏盖住。
- **分段选项**（`SegmentedChoice`）：墨色细框，选中的一段填墨；换选项时墨块用 `Motion.row` / `Motion.snap` 滑到新的一段，经过的字随覆盖程度由墨变纸色，不闪切（减少动效时立即到位）。每段左右只留 2 px，七个短值在手机宽度上放得下。
- **底部标签栏**（`AppTabBar`）：当前项是一块切角的强调色，换标签时这一块用 `Motion.wipe` / `mech` 滑到新的一格（和分段选项一样滑，不在两格之间闪切）；按下其他格只盖薄墨。
- **Wiki 的固定栏跟着栏走**：栏让开、回来时只改两个 CSS 变量；扫描整页找站点自己的固定栏、改页面边距只在页面加载和栏的尺寸变化时做。栏每次进出都扫一遍整页（还有 600 / 1600 ms 两次补扫）会让滚动卡顿，往回翻时栏回来正好撞上。
- 阅读器的进度面板开着时，跳到的那一行放在正文顶上，“当前在第几行”与保存的进度只算面板上沿以上的行。面板里每一行固定高度（强制行高，换行当空格，有步骤的剧情始终留出步骤那一行），拖动时面板不随预览的长短、中英文变高，滑块不抖。
- **空状态**用 `EmptyState`：一句完整的话说明这里将来会有什么，有下一步就给按钮。
- **提示与出错**用 `NoticeBox` / `kbFlag`（强调色小旗），贴在出问题的地方；输入框的错误写在框下（`errorText`），不弹底部提示。
- **底部弹出**用 `showAppSheet`（机械推入、不回弹），**对话框**用 `showAppDialog` + `AppDialog`。
- **短消息**用 `showToast`；能撤销的操作（移除书签）给"撤销"。

## 4. 人机交互约定

- **触控区至少 48×48**（按钮、图标按钮、标签、页码、开关、折叠头；画出来可以小，热区不能小）。纯图标按钮必须有 `tooltip`（也是读屏念的名字）。
- **字号**：正文 16（长文 15.5–16.5），界面字不小于 12；守卫测试拒绝 `fontSize` 小于 12。
- **对比度**：次要文字 `textSecondary`、最淡的 `textMuted` 在纸面上都 ≥ 4.5:1；输入框与控件的边框 `cardBorder` ≥ 3:1。
- **读屏**：选中的标签、开关、折叠头带 `selected` / `toggled` / `expanded`；状态行用 `liveRegion`。
- **按压反馈**：自己画按下样子的部件用 `PressHold`（`pressListener` + `pressed`）。手指落下先等待 `kPressTimeout`（100 ms），超过 `kTouchSlop` 的滚动不显示反馈；快速点按抬起时显示，保持至少 `Motion.press`，持续按住时显示后再拖动则立即松开。每个可点部件都要有反馈：块、标签用 `PressBuilder` + `pressTint`，列表行用 `PressRow`。展开的工具结果只在标题行显示按压反馈，结果区独立滚动、选字。不要自行用 `Listener` 或 `onTapDown` 设置按压状态，不用 `InkWell`。
- **流式内容只重建变了的部分**：问答列表每条消息各自 `select` 自己（`_MessageAt`），页面只看消息条数和是否在写；不要在页面上 `ref.watch(askChatProvider)` 整个列表。
- **出现的东西一点就动**：换页、面板推入这类回应点按的进场用 `snap`（快起步、慢停）；`mech`（慢起步）只给退出和擦入，进场用它前 100 ms 几乎不动，像没点上。折叠展开同理：打开用 `snap`、收起用 `mech`。
- **重的画面只画一次**：`IndustrialBackdrop` 的等高线是自己的一层；动画里只改位置、透明度的包装不要随动画值增删（`if` 只能加在 `Stack` 末尾的装饰上），否则整页在首尾帧被重新挂接。整页平移（换页、`SwitchedPages`）和 `AnimatedSize` 展开的内容包一层 `RepaintBoundary`。
- **减少动效**：所有动效走 `Motion.of(context, …)`；系统打开"减少动态效果"时换页、擦入、展开、走动的进度格全部静止。
- **系统手势**：Wiki 页从左缘右滑是后退、从右缘左滑是前进（与浏览器一致）；导览页的系统返回键回到上一步。
- **键盘**：问答输入框旁的面板与按钮不取焦点（键盘不收起）。底栏在键盘高过它之后才收起（`MainShell`，底栏的 `SafeArea` 保持系统导航条的高度），输入框先停在底栏上、再跟着键盘走，中间不跳。
  不在屏幕上的主标签按全屏高度排版、看不到键盘（`_TabSlot`）：否则键盘每动一帧，`IndexedStack` 把四个标签全部重建、重排一遍。
- **后台的标签不运行**：主标签和 Wiki 的站点各包一层 `TickerMode`，只有显示的那个开着；Wiki 的网页在 `TickerMode` 关掉时暂停（`WebView.onPause`）。Android 上 Flutter 的帧在 Android 主线程上开始，后台的网页每帧重画会拖慢所有页面。
- **网页用混合合成**（`useHybridComposition: true`）：网页是系统直接合成的视图。画进纹理再由 Flutter 合成时，网页每个 vsync 出一帧，Flutter 却取得不匀，四分之一的帧没显示出来，滑动一抽一抽（2026-10-24 追踪）。profile 版的日志里 `[webfps]` 是网页自己的帧率，和 `[frame]` 对照看。
- **刷新率**：`MainActivity` 向系统要当前分辨率下最快的显示模式（ColorOS 等系统不给没要的 App 高刷，Flutter 不会自己要）。
- **加载**：Wiki 网页加载时显示网页自己报告的进度（`SegmentProgress` 带数值），不用走动的格子。
- **长文只排屏幕附近的**：慢帧几乎都是文字排版（`RenderParagraph`）。长文一律是懒列表，一段（一行台词、一条语音）一项：阅读器（缓存上下各 480 px）、档案（`ProfileSliver`）、条目页的正文和语音（`EntryPage.textSliver`：面板是 `DecoratedSliver`，里面是懒列表）。不要把长文放进 `Column` 或 `SliverToBoxAdapter`。
- **不让看不见的页面重建**：被盖住的页面照样会因为 provider 变化而整页重建。阅读器滚动时只保存进度，关闭时才通知进度相关的页面（`invalidateReadingIn`）；每次保存都通知，资料首页和集合页在下面每隔几百毫秒整页重建一次。
- **长标签**：顶部标签放不下时缩短（省略号），不滚出屏幕；窄屏上一行放不下的按钮换行，不溢出。

## 5. 守卫测试

- `test/guards/square_shapes_test.dart`：不用圆角、圆形、`_rounded` 图标、回弹曲线。
- `test/guards/floating_docks_test.dart`：不用 `AppBar`。
- `test/guards/design_rules_test.dart`：不用转圈、投影、elevation、红绿（与琥珀、橙）色、Material 原生开关 / 分段按钮 / 底部弹出（这套样式各有自己的版本），`fontSize` 不小于 12。

截图检查：`test/support/screenshot.dart` 的 `shoot()`（`ARKLORES_SHOT_DIR`）。要看真实字体时，在测试里用 `FontLoader` 加载 `assets/fonts/` 里的 Saira、NotoSansSC（和要看的 EndfieldCipher）再截图。

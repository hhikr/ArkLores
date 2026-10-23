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
  强调色只做**填充**；浅色主题里黄色不当线、不当字（白底上看不见），"标出当前位置的线"用 `trace`（浅色为墨、深色为蓝）。
- **红色只给删除**（`danger`）。出错、警告、失败一律是强调色小旗加墨字；判定结果不用红绿（成立 = 墨色实线框，不成立 = 强调色块）。
- 不用投影、发光、渐变、圆角。

## 2. 代码在哪

| 文件 | 内容 |
| --- | --- |
| `shared/theme/app_theme.dart` | `AppThemeTokens`（全部颜色 token 的含义）、`sairaStyle`、`AppType` 扩展：`ui()` 界面字、`eyebrow()` 宽体小标、`field()` 数字与日期、`heading()` 标题、`text()` 正文 |
| `shared/theme/endfield_theme_tokens.dart` / `ark_theme_tokens.dart` | 浅色 / 深色两套完整取值（深色不是反色） |
| `shared/theme/cut_border.dart` | `CutBorder`：切角形状（可点的东西才用） |
| `shared/theme/motion.dart` | `Motion`：三条曲线（`snap` 出现、`mech` 擦入与所有退出、`ease`）、各档时长、`Motion.of()`（减少动效时为 0） |
| `shared/widgets/ef_widgets.dart` | 部件：`TriStrip` 三色条、`Hatch` 斜线纹、`Eyebrow`、`SectionTitle`、`IndexTag` 编号、`FactsRow` 字段行、`FilterBlock` 筛选块、`AppButton`（normal / go / danger / quiet，按下擦入、busy 铺斜线纹）、`SquareIconButton`、`NoticeBox` 提示、`EmptyState` 空状态、`SegmentProgress` / `BusyMark` / `LoadingView` 分段进度、`SquareSwitch`、`SegmentedChoice`、`Figure` 大数字、`InkPanel`、`PressRow` 按压行、`ActionRow`、`showAppSheet` + `SheetFrame` / `PlainSheet`、`showAppDialog` + `AppDialog`、`confirmAction`、`showToast` |
| `shared/widgets/page_frame.dart` | `PageScaffold`（推入页的顶栏）、`MainTopBar` + `TopTab` + `TopBarTitle`（四个主标签页的顶栏）、`AppTabBar`（底部标签栏）、`DockPanel`（盖在内容上的控件板）、`pagePadding` |
| `shared/widgets/theme_aware_card.dart` | 面板：可点时右下切角、按下时底边擦入强调色 |
| `shared/widgets/smooth_page_route.dart` | 换页：斜切快门从右推入（360 ms，返回 240 ms） |
| `main.dart` `buildAppTheme` | Material 自带部件的主题（按钮、输入框、对话框、菜单、开关……都改成这套样式） |

字体：界面字是 **Saira**（`assets/fonts/Saira.ttf`，SIL OFL，许可证同目录），可变字体，字重和宽度一律通过 `sairaStyle` 设轴；中文落到系统黑体。
阅读字体可在设置里选（默认黑体，可换回霞鹜文楷），token 是 `readingFontFamily`，长文一律用 `readingStyle()`。

## 3. 写界面时的规则

- **新页面**：推入的页面用 `PageScaffold`（顶栏有返回、标题、操作），主标签页用 `MainTopBar`。全 App 不用 `AppBar`（守卫测试）。列表用 `pagePadding` 让出顶栏和底栏。
- **能点的东西切一个角**（`CutBorder`、`AppButton`、`IndexTag`、可点的 `ThemeAwareCard`）；不能点的容器是直角。
- **一组操作只有一个主要按钮**（`ButtonKind.go`，静止就是强调色）；删除用 `ButtonKind.danger`，并先用 `confirmAction(danger: true)` 问一句；其余用 normal / quiet。
- **列表**是细线分隔的行（`LibraryRow` / `ActionRow` / `PressRow`），不是卡片网格；行里有编号、日期、计数时用 `field()` 排出来，都是真实数据。
- **分隔符**用 `/` 或竖线（`FactsRow`），不用 `·`。
- **英文小标**是中文标题的直译（`// SHELVES` / 书架）；想不出贴切的英文就只写中文或用编号。
- **加载**用 `LoadingView` / `BusyMark`（分段条，不知道进度时一段亮格走动，完成即停），不用转圈（守卫测试）。
- **空状态**用 `EmptyState`：一句完整的话说明这里将来会有什么，有下一步就给按钮。
- **提示与出错**用 `NoticeBox` / `kbFlag`（强调色小旗），贴在出问题的地方；输入框的错误写在框下（`errorText`），不弹底部提示。
- **底部弹出**用 `showAppSheet`（机械推入、不回弹），**对话框**用 `showAppDialog` + `AppDialog`。
- **短消息**用 `showToast`；能撤销的操作（移除书签）给"撤销"。

## 4. 人机交互约定

- **触控区至少 48×48**（按钮、图标按钮、标签、页码、开关、折叠头；画出来可以小，热区不能小）。纯图标按钮必须有 `tooltip`（也是读屏念的名字）。
- **字号**：正文 16（长文 15.5–16.5），界面字不小于 12；守卫测试拒绝 `fontSize` 小于 12。
- **对比度**：次要文字 `textSecondary`、最淡的 `textMuted` 在纸面上都 ≥ 4.5:1；输入框与控件的边框 `cardBorder` ≥ 3:1。
- **读屏**：选中的标签、开关、折叠头带 `selected` / `toggled` / `expanded`；状态行用 `liveRegion`。
- **减少动效**：所有动效走 `Motion.of(context, …)`；系统打开"减少动态效果"时换页、擦入、展开、走动的进度格全部静止。
- **系统手势**：Wiki 页从左缘右滑是后退、从右缘左滑是前进（与浏览器一致）；导览页的系统返回键回到上一步。
- **键盘**：问答输入框旁的面板与按钮不取焦点（键盘不收起）。
- **长标签**：顶部标签放不下时缩短（省略号），不滚出屏幕；窄屏上一行放不下的按钮换行，不溢出。

## 5. 守卫测试

- `test/guards/square_shapes_test.dart`：不用圆角、圆形、`_rounded` 图标、回弹曲线。
- `test/guards/floating_docks_test.dart`：不用 `AppBar`。
- `test/guards/design_rules_test.dart`：不用转圈、投影、elevation、红绿（与琥珀、橙）色、Material 原生开关 / 分段按钮 / 底部弹出（这套样式各有自己的版本），`fontSize` 不小于 12。

截图检查：`test/support/screenshot.dart` 的 `shoot()`（`ARKLORES_SHOT_DIR`）。要看真实字体时，在测试里用 `FontLoader` 加载 `assets/fonts/Saira.ttf` 和一个中文字体再截图。

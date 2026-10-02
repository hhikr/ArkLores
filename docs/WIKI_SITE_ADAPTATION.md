# Wiki Site Adaptation

ArkLores 的 Wiki 浏览器使用 WebView 展示远程站点。站点适配分为三层：

1. **站点识别**：根据当前 URL 的 hostname 选择适配策略。
2. **主题桥接**：只修改站点已经定义的主题状态；不对第三方页面做全量反色。
3. **阅读器正文定位**：为每个站点选择正文根节点，再应用 LXGW、字号、间距和阅读器控件。

## 当前内置来源

| ID | 来源 | 前端结构 | 主题机制 |
| --- | --- | --- | --- |
| `prts` | PRTS Wiki | MediaWiki | MediaWiki 原生主题 class |
| `endfield` | Endfield Wiki | 用户在设置中选择 fz 或 Warfarin | 按当前 URL 自动选择站点策略 |

Endfield Wiki 只占用一个标签页。设置页编辑该来源或添加自定义来源时，URL
输入框下方会提供 `Warfarin` 与 `fz.wiki` 预设。旧版分别保存的
`endfield-warfarin` 与 `endfield-fz` 会折叠为一个 `endfield` 来源，
保留列表中第一个已配置的终末地地址。

## 主题策略

### fz.wiki

fz.wiki 自己维护 `endfield-wiki-theme` localStorage 状态，并在根节点使用
`data-theme="light|dark"`。ArkLores 的适配只设置该根节点属性、同步其持久化
状态和 `theme-color`，不重写站点的强调色、卡片色和数据表样式。

### warfarin.wiki

Warfarin 的 CSS 使用 `.dark` 选择器切换一组语义变量。ArkLores 只切换
`html.dark`、设置 `color-scheme` 和 `theme-color`，不直接覆盖
`--background`、`--foreground`、`--card` 等变量。

主题桥接脚本会在 WebView 的 document-start 阶段运行，并把当前模式短暂保存
在 sessionStorage，降低站点导航和 WebView 重新加载时的白色闪屏。

## 阅读器策略

阅读器仍然使用内置 LXGW WenKai 字体，但正文根不再固定假设
`#mw-content-text`：

- PRTS 使用 MediaWiki 正文根。
- fz 优先使用文章布局第一列，再回退到 `data-page-content`、`data-content`
  和 `article`。
- Warfarin 优先使用主内容列，再回退到其页面主容器。

导航栏、侧栏和页脚继续由阅读器隐藏；正文内部的图片、表格、按钮、输入框、
音频和其他交互组件保留原生行为。复杂组件仍需要按页面类型单独增加适配，
不能用一套通用 CSS 覆盖所有 Wiki。

### fz 阅读器布局保护

fz 的条目正文由卡片组件组成，图片可能通过卡片容器的
`background-image`、`mask-image`、`-webkit-mask-image` 或 CSS 视觉层加载，
而不是直接使用 `<img>`。阅读器对 fz 页面会保留这些视觉容器的图像、着色和
尺寸，同时把正文列改为流式宽度；对懒加载 `<img>` 会在进入阅读器时主动触发
加载。

干员页还包含固定宽度、`min-width`、`aspect-ratio`、flex/grid 和
`overflow-hidden` 的多层组合。阅读器会在正文挂载完成后检查超出正文列的
容器，添加移动端约束，并监听异步 DOM 更新重新发现正文根、重新标记媒体节点；
窗口尺寸变化也会触发重新计算。退出阅读器时会移除观察器和临时 class，避免影响
普通模式。

## 验证要求

每次修改站点适配时至少运行：

```text
flutter analyze
flutter test test/wiki_appearance_test.dart test/wiki_site_adapter_test.dart
flutter test test/bookmark_service_test.dart
```

真机验收需要分别验证：

- fz：亮色、暗色、页面内跳转和 WebView 重新加载；
- Warfarin：亮色、暗色、语言路由和干员详情页；
- 两站阅读器：字号调节、图片、表格、按钮和返回普通模式；
- Android 与 iOS 的 document-start 主题是否都没有白闪。

当前适配只负责主题和阅读器基础正文定位，不承诺把两个站点的所有业务组件
转换为统一的电子书排版。剧情模拟器、图鉴交互和动态数据表应继续保留为站点
原生组件，并在出现具体布局问题时建立页面级适配。

# Wiki Site Adaptation

ArkLores 的 Wiki 浏览器使用 WebView 展示远程站点。站点适配分为两层：

1. **站点识别**：根据当前 URL 的 hostname 选择适配策略。
2. **主题桥接**：只修改站点已经定义的主题状态；不对第三方页面做全量反色。

## 当前内置来源

| ID | 来源 | 前端结构 | 主题机制 |
| --- | --- | --- | --- |
| `prts` | PRTS Wiki | MediaWiki | 站点自带的黑夜模式：MediaWiki 的 `skin-theme-clientpref-night/day` class |
| `endfield` | Endfield Wiki | 用户在设置中选择 fz 或 Warfarin | 按当前 URL 自动选择站点策略 |

Endfield Wiki 只占用一个标签页。设置页编辑该来源或添加自定义来源时，URL
输入框下方会提供 `Warfarin` 与 `fz.wiki` 预设。旧版分别保存的
`endfield-warfarin` 与 `endfield-fz` 会折叠为一个 `endfield` 来源，
保留列表中第一个已配置的终末地地址。

## 主题策略

### prts.wiki

PRTS 新版站点自带黑夜模式（MediaWiki 的客户端偏好 class）。ArkLores 只在 `html` 与 `body` 上切换
`skin-theme-clientpref-night` / `skin-theme-clientpref-day`（去掉 `-os`），document-start 时先切 `html` 防白闪；
不注入任何样式（2026-10-17 起，之前是一套覆盖颜色的 CSS）。站点改了切换方式时这里要跟着改；真机未复查。

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

## 悬浮栏与网页留白（0.11）

App 的顶部站点栏（`wiki-site-bar`）和底部导航都是悬浮的，网页铺满整个屏幕（顶到状态栏下、底到屏幕底）。网页不能从外部留白，
所以由 `_applyDockInsets` 注入样式：给 `html` 上下加悬浮栏高度的 padding，并把网站自己 `fixed`/`sticky` 在顶部/底部的栏同样下移/上移；
每次 build 用 `_syncDockInsets` 同步高度。新增站点时要真机确认它的固定栏没有被悬浮栏盖住。

## 从问答打开页面（0.13）

答案里的 Wiki 出处弹窗有“在 Wiki 中打开”：写 `wikiOpenRequestProvider`（站点 id + 网址）并切到 Wiki 标签，`WikiBrowserPage` 按站点 id
（找不到时按域名）选标签并加载；标签还没恢复好时先记下，恢复后再打开。问答查 Wiki 的部分见 `WIKI_EVIDENCE.md`。

## 验证要求

每次修改站点适配时至少运行：

```text
flutter analyze
flutter test test/features/wiki/wiki_appearance_test.dart test/features/wiki/wiki_site_adapter_test.dart
flutter test test/features/wiki/bookmark_service_test.dart
```

真机验收需要分别验证：

- fz：亮色、暗色、页面内跳转和 WebView 重新加载；
- Warfarin：亮色、暗色、语言路由和干员详情页；
- PRTS：亮色、暗色（站点自己的黑夜模式）与页面内跳转；
- Android 与 iOS 的 document-start 主题是否都没有白闪。

当前适配只负责主题，不改站点的排版。阅读器模式与“转交给 AI”已于 2026-10-17 删除：
长文在资料页里读，问答自己会查 Wiki（`wiki_search` / `wiki_read`）。剧情模拟器、图鉴交互和动态数据表应继续保留为站点
原生组件，并在出现具体布局问题时建立页面级适配。

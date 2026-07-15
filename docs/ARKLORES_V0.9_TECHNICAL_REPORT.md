# ArkLores v0.9 技术与运行原理报告

> 审计基准：v0.9.0 release line，工程版本 `0.9.0+9`<br>
> 审计日期：2026-07-15<br>
> 报告范围：Git 跟踪的源码、平台工程、工具、测试与全部维护文档<br>
> 状态口径：v0.9 功能开发、分支合并、tag、推送与 GitHub Release 均已完成

## 1. 执行摘要

ArkLores 是一个使用 Flutter 构建的《明日方舟》与《明日方舟：终末地》剧情阅读和 AI 辅助应用。它不是一个把网页直接交给大模型的普通聊天壳，也不是一个在线 Wiki 搜索器。当前架构的核心是：开发者离线把中文游戏解包数据构建成结构化 SQLite 数据库，App 再下载并安装这个数据库；三个 AI Agent 只能通过 `search_local_lore` 工具查询该数据库，不能把模型记忆、Wiki 页面或用户文本伪装成游戏原文。

当前产品由四个一级入口组成：

1. **Wiki**：在两个 WebView 标签中浏览 PRTS Wiki 与 Endfield Wiki，支持历史导航、暗色注入、书签和选区转交。
2. **AI**：提供梗概、事实核查和角色扮演三种工作流。
3. **资料**：显示暂停说明；旧 PDF/TXT 导入和索引链路已经退出当前架构。
4. **设置**：管理双主题、双语、Chat API 配置、GameData 知识库和版本信息。

系统最关键的运行链如下：

```text
用户输入
  -> Flutter 页面
  -> Riverpod Chat/Roleplay Notifier
  -> Summary / Fact-check / Role-play Agent
  -> ReActLoop
  -> search_local_lore
  -> GameDataKnowledgeStore
  -> 本地 SQLite schema 2
  -> 带 provenance 的 Observation
  -> LLM 生成答案
  -> ReAct 来源与结论约束
  -> 消息气泡与 GameData 证据卡
```

v0.9 相对 v0.8.0 没有改变 GameData schema、检索算法、Agent prompt 或模型协议。实际变更主要位于设计系统与设置体验：建立方舟/终末地两套 token、全局工业背景、切角表面、重做底部导航和设置页，并增加窄屏、英文及大字测试。开发清单已经归档到 Git 历史；源码中仍存在的问题归类为已知技术债，而不是未交付功能。

## 2. 审计方法与边界

本报告以当前代码能够实际执行的路径为第一事实来源，优先级如下：

1. 当前 `dev` 分支源码和配置。
2. 自动测试及静态分析的可重复结果。
3. 当前架构文档和最新版本记录。
4. 历史任务说明与 release 记录。

审计时执行了 `flutter analyze` 和完整 `flutter test`。静态分析无问题；自动测试 61 项通过，3 项需要真实外部 Chat API 的测试按设计跳过。跳过不等于失败，但也不能被写成当前环境已完成的外部服务验收。

`logs/` 是调试会话产物，不是设计文档；报告只解释日志机制和隐私边界，不引用其中的用户问题、模型回复或工具 observation。Git 忽略的 API 凭据文件同样不属于审计内容。Flutter、Gradle、Xcode 生成文件只解释其平台作用，不把机械生成代码逐行当作业务设计。

## 3. 产品与架构演进

### 3.1 原型期：Wiki 与通用 RAG

早期版本围绕 Wiki 抓取、文本清洗、分块和本地资料展开。当前仓库仍保留 `core/wiki` crawler、PRTS 模板解析器和 `core/rag/chunker.dart`，测试也继续覆盖部分解析行为。这些代码说明项目曾经尝试把 Wiki 或用户资料构造成知识来源。

但“文件仍存在”不代表“运行时仍使用”。当前 Agent provider 没有引用 Wiki crawler，工具注册表也只注册 `search_local_lore`。因此这些模块应视为历史能力和可复用解析工具，而不是当前 RAG 主链。

### 3.2 v0.4.5：GameData-first 转向

v0.4.5 做出了决定性架构变更：中文 GameData release asset 成为主知识源。旧 Wiki seed、Book indexing、embedding、向量数据库与 TFLite 路线被废止。其原因不是 Wiki 没有价值，而是事实核查需要稳定 ID、原始路径、内容类型、原始记录 ID 和可复现的构建版本；普通网页片段很难稳定提供这些契约。

这次转向形成了三层信任模型：

| 层级 | 来源 | 当前 Agent 可否作为证据 | 用途 |
| --- | --- | --- | --- |
| 1 | GameData / 游戏原始文本 | 可以，且是唯一主动证据 | 梗概、事实核查、角色事实 |
| 2 | 指定 Wiki | 不可以 | 人工阅读、提出问题、转交上下文 |
| 3 | 用户导入资料 | 当前停用 | 后续重新设计低可信来源协议 |

### 3.3 v0.5-v0.8：三个工作流和证据体验

- v0.5 引入事实核查：把命题拆成范围、实体和关系词，输出 supported、refuted、uncertain、unavailable 四态。
- v0.6 引入证据约束的角色扮演：开始前解析 canonical character 与稳定 `entity_id`，每轮必须检索。
- v0.7 打通 Wiki 阅读到 AI 的显式转交：选中文字只是用户上下文，Agent 仍需独立查询 GameData。
- v0.8 把 observation 解析为结构化证据卡，并统一加载、取消、重试、错误和空状态。

### 3.4 v0.9：视觉系统与设置表面

v0.9 建立两套共享信息架构、不同视觉语法的主题：

- **Arknights / Tactical Archive**：中性黑灰、高对比蓝色导视、战术档案感。
- **Endfield / Industrial Signal**：白色主表面、浅灰层级、黑色信息骨架和亮黄色重点色。

两套主题共用页面结构、导航位置、组件行为与语义颜色接口，差异集中在 token、明暗属性、边框、表面、强调色和背景绘制。这使主题切换不会改变功能模型。

本轮直接视觉输入是用户在 2026-07-15 会话中提供的两张生成式设置页草图，分别表达
终末地与明日方舟方向。它们只用于提取颜色关系、信息密度和构图意图，不是游戏实机截图，
也不作为官方 UI 事实证据。最终 App 不打包草图、角色立绘、Logo、字标或游戏截图；品牌感
由代码绘制的网格、断线、切角、色标和排版层级表达。

共享视觉约束为：页面内容最大宽度 720 px；设置卡片约占内容区 94%；可用宽度小于
430 px 或文字放大时偏好项改为上下布局；底部导航固定 68 px 并保持每项等宽。截图基线
覆盖 360x800、420x900、中英文、双主题及 1.0/1.6 文字缩放。夜间重点色为
`#0BA0D0`，日间重点色为 `#F8D439`；两者均使用 Noto Sans SC，不使用受保护的游戏资产。

## 4. 总体系统架构

### 4.1 分层

```text
┌─────────────────────────────────────────────────────────┐
│ features: 页面、交互、显示状态                           │
│ Wiki | AI | Materials | Settings                        │
├─────────────────────────────────────────────────────────┤
│ shared: 主题、本地化、通用组件、跨功能 Provider          │
├─────────────────────────────────────────────────────────┤
│ core: Agent、LLM、GameData、Wiki parser、Chunker         │
├─────────────────────────────────────────────────────────┤
│ platform: Android / iOS、Secure Storage、WebView、SQLite │
├─────────────────────────────────────────────────────────┤
│ external: Chat API、Wiki 网站、GameData release asset    │
└─────────────────────────────────────────────────────────┘
```

`features` 可以依赖 `core` 和 `shared`；`core` 不依赖具体页面。Riverpod provider 是对象装配和状态传播的主要方式。仓库没有单独的 domain package，因此一些业务状态集中在 `agent_provider.dart`，这是当前架构最明显的高耦合点之一。

### 4.2 三条外部 I/O 边界

系统有三条性质不同的网络或存储边界：

1. **Chat API**：发送 system prompt、对话历史、用户请求和工具 observation，返回 ReAct 文本。API Key 保存在系统安全存储中。
2. **Wiki WebView**：浏览外部网页。页面内容默认停留在 WebView，只有用户主动转交时才读取当前 selection、标题和 URL。
3. **GameData asset**：下载 `.db.gz`，可验证压缩包 SHA-256，解压并校验 schema 后原子式替换本地数据库。

这三条边界不能混为一谈：Wiki 页面不是数据库，release asset 不是模型 API，Chat provider 也不会自动访问本地 SQLite。

### 4.3 状态所有权

| 状态 | 所有者 | 生命周期 |
| --- | --- | --- |
| 当前主题 | `ThemeNotifier` | App 进程；当前未持久化 |
| 当前语言 | `LocaleNotifier` | App 进程；当前未持久化 |
| API 配置 | `ApiConfigNotifier` + `SettingsService` | Riverpod + Secure Storage |
| 首次引导完成 | `onboardingStatusProvider` + Secure Storage | 跨启动持久化 |
| Summary/Fact-check 消息 | 各自 StateNotifier | 当前进程内 |
| Role-play 会话 | `RoleplayNotifier` + JSON store | 跨启动持久化 |
| Wiki 标签与历史 | `WikiBrowserPage` State + WebView | 页面存活期间 |
| 书签 | `BookmarkNotifier` + SQLite service | 跨启动持久化 |
| GameData DB | 文件系统 + SQLite | 跨启动持久化 |

## 5. 顶层目录与根配置

### 5.1 目录总览

| 路径 | 作用 |
| --- | --- |
| `lib/` | Flutter/Dart 产品源码，共享层、功能层和核心服务层 |
| `test/` | 单元测试、Widget 测试和 opt-in 真实 Chat QA |
| `tools/` | GameData 审计、构建、finalize、检索 QA 和安装向导 |
| `docs/` | 当前架构、数据规范、版本记录、设计与开发流程文档 |
| `android/` | Android Gradle 工程、Manifest、Activity、图标和启动样式 |
| `ios/` | iOS Xcode 工程、plist、AppDelegate、图标和 storyboard |
| `logs/` | 历史或调试会话日志，不参与编译和产品数据链 |

### 5.2 根文件

| 文件 | 作用 |
| --- | --- |
| `pubspec.yaml` | 包名、`0.9.0+9` 版本、Dart 约束、依赖和 Flutter 本地化开关 |
| `pubspec.lock` | 锁定直接与传递依赖版本，保证环境可重复 |
| `analysis_options.yaml` | 继承 `flutter_lints`；当前没有额外收紧规则 |
| `l10n.yaml` | 指定 ARB 目录、英文模板和生成文件输出目录 |
| `README.md` | 产品入口、当前知识源、运行方式和结构摘要 |
| `CHANGELOG.md` | v0.9 与历史版本变化、发布资产元数据 |
| `CONTRIBUTING.md` | 分支、提交、测试、来源和凭据约束 |
| `CLAUDE.md` | 面向代码代理的项目约束与常用命令 |
| `.metadata` | Flutter 工程元数据，用于工具识别与迁移 |
| `.gitignore` | 排除构建物、本地配置、凭据和平台临时文件 |
| `arklores.iml` | IntelliJ/Android Studio 模块元数据，不承载业务逻辑 |

## 6. 启动、依赖装配与路由

### 6.1 `lib/main.dart`

`main()` 首先调用 `WidgetsFlutterBinding.ensureInitialized()`，确保插件通道在 `runApp` 前可用。随后创建 `SettingsService`，依次读取首次引导状态和 `LLMConfig`。读取失败只通过 `debugPrint` 报告并使用默认值，因此安全存储异常不会阻止 App 启动。

读取结果通过 `ProviderScope.overrides` 注入两个声明为 `UnimplementedError` 的 provider：

- `onboardingDoneProvider`：同步提供启动时读取的布尔值。
- `initialApiConfigProvider`：同步提供启动时读取的 API 配置。

这种方式把异步启动 I/O 限制在 `main()`，使后续 Widget 可以同步读取初始状态。

`ArkLoresApp` 监听主题、语言和 onboarding 状态，构造 `MaterialApp`。两个主题槽都使用同一个动态生成的 ThemeData，`themeMode` 固定为 dark，但 ThemeData 自身的 brightness 来自 token；因此 Endfield 仍可表现为亮色。全局 `builder` 再套一层 `IndustrialBackdrop`，使主页面和子路由共享背景绘制。

首次启动显示 `OnboardingPage`，完成后把 `onboardingStatusProvider` 改为 true，根 Widget 随之切换到 `MainShell`。命名路由当前只直接注册 `/knowledge-base` 和 `/api-settings`。

### 6.2 `lib/app.dart`

`MainShell` 保存 `_currentIndex`，并把 Wiki、AI、Materials、Settings 四页放进 `IndexedStack`。IndexedStack 的意义是切换底部标签时不销毁非活动页：Wiki WebView 历史和 AI 页面局部状态可以保留，但代价是四页会同时保持在 Widget 树中。

主题改变时，外层 `AnimatedSwitcher` 的 key 随 `themeName` 改变，通过 300ms FadeTransition 重建视觉树。底部 `_IndustrialNavigation` 自行实现，不使用标准 `NavigationBar`：固定 68 高度、顶边框、选中顶部强调线、图标和单行省略标签。每个 `_NavigationItem` 包含 button/selected semantics。

文件末尾的 `KnowledgeBaseRoute` 和 `generateAppRoute()` 是另一套路由包装，但根 `MaterialApp` 当前没有调用 `generateAppRoute`，因此这部分属于可移除或待统一的重复路由实现。

## 7. `shared/`：共享设计与跨功能状态

### 7.1 `shared/theme/`

`AppThemeTokens` 是设计系统的抽象契约，定义背景、表面、强调色、语义色、文字、分隔线、来源 badge、导航、字体、圆角、阴影、切角和主题元信息。具体页面读取接口而不是判断主题类，保证两套主题共享组件行为。

`ArkThemeTokens` 和 `EndfieldThemeTokens` 分别实现全部 token。两者都使用 Google Fonts 构造 title/body 样式。主题实例不只是颜色表：`isDark` 决定 Material brightness，`isEndfield` 影响背景和部分前景选择，`cornerCut` 控制切角表面几何。

`ThemeNotifier` 默认持有 Ark token，通过 `switchTo` 或 `toggle` 替换整个 token 对象。当前主题选择没有写入 Secure Storage，因此重启后回到 Ark 主题。

### 7.2 `shared/widgets/industrial_ui.dart`

- `IndustrialBackdrop`：为整个 App 提供透明叠加绘制层。
- `IndustrialPageHeader`：统一页面标题、编号/eyebrow、描述与尾部操作。
- `IndustrialSectionHeader`：统一设置等页面的分区标识。
- `_MarkerClipper`：裁剪标题旁的工业标记。
- `_BackdropPainter`：按主题绘制非均匀网格、断线、透视线和斜向强调线。

背景通过 CustomPainter 生成，不依赖图片资产，也不进入 WebView 网页 DOM。`shouldRepaint` 根据关键 token 判断是否需要重绘。

### 7.3 `theme_aware_card.dart`

`ThemeAwareCard` 是当前主要表面容器。它读取主题 token，用 `_CutCornerClipper` 生成切角路径，再由 `_IndustrialBorderPainter` 绘制边框和强调细节。它解决了不同页面重复写 card color、border、radius 和 shadow 的问题，同时让 Ark 与 Endfield 共享布局而呈现不同材质。

### 7.4 `citation_card.dart`

这是旧 Wiki/Book 引用卡组件，只支持 `CitationSourceType.wiki` 与 `book`，通过 AnimationController 和 AnimatedCrossFade 展开内容。当前 AI 的 GameData 证据使用 `chat_bubble.dart` 内的专用 evidence UI，而不是此卡。组件中的“View in Wiki”仍是 TODO，因此它不是当前可用的来源导航实现。

### 7.5 `shared/l10n/`

`app_en.arb` 是模板，`app_zh.arb` 提供中文对应项；二者当前各有 176 个 JSON 条目（包含 ARB 元数据）。`flutter gen-l10n` 生成抽象 `AppLocalizations` 和中英文实现。`l10n.dart` 为 BuildContext 增加 `context.t` 快捷访问。

`LocaleNotifier` 在 `en` 与 `zh` 之间切换。语言同样未持久化。生成文件应由 ARB 再生成，不应手工修改。

### 7.6 `shared/providers/`

- `settings_provider.dart`：装配 SettingsService、首次引导状态和 `ApiConfigNotifier`。保存配置时先写 Secure Storage，再更新 state，使 `llmClientProvider` 自动重建。
- `bookmark_provider.dart`：AsyncNotifier 在 build 时加载书签，并提供 toggle/remove 等操作；SQLite 写入成功后同步更新内存列表与 URL set。
- `theme_provider.dart`：持有当前 token 实例，是所有视觉组件的单一主题入口。

## 8. `features/wiki/`：Wiki 阅读系统

### 8.1 `wiki_browser_page.dart`

Wiki 页面配置了两个固定站点：PRTS Wiki 和 Warfarin 的 Endfield Wiki。`WikiBrowserPage` 创建一个双标签 `TabController`，并为每个站点分别保存 WebView controller、标题、URL、后退状态和前进状态。页面主体使用 IndexedStack 而不是可横滑的 TabBarView，所以切换站点不会销毁 WebView，也不会与网页自身的横向手势冲突。

每个 `_WikiTabView` 创建 `InAppWebView`，开启 JavaScript、DOM storage、缓存、缩放和透明背景。关键回调如下：

| 回调 | 作用 |
| --- | --- |
| `onWebViewCreated` | 把 controller 交给父页面保存 |
| `onLoadStart` | 清除上一轮主 frame 错误 |
| `onLoadStop` | 若暗色模式开启，重新注入暗色脚本 |
| `onTitleChanged` | 更新当前标签标题 |
| `onUpdateVisitedHistory` | 更新 URL，并异步查询前进/后退能力 |
| `onReceivedError` | 只处理主 frame，显示 DNS、超时或离线友好错误 |

页面右下角 `_ExpandableTray` 是一个可展开的纵向工具托盘，连接后退、前进、刷新、暗色、收藏、书签列表和转交 AI。`wiki_toolbar.dart` 中还保留了另一套横向 `WikiToolbar`，当前浏览页没有实例化它，属于旧 UI 组件。

### 8.2 暗色注入

`wiki_dark_mode.dart` 将 CSS 和 JavaScript 注入网页。脚本为页面增加固定 style id，以避免重复创建；开启时修改背景、文字、链接、表格等常见元素，关闭时移除 style。父页面会对两个已创建 controller 同步切换，并在后续页面加载完成后再次注入，解决网页导航导致 DOM 重建的问题。

这只是客户端显示转换，不修改远端页面，也不把网页写入知识库。网页结构变化可能导致选择器覆盖不完整，因此它是一种 best-effort 阅读功能。

### 8.3 书签

`bookmark_service.dart` 定义 `Bookmark` 数据模型和 `BookmarkService`。模型包括 UUID、标题、URL、站点和创建时间，并可在对象与 SQLite map 之间转换。Service 在 App 数据目录维护独立书签数据库，创建表、查询、插入、删除和按 URL 判断。

`BookmarkNotifier` 是 UI 的异步状态入口。浏览页切换收藏时根据当前标签计算 `site`，调用 notifier；`bookmark_page.dart` 监听 AsyncValue，分别显示加载、错误、空列表或书签项。点选书签后通过 Navigator 返回 Bookmark，浏览页据其站点切换标签并加载 URL。

### 8.4 Wiki 到 AI 的显式转交

用户点击转交后，页面执行：

```text
evaluateJavascript(window.getSelection().toString())
  -> 选择 Summary 或 Fact-check
  -> WikiAiContext(selectedText, pageTitle, pageUrl, siteLabel, target)
  -> push 新 AiChatPage
  -> 转换为带边界声明的用户 prompt
  -> Agent 独立调用 search_local_lore
```

`WikiAiContext.toPrompt()` 明确写入“not GameData evidence”。即使选区为空，也只发送页面信息，不虚构网页内容。URL 用于说明用户当时阅读的位置，不能出现在 GameData 证据字段中。

## 9. `features/ai/`：AI 交互表面

### 9.1 `ai_chat_page.dart`

`AiChatPage` 使用 TabController 管理 Summary、Fact-check、Role-play 三个标签。Summary 与 Fact-check 共用聊天页面构造模式，但监听不同的 Riverpod notifier；Role-play 交给独立 `RoleplayTab`。

页面接收可选 `initialWikiContext`。初始化后根据 target 选择标签，并在首帧后把格式化 context 作为用户消息提交。这样 Navigator push 不需要跨页面共享临时全局变量，也避免 context 在 build 中重复发送。

Summary 和 Fact-check 页面的主要状态包括消息列表、输入 controller、ScrollController、当前请求状态和最后失败输入。发送前检查空输入及 API 配置；请求期间按钮变为停止，取消后通过 notifier 的代次/取消机制忽略迟到结果；失败时可以重试原请求。

### 9.2 消息模型与显示

`ChatMessage` 不等同于 LLM 层的 `Message`。它是 UI 状态模型，包含本地 UUID、角色、正文、时间、ReAct steps、是否思考、错误、取消状态、事实核查 verdict 和 observation。发送时 notifier 会把适合模型的历史转换成 `core/llm/Message`，同时保留 UI 专用字段。

`chat_bubble.dart` 根据消息角色和状态组合以下细分组件：

- 用户与助手气泡布局。
- Markdown 正文渲染。
- 思考/工具步骤的可展开区域。
- Fact-check verdict badge。
- GameData-only 来源栏。
- 证据摘要与可展开证据条目。
- 取消、错误、空状态和重试入口。

`evidence_observation.dart` 是 observation 到 UI 的防火墙。它只接受 `Source Kind: GameData` 且具备必要 provenance 的 result block，解析 title、section、content type、source path、raw id、retrieval type、ranking reason、trust 和 excerpt。非 GameData 或字段不完整的 block 不会被画成官方证据卡。

覆盖度标签只表达检索类型：`scoped_story_evidence` 可以显示为 direct candidate，普通结果显示 retrieved context。它不把 retrieval score 翻译成“事实可信百分比”。

### 9.3 `roleplay_tab.dart`

Role-play 有 setup 和 conversation 两个主要界面。setup 接受角色名和可选场景，调用 `resolveCharacter`。唯一候选进入会话；多个 exact alias 候选要求用户消歧；未安装数据库或无候选均显示对应状态。

进入会话后顶部显示 canonical character、稳定 entity ID、GameData 范围和“生成对白不是官方台词”的声明。消息发送、取消、重试、继续旧会话、重新开始都通过 `RoleplayNotifier`。会话历史持久化为 JSON，而不是写入 GameData DB。

## 10. `core/llm/`：模型协议与网络实现

### 10.1 `llm_client.dart`

该文件定义与 provider 无关的模型协议：

- `MessageRole`：system、user、assistant、tool。
- `Message`：role、content 及可选 tool call 元数据，可序列化为 OpenAI-compatible JSON。
- `LLMConfig`：Chat base URL、API key 和 model，默认指向 DeepSeek-compatible 配置。
- `LLMException`：稳定错误文本、HTTP status 和原始 body。
- `ChatCompletionResult`：正文和 finish reason；`length` 被视为截断。
- `LLMClient`：普通 chat、带元数据的 chatCompletion 和 streaming 接口。

API Key 校验拒绝首尾空格、空白字符、控制/非 ASCII 字符和超长文本，目的是阻止用户误粘贴错误页面或整段日志。配置有效只要求 key 非空，URL 可达性和模型名称由真实请求验证。

### 10.2 `openai_client.dart`

`OpenAICompatibleClient` 用 `http.Client` POST 到 `$chatBaseUrl/chat/completions`，请求包含 model、messages、temperature、max_tokens、可选 stop 和 tools。当前 ReAct 实际使用文本格式工具协议，ToolRegistry 的 OpenAI schema 主要是抽象能力，并非 provider 原生 function calling 的唯一实现。

非 200 响应优先解析 `error.message` 或顶层 `message`，否则使用稳定 fallback。SocketException 和 TimeoutException 被转换为 LLMException。`chatStream` 读取 SSE `data:` 行、忽略 `[DONE]` 和坏 JSON，并把 delta content 交给回调；当前 ReAct 主循环使用非流式 `chatCompletion`，最终回答事件也以完整文本一次发出。

`llm_provider.dart` 监听 `apiConfigProvider` 创建 client，并在 provider dispose 时关闭底层 HTTP client。保存配置会触发 client 和依赖它的 Agent provider 重建。

## 11. `core/agent/`：自研 ReAct 编排器

### 11.1 工具抽象

`AgentTool` 规定 name、description、JSON Schema parameters 和异步 execute。`ToolExecutionResult` 把模型可见 observation 与开发日志分开。`ToolRegistry` 按工具名注册、查找和导出 OpenAI-compatible schema。

所有当前 Agent 都只注册 `SearchLocalLoreTool`。这是一条架构约束，而不仅是默认设置：没有 `search_wiki`、`search_book` 或任意网络搜索工具，模型无法通过工具绕开 GameData 信任策略。

### 11.2 `react_loop.dart` 状态机

ReActLoop 先把 Agent system prompt、工具清单和严格输出格式组合成 system message，然后附加历史与当前用户问题。每轮以低 temperature 请求一个步骤，并用 `Observation:` 作为 stop 序列，要求模型只生成一组 Thought/Action/Action Input 或 Final Answer。

完整循环如下：

```text
构造 prompt 和 loopMessages
  -> chatCompletion(maxTokens = stepMaxTokens)
  -> 若 finish_reason=length：立即报截断错误
  -> 解析 Thought / Action / Action Input / Final Answer
  -> Final Answer?
       -> 检查 minimumToolCalls
       -> 检查非空
       -> 来源/证据 finalize
       -> 发出 finalAnswerToken
  -> Action?
       -> 在 ToolRegistry 查找
       -> 宽松解析 JSON 或 key-value map
       -> 执行工具
       -> 保存并发出 observation
       -> 将 Observation 追加到 loopMessages
  -> 达到轮数仍未完成：执行受约束 fallback 或返回错误
```

解析器专门兼容真实 provider 常见偏差：Action 紧跟在句号后、Action 名后附带 metadata、Action Input JSON 后继续输出解释、用松散 map 而非严格 JSON。兼容只发生在协议层，不会允许调用未注册工具。

`minimumToolCalls` 防止模型跳过本地取证直接回答。Fact-check 和 Role-play 要求至少一次完成的工具调用；Fact-check 还使用 7 轮和 4096 step token 预算，以容纳 scope/entity 解析。截断、空 Final Answer、未知 action 和坏参数都会形成可见错误或下一轮 observation，而不是悄悄接受不完整回答。

循环维护 `_EvidenceSummary`，从 observation 识别实际 GameData result、无库、无结果、歧义和不支持来源声明。最终处理会阻止模型声称使用了 observation 中不存在的 Wiki/Book 等来源，并允许 Fact-check 的 transform 根据证据覆盖重写 verdict。

### 11.3 Debug 日志

`AgentLogger` 只在 `kDebugMode` 启用，记录 query、每轮原始模型输出、解析结果、工具参数、observation、fallback 和最终回答。Android 写入 app external files 下的 `agent_logs`，其他平台写 Documents，插件不可用时退到临时目录。

这保证 release 构建 no-op，但 debug 日志包含用户问题、模型思考和数据库原文，仍属于敏感数据。仓库中的 `logs/` 不由运行时自动作为知识源读取。

## 12. 三个 Agent 的工作原理

### 12.1 Summary Agent

`SummaryAgent` 组合 base prompt、统一知识库规则和 summary instructions，注册 `search_local_lore`，要求第一次使用 `search_mode=summary`。检索优先实体文档，再补相关剧情、结构化记录和 FTS fallback。若 exact alias 对应多个实体，Agent 必须展示候选并停止猜测。

`SummaryChatNotifier` 负责把用户消息加入 state、消费 ReAct stream、累计 steps/observation 并更新占位 assistant 消息。请求代次用于取消：取消会提高 generation，旧 Future 即使返回也不能覆盖新状态。

### 12.2 Fact-check Agent

事实核查不直接对整句做普通全文搜索。Prompt 要求：

1. 把输入拆成原子命题。
2. 分别查询剧情范围和实体，取得 `scope_id`、`entity_id`。
3. 用单个关系/状态/动作词调用 `search_mode=evidence`。
4. 对支持、反驳、歧义和缺失作区分。
5. 第一行输出严格 verdict marker。

`FactCheckAgent` 的 final transform 解析 marker，并结合实际 observations 校验。模型给出 supported/refuted 但没有 GameData record 时，结论会降级；歧义通常映射 uncertain，无覆盖映射 unavailable。普通复合查询无结果不能作为反证。

`FactCheckChatNotifier` 保留上一轮相关主张和证据 marker供追问使用，同时让新主张重新检索。UI 从最终 marker 提取 enum，不把英文 wire value直接当正文展示。

### 12.3 Role-play Agent

`RoleplayAgent.resolveCharacter()` 直接通过 `GameDataKnowledgeStore.findEntityCandidates` 做结构化解析，返回 resolved、ambiguous、notFound 或 unavailable。只有 resolved 才能创建 `_CharacterBoundSearchTool`；该包装器强制覆盖每次工具参数中的 `entity_id` 和 roleplay mode，模型不能在对话中改猜另一个角色。

首轮要求查询档案、语音、秘录、模组和剧情参与，后续按用户提到的任务或经历检索。用户场景被放入 session context，但明确不是 GameData。生成对白可以模仿语气，不能声称为官方台词；角色不知道或数据库未覆盖的事实不能由模型记忆补齐。

`RoleplayNotifier` 管理 setup、候选、当前角色、场景、消息、loading/error 和保存恢复。`RoleplaySessionStore` 把状态先写临时 JSON 再替换正式文件；坏 JSON 读取返回空，避免一次损坏阻止 App 启动。

## 13. `core/gamedata/`：知识库安装与 schema

### 13.1 release asset 安装

`GameDataInstaller` 默认目标文件是 `arklores_gamedata_zh.db`。URL 和压缩包 SHA-256 在编译/运行时通过 `ARKLORES_GAMEDATA_DB_URL` 与 `ARKLORES_GAMEDATA_DB_SHA256` 注入，App 本身不内置大型数据库。

下载更新流程：

```text
GET .db.gz
  -> 累积字节并报告 received/total
  -> 可选校验压缩数据 SHA-256
  -> gzip 解压
  -> 写入 .tmp
  -> 只读打开 SQLite
  -> 检查必需表、schema_version=2、关键计数 > 0
  -> 删除旧 DB
  -> rename .tmp 为正式 DB
```

验证失败时删除临时文件并保留旧数据库。严格说，替换阶段先 delete 再 rename，不是所有文件系统语义上的单次原子 replace，但验证失败不会破坏旧库。Android 优先使用 external app files，其他平台使用 application documents。

### 13.2 schema 2 表职责

| 表 | 职责 |
| --- | --- |
| `gamedata_manifest` | schema、语言、源仓库 commit、构建时间和记录计数 |
| `entities` | 稳定实体 ID、名称、类型、来源和别名 JSON |
| `entity_aliases` | alias 到 entity ID 的多对多映射、别名类型和置信度 |
| `entity_documents` | 按实体聚合的高质量长文档，优先服务梗概 |
| `story_lines` | 剧情文件解析后的逐行内容、speaker 和 line index |
| `story_scopes` | story ID 到 activity/main 等稳定范围的映射 |
| `normalized_records` | 从 JSON 表抽取的统一结构化文本记录 |
| `entity_relations` | 源实体、目标实体和关系类型；当前 App 查询利用有限 |
| `lore_chunks` | 统一检索片段，携带 entity/story/scope/provenance |
| `entity_documents_fts` | entity document 的 trigram FTS5 外部内容索引 |
| `lore_chunks_fts` | lore chunk 的 FTS5 外部内容索引 |

安装器把两个 FTS virtual table也列为必需项。常用过滤字段有普通索引：entity name、alias、record content type/entity、chunk source/content/entity/scope、document entity/type。

### 13.3 `GameDataKnowledgeStore`

KnowledgeStore 延迟解析数据库路径并缓存只读 sqflite connection。`isAvailable` 只确认文件存在；真正结构兼容性主要由安装器保障。公共能力有通用 `search()`、`findEntityCandidates()` 和关闭连接等。

`GameDataSearchResult` 统一返回 id、固定分值、retrieval type、source kind/type、内容分类、实体/剧情 ID、标题、章节、正文、source path、raw id、行号和 ranking reason。`GameDataEntityCandidate` 则表达消歧候选和 match type。

## 14. 检索算法与证据查询

### 14.1 Query plan

每次 search 先创建 `_GameDataQueryPlan`：规范空白、推断 content type、删除“剧情/梗概/档案”等意图词以获得实体查询、扩展“肉鸽/集成战略”“语音/charword”“秘录/story_review”等同义表达，并判断是否具有 story intent。

### 14.2 普通与摘要检索顺序

结果以 ID 去重，先进入 map 的高优先结果不会被低优先 fallback 替换。概括后的顺序是：

1. 实体名称和 alias 结构化查询。
2. 已解析 entity 的聚合文档。
3. Summary/Role-play 模式下的剧情上下文。
4. entity 绑定 chunk 和 normalized record。
5. entity document FTS 与 LIKE。
6. normalized record 多词 AND LIKE。
7. story-intent chunk。
8. lore chunk FTS 与 LIKE。
9. 指定 content type 的宽 fallback。

最后按预设 score 降序、标题升序，截取 `topK`（限制在 1 至 10）。score 是检索阶段优先级，不是概率，也不是事实真值。

### 14.3 实体消歧

候选查询对 canonical name exact、canonical alias exact、其他 alias exact、name LIKE、alias LIKE 分级。一个 alias 命中多个实体时，工具返回带 entity ID、实体类型、匹配别名、来源路径和 confidence 的候选块。Agent 应请求用户选择或携带明确 ID 重查。

### 14.4 Scoped story evidence

当 `search_mode=evidence` 同时带有效 scope ID 与 entity ID 时，检索进入专用路径：

1. 把 `scope_id` 拆成 scope type 和稳定 id。
2. 查询 entity 的 canonical name及别名。
3. 只选择 `source_type='game_story'` 且 scope 相等的 chunks。
4. 要求正文包含实体名之一，并对每个 claim term执行 AND 条件。
5. 最多取 200 个候选，在 Dart 中计算实体名和关系词的最短字符距离。
6. 优先返回距离更近、同句可能性更高的片段，再以 story/raw id稳定排序。

因此“活动 + 人名 + 死亡”不会只是三个词在任意全库文档中相遇，而是在已解析活动范围内寻找人物名与“死亡”的直接邻近文本。它仍叫 direct candidate，而不是自动判定事实；最终 supported/refuted 由 Agent 阅读正文后形成。

### 14.5 `SearchLocalLoreTool`

工具 schema 接收 query、top_k、content_type、entity_id、search_mode 和 scope_id。它先处理非法 evidence 参数，再做候选消歧或 KnowledgeStore search。结果格式包含 Retrieval Plan、每条结果的 provenance、trust 和截断 excerpt。

Observation 有总字符预算和单条 excerpt 预算。超过预算时省略剩余结果并注明数量，避免大数据库结果挤爆模型上下文。无库与有库无结果使用不同文本，使 ReAct 能区分“需要安装”和“当前库未覆盖”。

## 15. GameData 离线构建与发布流水线

### 15.1 `build_gamedata_database.dart`

构建器是桌面 Dart CLI，使用 `sqflite_common_ffi`，输入 Kengxxiao/ArknightsGameData 的 `zh_CN` 目录，输出未压缩 DB、manifest 和 build report。它先删除明确允许覆盖的输出目录、创建 schema、写入源仓库 commit，再按四阶段导入：

1. **Character profiles**：读取 `character_table.json` 和 `handbook_info_table.json`，建立 operator entity、canonical/生成 alias、基础档案 chunks、normalized records 和聚合 entity document。
2. **Character voices**：读取 charword 数据，将语音标题和正文绑定到 operator ID。
3. **Structured text tables**：遍历配置的 Excel JSON 表，从白名单文本 key中提取含中文内容，推断 raw ID、标题、parent 和内容分类，写 normalized record 与 chunk。
4. **Stories**：递归读取剧情 TXT，清理控制标签，解析 speaker/正文，写逐行 story_lines、story scope、normalized records 和较长 chunks。

稳定记录 ID 使用内容字段拼接后的 SHA-1，目的是同一源数据重复构建得到相同主键，而不是用于安全签名。`_collectTextSections` 只收集 `_textKeys` 白名单且包含中文字符的字符串，去 HTML 标签、规范空白并去重。这种规则降低无意义数值配置进入知识库的概率，但也意味着未列入白名单的新字段不会自动导入。

剧情 scope 根据 story path 推断：`activities/<id>` 映射 activity，其他路径使用首段作为 scope。故事类型进一步区分 main、activity、operator record、roguelike、sandbox 和 tutorial，写入 content category/subtype/type。

导入结束后执行两个 FTS external-content rebuild，重新 SQL COUNT 获取真实统计值，更新数据库内部 manifest，并生成外部 JSON：

- `gamedata_manifest.json`：schema、语言、release 文件名、源仓库/branch/commit 和计数。
- `gamedata_build_report.json`：构建状态、数据库路径和计数。

`--story-limit=N` 只用于 schema/smoke，不能代表完整剧情检索质量。

### 15.2 内容审计与 finalize

- `audit_arknights_gamedata_files.py`：遍历源仓库文件，统计 JSON 中文文本和文本文件内容，建议 category/relevance，输出 CSV/Markdown 审计资料。
- `inspect_arknights_gamedata_content.py`：快速查看顶层目录、剧情目录、Excel JSON 文本密度和 story table 覆盖，用于开发 importer 前的取样研究。
- `finalize_gamedata_assets.dart`：要求 DB、`.db.gz` 和 manifest 已存在，计算压缩/未压缩大小与 SHA-256，回写 manifest 和 report。它不负责 gzip，本步骤假定压缩已完成。
- `check_gamedata_retrieval.dart`：直接打开 finalized DB，执行固定 query、alias candidates 和 scoped evidence QA，检查结果类型、字段和期望命中。

### 15.3 分发闭环

```text
固定 GameData commit
 -> audit / inspect
 -> build schema 2 DB
 -> 完整 retrieval QA
 -> gzip
 -> finalize hashes/metadata
 -> GitHub Release asset
 -> App 构建时注入 URL + compressed SHA
 -> 用户下载、校验、安装
```

数据库不进入 APK，允许数据资产与 App 版本分开刷新；代价是首次使用 AI 前必须安装知识库，并且 release 需要长期维护 URL、hash 和 schema 兼容策略。

## 16. `core/rag/` 与 `core/wiki/` 历史模块

### 16.1 `rag/chunker.dart`

`Chunker` 是与模型无关的 Markdown/文本分块器。`Chunk` 保存 id、正文、标题、层级、来源和字符范围；`ChunkerConfig` 控制目标大小、overlap 和最小大小。算法识别 Markdown heading，将文本组织为 section，再按段落/字符预算切分，并给相邻 chunk 保留 overlap。当前 GameData builder 仍使用它处理长文本，所以 `core/rag` 不是完全死代码；被废止的是 embedding/vector 检索，而不是确定性 chunking。

### 16.2 `wiki_crawler.dart` 与 `wiki_provider.dart`

`MediaWikiCrawler` 封装 MediaWiki API：站点探测、页面列表/分类成员、页面内容和批量 crawl，输出 `WikiPage` 与 `CrawlProgress`。`wiki_models.dart` 定义 PRTS/Endfield 枚举、页面模型和进度模型；`wiki_provider.dart` 用 `CrawlNotifier` 管理 idle/running/completed/error、取消和进度比例。

当前任何 feature 页面都不监听 `crawlProvider`，Agent 也不导入它。因此它是运行时不可达的旧采集链，而 WebView 浏览不经过该 crawler。

### 16.3 `warfarin_crawler.dart`

Warfarin Wiki 使用 Remix 数据流而非标准 MediaWiki API。Crawler 请求页面/loader 数据，解析 indexed key 与嵌套值，提取 operator metadata、archive、voice、lore 和 dialogue，再格式化为 Markdown。测试主要验证 stream decoder 和 formatter，不验证当前站点在线协议。

### 16.4 `prts_utils.dart`

该文件包含 MediaWiki template 的括号深度解析、格式清洗、剧情控制标签移除和 operator Markdown 汇总。它能组合档案、招聘合同、天赋、技能、后勤、模组、悖论模拟、密录、信物和语音。当前 GameData builder不调用它；它只服务历史 PRTS 抓取/测试语境。

## 17. 设置、知识库、首次引导与 Materials

### 17.1 设置页

`settings_page.dart` 是 v0.9 重做重点。页面使用工业 page/section header，把偏好、知识与系统信息分区。`_PreferenceRow` 统一标签、说明和尾部控件；`_CompactSettingWidth` 根据可用宽度限制控件；`_SettingsActionTile` 负责可导航设置项；`_SystemFooter` 展示版本/系统信息。主题和语言使用紧凑选择控件，API 与知识库通过命名路由进入子页。

### 17.2 API 设置

`api_settings_page.dart` 编辑 Chat base URL、API key 和 model。Key 输入可切换显隐，保存前构造 `LLMConfig` 并做格式校验。成功后 `ApiConfigNotifier.save` 写 Secure Storage，再更新 provider。App 不测试 key 是否真的有权限，真实网络错误在首次请求时显示。

### 17.3 知识库页

`knowledge_base_page.dart` 监听 `gameDataInstallStatusProvider`，显示安装状态、字节数、source commit、构建时间和各类计数。用户下载时调用 installer、接收字节进度，结束后 invalidate status provider重新读取 manifest。无编译期 URL 时无法凭空发现 release；当前发布流程必须注入 URL。

### 17.4 首次引导

`onboarding_page.dart` 有 Welcome、API 配置、完成三个 PageView step。第二步禁止手势跳过表单流程，但提供显式稍后配置；顶部可切语言。完成或跳过调用 `markOnboardingDone`，再通知根 App 切换主页。主题没有在 onboarding 内配置。

### 17.5 Materials

`materials_page.dart` 只有暂停说明，没有文件选择、PDF/TXT parser、索引或数据库写入。它保留一级入口是产品信息架构选择，不应据此推断用户资料功能仍可用。

## 18. Android、iOS 与平台边界

### 18.1 Android

Android application ID/namespace 为 `com.arklores.arklores`，compileSdk 36，版本号来自 pubspec。Manifest声明 INTERNET 和 ACCESS_NETWORK_STATE，主 Activity 使用 Flutter embedding v2、singleTop、硬件加速和 adjustResize，并响应语言、字号、方向等 configuration change。

`MainActivity.kt` 只是 `FlutterActivity` 子类，业务完全在 Dart。`res/values` 与 `values-night` 定义 Flutter 启动/普通主题，mipmap 目录提供各密度 launcher icon。debug/profile manifest 是 Flutter 开发构建补充配置。

release build type 当前仍使用 debug signing config。因此“release-mode APK”只表示优化构建，不能等同于正式生产签名。Gradle plugin 8.2.2、Kotlin 1.9.24，wrapper 和本地 Flutter plugin loader共同构成构建链。

### 18.2 iOS

`AppDelegate.swift` 注册 Flutter plugins后交还父类。`Info.plist` 从 Flutter build variables取得版本与 bundle ID，支持 iPhone 竖屏及左右横屏、iPad 四方向，并启用文件共享和原地打开。Storyboard 和 xcassets 是 Flutter 默认启动界面与图标资源；Xcode project/workspace/scheme 管理编译、签名和测试目标。`RunnerTests.swift` 当前只有平台测试模板，不覆盖业务 Dart 逻辑。

## 19. `tools/setup.sh` 开发与安装向导

setup 脚本统一处理 Android/iOS 的环境检查、构建、卸载和安装。它支持交互模式与参数模式，默认 Android debug build+install，只有显式 `uninstall` 才删除设备 App 数据。

GameData 有三种来源：从源仓库现场构建、复用本地 `.db.gz`、使用远程 URL+SHA。Android 本地服务优先 `adb reverse tcp:8765`，否则检测局域网 IP；脚本启动 Python HTTP server、验证资产可访问并把 URL/SHA 作为 dart-define 注入。`--allow-unverified-gamedata` 只允许临时开发。

脚本也能检查/安装 Android SDK 组件、调用 Flutter build、adb 或 ideviceinstaller。`--dry-run` 只验证和显示参数，不代表真实构建、网络或设备安装通过。

## 20. 测试体系

| 测试文件 | 覆盖内容 |
| --- | --- |
| `agent_test.dart` | Wiki context、GameData 查询/消歧/evidence、安装保护、ReAct 容错、Fact-check、LLM key、Role-play 与会话存储 |
| `fact_check_widget_test.dart` | 窄屏 verdict/evidence、Summary 取消重试、Role-play 两状态、Wiki context 转交 |
| `evidence_observation_test.dart` | 多 result parser、必要 provenance、拒绝伪来源 |
| `settings_redesign_test.dart` | 主题 palette、360x800 中文、420x900 英文 1.6x 字号 |
| `bookmark_service_test.dart` | Bookmark ID、map round-trip、相等和站点标签 |
| `warfarin_crawler_test.dart` | Remix decoder、operator/lore/dialogue Markdown formatter |
| `live_fact_check_test.dart` | 最小 Chat、真实 scoped claim、无覆盖未来命题；需环境变量 opt-in |

自动测试大量使用临时 SQLite 和 `sqflite_common_ffi`，所以会出现切换 default factory 的 warning；当前不影响结果。测试强项是检索和 Agent 协议，缺口是 Android/iOS 真机 WebView、TalkBack/VoiceOver、完整长对话性能、真实 release 下载和正式签名。

## 21. v0.9 视觉实现专项

v0.9 从 `v0.8.0` 到当前 HEAD 的 28 文件差异约为 1419 行新增、368 行删除。核心新增是 `industrial_ui.dart` 和 `settings_redesign_test.dart`；`main.dart`、`app.dart`、主题 token、ThemeAwareCard 和 SettingsPage发生实质改造。AI、Wiki、Materials、API、Knowledge Base、Onboarding 和 Bookmark 页面在该范围内主要是适配全局透明背景，而非完整重写。

因此 0.9 的准确技术描述是“建立应用级设计系统并完成导航/设置主表面迁移”，而不是“每一个 feature 的内部组件都已经拆分重写”。这与项目方把 0.9 定义为开发完毕并不冲突，但 release notes应避免声称已完成源码未体现的全页面重构。

## 22. 安全、可靠性与已知债务

### 22.1 已建立的保护

- API key使用 OS Secure Storage，不进入普通设置文件。
- GameData 可校验压缩包 SHA，坏库验证失败时保留旧库。
- release 构建不启用 AgentLogger。
- Agent 只注册本地 GameData 工具，确定 verdict 受 observation 二次约束。
- Wiki context 带显式非证据声明。
- observation 和 excerpt 有上下文预算。
- 异步取消通过请求代次阻止迟到响应写回。

### 22.2 仍需记录的债务

- Materials、Knowledge Base 和 Wiki 错误覆盖层仍存在硬编码中文，未完全进入 ARB。
- `CitationCard` 的 Wiki 跳转 TODO 未接通。
- `app.dart` 有未被根 MaterialApp采用的重复 route generator。
- Wiki crawler/provider 是不可达历史链，增加维护和理解成本。
- `agent_provider.dart`、`gamedata_knowledge_store.dart`、`react_loop.dart` 和若干页面文件较长，职责拆分有限。
- analyzer 只使用默认 flutter_lints，尚未实现规划中的规则收紧。
- Theme 和 Locale不持久化。
- Streaming client存在，但当前 Agent UI并非逐 token流式输出。
- Android release仍用 debug certificate；iOS 正式签名和发布流程未验证。
- debug Agent 日志包含完整敏感上下文，缺少应用内清理/告知机制。

## 23. 文档体系与一致性审计

| 文档 | 当前职责与审计结论 |
| --- | --- |
| `implementation_plan.md` | 当前架构权威文档；0.9 部分仍按计划/验收语言书写 |
| `GAMEDATA_BUILD_PIPELINE.md` | taxonomy、schema、构建和 release asset 的统一数据契约 |
| `RETRIEVAL_QA.md` | 固定检索用例、失败规则、版本验证记录和已知限制 |
| `ANDROID_SETUP_GUIDE.md` | Android/asset 操作完整，但标题仍称适用于 v0.8.0 |
| 根 `CHANGELOG.md` | 用户变化与历史 release 技术元数据的统一记录 |
| 根 `CONTRIBUTING.md` | 分支、提交、安全和 PR 前检查的统一入口 |
| 根 `README.md` | v0.9 产品入口、release asset 和快速开始 |
| `CLAUDE.md` | 当前开发约束和命令基本准确 |

## 24. 端到端典型流程

### 24.1 新用户到第一次梗概

```text
启动 -> 读取 Secure Storage -> Onboarding
 -> 保存 Chat 配置/稍后配置 -> MainShell
 -> Settings/Knowledge Base -> 下载 .db.gz
 -> SHA + schema 校验 -> 安装 DB
 -> AI/Summary 输入实体 -> ReAct
 -> entity/alias/document/story 查询 -> Observation
 -> Chat API 整理梗概 -> 证据 parser -> 回答与证据卡
```

### 24.2 Wiki 选区事实核查

```text
Wiki 阅读 -> 选择网页文本 -> 工具托盘“发送到 AI”
 -> 选择 Fact-check -> WikiAiContext
 -> 新 AI 页面自动提交非证据上下文
 -> 分别解析 scope/entity -> scoped evidence
 -> GameData observation -> verdict transform
 -> 四态 badge + GameData 引用；Wiki URL不进入证据卡
```

### 24.3 角色扮演恢复

```text
输入角色名 -> alias candidates -> 唯一 entity_id/请求消歧
 -> 首轮 GameData memory检索 -> 生成对白 -> 原子 JSON 保存
 -> App 重启 -> RoleplaySessionStore load
 -> 恢复 canonical character、场景和历史
 -> 新一轮仍重新调用角色绑定 search tool
```

## 25. 结论

ArkLores 当前最有辨识度的技术价值不是 UI 主题或“接入了大模型”，而是把事实来源约束落实到了数据分发、SQLite schema、查询参数、工具注册、ReAct 门槛、verdict 后处理和证据 UI 多层。任何单层都不能独立保证真实性，但这些层共同降低了模型绕过证据直接作答的概率。

v0.9 在不改变上述业务核心的情况下建立了可继续扩展的双主题视觉基础，并已发布为
`v0.9.0` GitHub Release。发布 APK 是 release-mode 的 debug-certificate 验收包，不是正式
商店签名；硬编码、本地化和历史 crawler 继续作为已知技术债维护。

## 附录 A：`lib/` 逐文件职责索引

| 文件 | 直接职责 |
| --- | --- |
| `main.dart` | 启动 I/O、Provider override、MaterialApp、主题、本地化和根路由 |
| `app.dart` | 四页 MainShell、IndexedStack、底部导航和备用 route wrapper |
| `core/llm/llm_client.dart` | 模型消息、配置、结果、异常和 client接口 |
| `core/llm/openai_client.dart` | OpenAI-compatible HTTP/SSE 实现 |
| `core/llm/llm_provider.dart` | 从 API 配置装配并释放 client |
| `core/agent/agent_prompts.dart` | 基础信任规则与三 Agent prompt |
| `core/agent/react_loop.dart` | ReAct 状态机、解析容错、工具循环和答案约束 |
| `core/agent/agent_provider.dart` | 三工作流 UI 状态、notifier、取消重试和 session协调 |
| `core/agent/summary_agent.dart` | Summary prompt、tool registry与 loop配置 |
| `core/agent/fact_check_agent.dart` | Fact-check loop和 verdict证据校验 |
| `core/agent/roleplay_agent.dart` | 角色解析、角色绑定工具和 role-play loop |
| `core/agent/roleplay_session_store.dart` | Role-play JSON 原子保存、读取和清除 |
| `core/agent/agent_logger.dart` | debug-only ReAct 会话日志 |
| `core/agent/tools/agent_tool.dart` | 工具与结果抽象 |
| `core/agent/tools/tool_registry.dart` | 工具注册和查找 |
| `core/agent/tools/search_local_lore.dart` | GameData 查询参数验证与 observation格式化 |
| `core/gamedata/gamedata_installer.dart` | asset下载、hash、解压、schema校验和替换 |
| `core/gamedata/gamedata_provider.dart` | installer和安装状态 provider |
| `core/gamedata/gamedata_knowledge_store.dart` | SQLite 多阶段检索、消歧和 evidence排序 |
| `core/rag/chunker.dart` | 确定性文本/Markdown 分块 |
| `core/wiki/wiki_models.dart` | Wiki site/page/progress模型 |
| `core/wiki/wiki_crawler.dart` | 历史 MediaWiki API crawler |
| `core/wiki/wiki_provider.dart` | 历史 crawl Riverpod状态 |
| `core/wiki/warfarin_crawler.dart` | Warfarin Remix解析和 Markdown格式化 |
| `core/wiki/prts_utils.dart` | PRTS template/剧情清洗和 operator文档汇总 |
| `features/wiki/wiki_browser_page.dart` | 双站 WebView与工具托盘 |
| `features/wiki/wiki_dark_mode.dart` | 网页暗色 CSS/JS注入 |
| `features/wiki/wiki_toolbar.dart` | 当前未使用的横向 Wiki工具栏 |
| `features/wiki/bookmark_service.dart` | Bookmark模型和 SQLite CRUD |
| `features/wiki/bookmark_page.dart` | 书签列表、空态和返回选择 |
| `features/ai/ai_chat_page.dart` | AI三标签和 Summary/Fact-check输入流程 |
| `features/ai/wiki_ai_context.dart` | Wiki上下文边界模型与 prompt格式 |
| `features/ai/evidence_observation.dart` | GameData observation严格解析 |
| `features/ai/widgets/chat_bubble.dart` | 消息、Markdown、verdict、步骤和证据 UI |
| `features/ai/widgets/roleplay_tab.dart` | 角色 setup、消歧和对话 UI |
| `features/settings/settings_page.dart` | v0.9响应式设置主页 |
| `features/settings/api_settings_page.dart` | Chat API配置表单 |
| `features/settings/knowledge_base_page.dart` | GameData状态、下载和进度 |
| `features/settings/onboarding_page.dart` | 三步首次引导 |
| `features/settings/settings_service.dart` | Secure Storage配置/引导标记 |
| `features/materials/materials_page.dart` | 用户资料功能暂停说明 |
| `shared/theme/app_theme.dart` | 主题 token接口 |
| `shared/theme/ark_theme_tokens.dart` | Ark深色主题实现 |
| `shared/theme/endfield_theme_tokens.dart` | Endfield亮色主题实现 |
| `shared/providers/theme_provider.dart` | 主题状态与切换 |
| `shared/providers/settings_provider.dart` | 设置对象装配和 API config状态 |
| `shared/providers/bookmark_provider.dart` | 书签 AsyncNotifier |
| `shared/l10n/l10n.dart` | `context.t`扩展 |
| `shared/l10n/locale_provider.dart` | 中英文 locale状态 |
| `shared/l10n/app_en.arb` / `app_zh.arb` | 本地化源资源 |
| `shared/l10n/generated/*` | Flutter gen-l10n生成实现 |
| `shared/widgets/industrial_ui.dart` | 背景、页头、分区头和 painter |
| `shared/widgets/theme_aware_card.dart` | 切角主题表面 |
| `shared/widgets/citation_card.dart` | 历史 Wiki/Book折叠引用卡 |

## 附录 B：主要依赖与用途

| 包 | 用途 |
| --- | --- |
| `flutter_riverpod` | 依赖装配和响应式状态管理 |
| `flutter_inappwebview` | 双 Wiki浏览、JS selection和暗色注入 |
| `sqflite` | App端 GameData与书签 SQLite |
| `sqflite_common_ffi` | 桌面构建工具和测试 SQLite |
| `http` | Chat API与 GameData下载 |
| `flutter_secure_storage` | API key与 onboarding状态 |
| `path_provider` / `path` | 平台目录和路径拼接 |
| `crypto` | SHA-256 asset校验和构建元数据 |
| `uuid` | UI消息、书签等本地 ID |
| `flutter_markdown` | AI回答 Markdown渲染 |
| `google_fonts` | 双主题字体 |
| `intl` / `flutter_localizations` | 中英本地化 |

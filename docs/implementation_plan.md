# ArkLores — 明日方舟剧情助手 · 架构设计文档

> 一款为《明日方舟》剧情爱好者打造的 AI 增强阅读工具。开源、无服务器、用户自带 API Key。

---

## 项目概览

| 项目 | 决策 |
|------|------|
| **App 名称** | **ArkLores**（英文，与 Arknights 读音相近，一语双关） |
| 目标平台 | Android + iOS（Flutter） |
| 最低系统版本 | Android 8.0（API 26）/ iOS 14 |
| AI 接入 | 用户自带 API Key，OpenAI 兼容接口 |
| 数据存储 | 本地 sqlite-vec（向量）+ SQLite（结构化） |
| 向量方案 | sqlite-vec FFI（优先）；不可用时回退纯 Dart cosine similarity |
| Agent 实现 | 纯 Dart 手写 ReAct Loop |
| 状态管理 | Riverpod |
| 开源协议 | GPL-3.0 + README 道义声明"非商业" |
| 作者署名 | `hhikr`（GitHub ID，写入 AUTHORS 文件和 README） |
| 视觉主题 | **双主题可切换**：① 明日方舟·战术档案风 ② 终末地·全息投影风 |
| 知识来源 | PRTS Wiki + 终末地 Wiki + 书籍文件（用户导入 PDF/TXT） |
| 迭代路线 | v0.1: Wiki/AI 核心导航；v0.2: Agent 与引用卡片；v0.3: 书籍导入与资料 Tab；v0.4: 设置与知识库管理 |

---

## 整体架构

```
┌────────────────────────────────────────────────────────┐
│                   Flutter UI Layer                      │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌───────────┐  │
│  │ Wiki 浏览  │ │  AI 对话  │ │   资料     │ │   设置    │  │
│  │ WebView    │ │ 三模式切换 │ │ 书籍导入   │ │ API Key   │  │
│  │ +书签/深色 │ │ +引用卡片  │ │ 多文件管理 │ │ 知识库管理│  │
│  └─────┬────┘ └─────┬────┘ └─────┬────┘ └────┬───┘  │
│       │  智能浮动按钮联动   │           │            │  │
└───────┼───────────────────────┼───────────┼────────────┘
         │                      │           │
┌────────▼───────────────────▼─────────▼──────────────────┐
│                 Application Layer (Dart)                │
│  │  │ 事实核查   │ │ 梗概生成   │ │  角色扮演    │  │  │
│  │  │  Agent    │ │  Agent    │ │   Agent     │  │  │
│  │  └────────────┘ └────────────┘ └──────────────┘  │  │
│  │           ↓ Tool Calls                            │  │
│  │  ┌────────────────────────────────────────────┐  │  │
│  │  │              Tool Registry                  │  │  │
│  │  │  search_wiki | get_character | cite_source │  │  │
│  │  │  get_timeline | get_related_events         │  │  │
│  │  └────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────────────┬───────────────────────────┘
                             │
         ┌───────────────────┼──────────────────┐
         ▼                   ▼                  ▼
┌──────────────┐   ┌──────────────────────────┐  ┌──────────────┐
│ sqlite-vec   │   │   内容摄取层               │  │  LLM Client  │
│ 向量索引      │   │  ┌──────────────────────┐  │  │  OpenAI 兼容 │
│ + SQLite     │   │  │ Wiki 爬取器           │  │  │  Embedding + │
│ 结构化缓存    │   │  │ MediaWiki API        │  │  │  Chat API    │
└──────────────┘   │  │ (prts + warfarin)    │  │  └──────────────┘
                   │  ├──────────────────────┤  │
                   │  │ 书籍导入器            │  │
                   │  │ PDF/TXT 文件导入      │  │
                   │  │ → 文本提取 → 分块     │  │
                   │  └──────────────────────┘  │
                   └──────────────────────────┘
```

---

## 功能模块详细设计

### 1. Wiki 浏览模块

**技术**：`flutter_inappwebview` 包

**功能清单**：
- 底部标签页：PRTS Wiki / 终末地 Wiki
- 自定义顶部工具栏：前进 / 后退 / 书签 / 日间-夜间切换 / 刷新
- **智能浮动按钮**：长按选中文字后浮出快捷菜单
  - 「问 AI」→ 将选中文字 + 当前页面 URL 传入当前 AI 模式
  - 「添加书签」→ 保存段落到本地书签库
- 书签管理页：列表展示，点击跳回对应 Wiki 页面

**深色/日间模式**：注入 CSS 覆盖实现（无需等待系统主题）

---

### 2. AI 对话模块

**界面结构**：
```
┌──────────────────────────────────────────────┐
│  [事实核查]  [梗概生成]  [角色扮演]  ← 顶部Tab │
├──────────────────────────────────────────────┤
│  对话气泡区域（支持 Markdown 渲染）             │
│  带下划线的引用 → 点击展开引用卡片              │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │ 引用卡片（展开态）                       │  │
│  │ 原文段落...                             │  │
│  │ 来源：PRTS Wiki · 龙门主线第三章        │  │
│  │ [在 Wiki 中查看 →]                     │  │
│  └────────────────────────────────────────┘  │
├──────────────────────────────────────────────┤
│  [输入框]                        [发送]       │
└──────────────────────────────────────────────┘
```

#### 2.1 事实核查 Agent

- **输入**：用户输入一个关于剧情的说法
- **多轮**：支持追问；检测到话题切换时自动开新对话
- **Workflow**：
  ```
  用户输入
     → 意图分析（是否追问同一话题？）
     → search_wiki(claim_keywords) × 3~5 次
     → LLM 综合判断：真 / 假 / 存疑 / 无法确认
     → 输出结论 + 引用证据（带下划线可展开）
  ```

#### 2.2 梗概生成 Agent

- **输入**：人物名 / 事件名 / 虚构国家/组织名
- **Workflow**：
  ```
  用户输入
     → 实体识别 + 分类（人物/事件/地点/组织）
     → 多轮 search_wiki（主条目 + 关联条目）
     → 层级摘要：时间线整合 → 重要节点标注
     → 输出 Markdown 格式梗概 + 引用列表
  ```
- **输出格式**：段落标题 + 正文 + 引用脚注（可点击展开）

#### 2.3 角色扮演 Agent

- **选角流程**：
  1. 输入框输入角色名 → 模糊匹配本地索引 → 展示建议列表
  2. 确认后展示**角色信息卡**（性格、身份、相关剧情摘要，来自 Wiki）
  3. 可选填写**场景描述**（如"当前场景是利卡第四章剧情结束后"）
  4. 开始对话

- **System Prompt 构建**：
  ```
  [角色 Wiki 信息] + [场景描述] + [说话风格指引]
  → 检索该角色相关剧情段落作为 RAG 上下文
  → 每轮对话都携带完整历史（多轮）
  ```
- **多轮对话**：保留完整对话历史，支持存档/重新开始

---

### 3. 资料模块

**入口**：底部导航第三个 Tab（资料）

**功能清单**：
- **书籍列表**：展示已导入的所有书籍文件，显示名称 / 块数 / 导入时间
- **导入按钮**：调用文件选择器选取 PDF 或 TXT，支持多选
- **导入进度**：导入中显示进度条（提取→分块→Embedding）
- **显示名编辑**：点击书籍条目可编辑显示名称（如将「大地巡旅.pdf」改为「大地巡旅·官方设定集」）
- **删除书籍**：滑动删除，同步清除该文件对应的所有向量
- **全局警示卡片**：资料页顶部常驻展示：

  > ⚠️ **资料内容属用户导入，可能包含非官方解读、翻译误差或个人总结。AI 将小心引用并以 Wiki 内容为优先参考。**

---

### 4. 知识库（RAG 引擎）

知识库支持两类内容来源，经统一管道处理后存入同一向量库，Agent 检索时透明感知来源类型。

#### 来源一：Wiki 在线爬取

```
MediaWiki API (api.php)
  → 批量拉取页面 Wikitext/HTML
  → 按标题层级切块（Chunk: ~500 Token，50 Token 重叠）
  → 调用 Embedding API（用户 API Key）
  → 存入 sqlite-vec（source_type = 'wiki'）
```

#### 来源二：书籍文件导入（大地巡旅等）

```
用户通过文件选择器选取 PDF 或 TXT 文件
  → PDF：使用 syncfusion_flutter_pdf 提取纯文本
  → TXT：直接读取
  → 按段落/固定窗口切块（~500 Token，50 Token 重叠）
  → 调用 Embedding API
  → 存入 sqlite-vec（source_type = 'book'，file_name 记录书名）
```

> [!NOTE]
> 书籍文件仅存储提取后的纯文本块，不保留原始 PDF。引用卡片展示时来源显示为「书籍·[文件名]」。

#### 索引策略

| 操作 | 触发方式 |
|------|----------|
| 首次建立 | 用户首次配置 API Key 后引导建立（仅 Wiki） |
| 增量更新 Wiki | 常驻「更新知识库」按钮，可选 PRTS / 终末地 / 两者 |
| 导入书籍 | 知识库管理页「导入书籍」按钮，选择文件后自动索引 |
| 删除书籍 | 知识库管理页列表中删除，同步清除对应向量 |

#### sqlite-vec Schema（草案）

```sql
CREATE TABLE chunks (
  id          TEXT PRIMARY KEY,  -- UUID
  source_type TEXT NOT NULL,     -- 'wiki' | 'book'
  -- Wiki 来源字段
  source_url  TEXT,              -- 原始 Wiki 页面 URL（wiki 类型）
  wiki        TEXT,              -- 'prts' | 'warfarin'（wiki 类型）
  -- 书籍来源字段
  book_id     TEXT,              -- 关联 books.id（book 类型）
  -- 通用字段
  page_title  TEXT,              -- Wiki 页面标题 或 书籍章节标题
  section     TEXT,              -- 所属小节标题
  content     TEXT NOT NULL,     -- 原文内容
  updated_at  INTEGER            -- Unix timestamp
);

CREATE VIRTUAL TABLE chunk_embeddings USING vec0(
  chunk_id TEXT PRIMARY KEY,
  embedding FLOAT[1536]          -- text-embedding-3-small 维度
);

-- 书籍文件元数据表
CREATE TABLE books (
  id           TEXT PRIMARY KEY,
  file_name    TEXT NOT NULL,     -- 原始文件名
  display_name TEXT,             -- 用户可编辑的显示名称
  chunk_count  INTEGER,
  imported_at  INTEGER
);
```

---

### 5. AI 资料可信度策略

> 用户导入的书籍内容来源不稳定，可能包含翻译误差、非官方解读或进度要求。AI 必须对其审慎对待。

这不是“不用书籍内容”，而是“使用但标注并警醒”。具体实现如下：

#### System Prompt 插入（每个 Agent 均注入）

```
下面提供的检索结果包含两类来源：
- [Wiki] 来自 PRTS Wiki 或终末地 Wiki（官方社区维护，较可信）
- [Book] 来自用户导入的书籍资料（可能包含非官方解读或翻译误差）

引用规则：
1. 当 [Wiki] 和 [Book] 内容冲突时，优先采信 [Wiki]
2. 引用 [Book] 内容时，必须明确标注为「来自书籍资料」
3. 如果 [Book] 内容无法被 [Wiki] 佐证，应在输出中说明“此信息仅来自用户导入资料，建议自行核实”
4. 不得将 [Book] 来源的内容以确定语气表述为官方设定
```

#### 引用卡片视觉区分

| 来源类型 | 卡片标识 | 颜色 |
|----------|----------|------|
| PRTS Wiki | 🌐 Wiki · PRTS | 主题强调色 |
| 终末地 Wiki | 🌐 Wiki · Endfield | 主题强调色 |
| 书籍资料 | 📚 资料 · [显示名] | 琥珀金/棕色，区分于 Wiki |

---

### 6. LLM 客户端层

**设计原则**：OpenAI 兼容接口，用户自填：
- Base URL（支持中转/国内 API）
- API Key
- 模型名（Chat + Embedding 分开指定）

**抽象接口**（Dart）：
```dart
abstract class LLMClient {
  Future<String> chat(List<Message> messages, {List<Tool>? tools});
  Future<List<double>> embed(String text);
}

class OpenAICompatibleClient implements LLMClient { ... }
```

---

### 7. 视觉设计系统（双主题）

用户可在设置页切换两套完整主题，切换即时生效（无需重启）。两套主题共用组件树，仅替换 `AppTheme` Token 层。

---

#### 主题 A — 明日方舟·战术档案风（ArkTheme）

> 以赛博朋克与战术工业风（Tactical/Industrial）为核心。扁平化模块切割、大量几何线条与装饰性功能区块、高度冷色调，整体呈现高度秩序化的「机密档案」感。

**色彩系统**：
```
背景主色:    #0B0D10（近纯黑，带极浅蓝偏）
背景次色:    #13181F（深石板灰蓝）
面板/卡片:   #1A2233（偏蓝深灰）
主强调色:    #4A90D9（冷钢蓝，明日方舟 UI 主蓝）
次强调色:    #A8C8E8（淡冰蓝，文字高亮）
警告/标记:   #D4A843（琥珀金，重要标注）
危险/错误:   #C0392B（深红）
文字主色:    #E2E8F0（浅冷白）
文字次色:    #6B7F99（灰蓝）
边框/分割线: #1E2D40（极深蓝灰）
扫光/强调线: #5BA3E0（亮蓝，用于动态效果）
```

**设计元素**：
- **切角卡片**（Chamfer Corner）：卡片右上角 8~12px 斜切，带 1px 冷蓝描边
- **装饰线框**：标题区左侧 2px 亮蓝竖线 + 右上角折角装饰
- **模块化分割**：大量水平/垂直细线将界面切分为功能区块
- **扁平图标**：线框风格（stroke-only），无填充
- **字体**：`Rajdhani`（英文标题/数字，科技感）+ `Noto Sans SC`（中文正文）
- **微动态**：
  - 按钮按下时：水平扫光效果（从左到右 150ms）
  - 卡片展开：高度 clip 动画 + 左侧竖线延伸
  - 页面切换：横向滑入（模拟档案翻页）
  - Loading：横向扫描线动画（雷达扫描感）

---

#### 主题 B — 终末地·全息投影风（EndfieldTheme）

> 在工业风基础上演进为未来科幻与空间投影（Spatial/Diegetic UI）。强调轻量化与透明度，运用大量悬浮三维全息质感元素和微观动态线框，减少色块遮挡，贴合宏大荒凉的异星探索题材。

**色彩系统**：
```
背景主色:    #050810（极深近黑，带微蓝紫）
背景次色:    #0C1020（深宇宙蓝）
面板/卡片:   rgba(16,24,48,0.72)（半透明深蓝，磨砂玻璃）
主强调色:    #00C8FF（全息青，明亮霓虹蓝）
次强调色:    #7B61FF（幽蓝紫，辅助高亮）
警告/标记:   #FFB800（暖琥珀，异星地表色）
危险/错误:   #FF4D6A（热红，告警）
文字主色:    #C8E0F0（冷蓝白）
文字次色:    #4A6080（暗蓝灰）
线框/网格:   rgba(0,200,255,0.15)（极浅全息青，用于背景网格）
发光边缘:    #00C8FF（用于卡片边框 glow 效果）
```

**设计元素**：
- **全息卡片**：背景半透明（BackdropFilter blur 16px）+ 0.5px 全息青描边 + 边缘发光（box-shadow: 0 0 12px #00C8FF40）
- **动态线框网格**：背景注入极浅六边形/矩形网格，缓慢漂移动画
- **悬浮感**：卡片带轻微 Y 轴位移动画（hover 上浮 4px）
- **三维感**：标题区使用透视渐变（顶部亮 → 底部消隐）模拟投影面
- **字体**：`Exo 2`（英文标题，几何未来感）+ `Noto Sans SC`（中文正文）
- **微动态**：
  - 卡片出现：从下方淡入 + 模糊消散（fade + unblur 200ms）
  - 按钮：轮廓脉冲发光（pulse glow，1.5s 循环）
  - 页面切换：Z 轴推进（scale 0.95→1.00，营造纵深感）
  - Loading：旋转全息环 + 中心粒子扩散
  - 背景：线框网格低速漂移（30s/周期，subtlety 优先）

---

#### 主题切换实现

```dart
// lib/shared/theme/app_theme.dart
abstract class AppThemeTokens {
  Color get bgPrimary;
  Color get bgSecondary;
  Color get cardSurface;
  Color get accentPrimary;
  // ... 其余 Token
  TextStyle get titleFont;
  BorderRadius get cardRadius;
  List<BoxShadow> get cardShadow;
}

class ArkThemeTokens implements AppThemeTokens { ... }      // 主题 A
class EndfieldThemeTokens implements AppThemeTokens { ... } // 主题 B

// Riverpod Provider
final themeProvider = StateNotifierProvider<ThemeNotifier, AppThemeTokens>(
  (ref) => ThemeNotifier(),
);
```

所有 Widget 通过 `ref.watch(themeProvider)` 读取 Token，切换主题时整棵树自动重建。

---

## 项目目录结构（Flutter）

```
arklores/
├── lib/
│   ├── main.dart
│   ├── app.dart                    # 路由 & 主题
│   ├── core/
│   │   ├── llm/
│   │   │   ├── llm_client.dart     # 抽象接口
│   │   │   └── openai_client.dart  # OpenAI 兼容实现
│   │   ├── rag/
│   │   │   ├── vector_store.dart   # sqlite-vec 封装
│   │   │   ├── chunker.dart        # 文本分块
│   │   │   └── embedder.dart       # Embedding 调用
│   │   ├── wiki/
│   │   │   ├── wiki_crawler.dart   # MediaWiki API 爬取
│   │   │   └── wiki_models.dart
│   │   └── agent/
│   │       ├── react_loop.dart     # 通用 ReAct 执行器
│   │       ├── tools/
│   │       │   ├── search_wiki.dart
│   │       │   ├── get_character.dart
│   │       │   └── cite_source.dart
│   │       ├── fact_check_agent.dart
│   │       ├── summary_agent.dart
│   │       └── roleplay_agent.dart
│   ├── features/
│   │   ├── wiki/
│   │   │   ├── wiki_browser_page.dart
│   │   │   └── bookmark_page.dart
│   │   ├── ai/
│   │   │   ├── ai_chat_page.dart
│   │   │   ├── fact_check/
│   │   │   ├── summary/
│   │   │   └── roleplay/
│   │   │       ├── character_search.dart
│   │   │       ├── character_card.dart
│   │   │       └── roleplay_chat.dart
│   │   ├── materials/                   # 资料 Tab
│   │   │   ├── materials_page.dart        # 书籍列表 + 导入入口
│   │   │   ├── book_import_sheet.dart     # 导入进度底部弹窗
│   │   │   └── book_list_item.dart        # 单本书籍条目组件
│   │   └── settings/
│   │       ├── settings_page.dart
│   │       └── knowledge_base_page.dart   # Wiki 知识库管理（准确性设置）
│   └── shared/
│       ├── theme/
│       │   ├── app_theme.dart           # 抽象 Token 接口
│       │   ├── ark_theme_tokens.dart    # 主题A：战术档案风
│       │   └── endfield_theme_tokens.dart # 主题B：全息投影风
│       ├── widgets/
│       │   ├── citation_card.dart       # 可展开引用卡片
│       │   ├── floating_action.dart
│       │   └── theme_aware_card.dart    # 自适应主题的基础卡片组件
│       └── providers/
│           ├── settings_provider.dart
│           ├── theme_provider.dart      # 主题切换状态
│           └── chat_provider.dart
├── android/
├── ios/
└── pubspec.yaml
```

---

## 关键依赖（pubspec.yaml）

```yaml
dependencies:
  flutter_inappwebview: ^6.x          # WebView
  flutter_riverpod: ^2.x              # 状态管理
  sqflite: ^2.x                       # SQLite
  sqlite_vec: ^0.1.x                  # 向量搜索（FFI 绑定，优先）
  http: ^1.x                          # HTTP 客户端
  flutter_markdown: ^0.x              # Markdown 渲染
  flutter_secure_storage: ^9.x        # API Key 安全存储
  google_fonts: ^6.x                  # Rajdhani / Exo2 / Noto Sans SC
  file_picker: ^8.x                   # 书籍文件选择（PDF/TXT）
  syncfusion_flutter_pdf: ^26.x       # PDF 文本提取（免费社区版）
  path_provider: ^2.x                 # 本地文件路径
  uuid: ^4.x                          # Chunk UUID 生成
```

> [!WARNING]
> `sqlite_vec` 的 Flutter 原生绑定目前处于早期阶段，需在 v0.3 优先验证 iOS/Android FFI 兼容性。不可用时回退为纯 Dart cosine similarity 实现（性能略低但零依赖，可作为永久备选）。

> [!NOTE]
> `syncfusion_flutter_pdf` 社区版对非商业开源项目免费，符合本项目定位。如遇许可证问题可替换为 `pdfx`（纯 Dart，但文字提取能力较弱）。

---

## 迭代计划（详细版）

> 每个版本均为一个可独立运行的里程碑，优先保证核心链路可用，再逐层叠加功能。

---

### v0.1 — 项目骨架与设计系统
**目标**：能跑起来的空壳 App，所有视觉 Token 到位，主题切换可用。

| 交付内容 | 说明 |
|----------|------|
| Flutter 项目初始化 | Android + iOS 双平台配置，目录结构搭建 |
| 双主题 Token 实现 | `ArkThemeTokens` + `EndfieldThemeTokens`，设置中可切换 |
| **底部导航四 Tab** | **Wiki / AI / 资料 / 设置**，空页面占位 |
| 字体 & 基础组件 | Rajdhani/Exo2/Noto Sans SC 载入，ThemeAwareCard 组件 |
| 主题切换动画 | 切换时全屏 fade 过渡（300ms） |

**估时**：1 周  
**验收标准**：双主题可切换，页面无报错，在 Android 模拟器上运行。

---

### v0.2 — Wiki 浏览器
**目标**：能正常浏览两个 Wiki 站，基础阅读工具就位。

| 交付内容 | 说明 |
|----------|------|
| 双站 WebView | PRTS Wiki + 终末地 Wiki，底部 Tab 切换 |
| 自定义工具栏 | 前进/后退/刷新/书签/夜间模式，沉浸感设计 |
| Wiki 夜间模式 | 注入 CSS 实现，与 App 主题联动 |
| 书签系统 | 保存页面 URL + 标题 + 时间戳，本地 SQLite 存储 |
| 书签管理页 | 列表展示，支持删除，点击跳回 |

**估时**：1.5 周  
**风险**：PRTS Wiki 部分页面有 JavaScript 依赖，需测试 WebView 兼容性。  
**验收标准**：两站可正常浏览，书签存取正常，深色注入不破坏页面布局。

---

### v0.3 — 基础设施：LLM + 知识库
**目标**：跑通从 Wiki 爬取 → Embedding → sqlite-vec 的完整数据链路。

| 交付内容 | 说明 |
|----------|------|
| 设置页：API Key 配置 | Base URL / API Key / Chat 模型 / Embedding 模型，`flutter_secure_storage` 加密存储 |
| LLM 客户端 | `OpenAICompatibleClient` 实现，支持 Chat + Embedding |
| MediaWiki 爬取器 | 调用 `api.php` 批量拉取页面内容，支持 PRTS + 终末地 |
| 文本分块器 | ~500 Token 窗口，50 Token 重叠，按标题层级切分 |
| sqlite-vec 集成 | 验证 FFI 可行性，向量存取封装（备选：纯 Dart cosine similarity）|
| Wiki 知识库管理页 | 显示索引状态、页面数、向量数，「更新 Wiki」按钮 |
| **资料 Tab 功能** | 书籍列表、PDF/TXT 导入、进度展示、显示名编辑、删除 |
| **AI 信任策略实现** | Prompt 插入参考第 5 节，引用卡片颜色区分 Wiki/书籍 |
| 首次引导流程 | 未配置 API Key 时，引导用户完成配置 + 首次 Wiki 索引建立 |

**估时**：2 周  
**风险**：sqlite-vec Flutter FFI 绑定不稳定，需预留备选方案时间。  
**验收标准**：能将 100 个 Wiki 页面成功向量化入库，能执行语义搜索并返回结果。

---

### v0.4 — 梗概生成 Agent（首个 AI 功能）
**目标**：用户输入人物/事件/国家名，能得到有引用来源的剧情梗概。

| 交付内容 | 说明 |
|----------|------|
| ReAct Loop 核心 | 通用 Agent 执行器，支持 Tool 调用和多轮思考 |
| Tool：`search_wiki` | 语义检索 sqlite-vec，返回 Top-K 段落 |
| Tool：`cite_source` | 根据 chunk_id 返回原文 + 来源 URL |
| 梗概生成 Workflow | 实体分类 → 多轮检索 → 层级摘要 → Markdown 格式输出 |
| AI 对话界面骨架 | 三模式顶部 Tab，气泡消息列表，Markdown 渲染，流式输出 |
| 引用卡片 UI | 带下划线引用 → 点击展开卡片 → 「在 Wiki 中查看」按钮 |

**估时**：2 周  
**风险**：中文实体识别准确率依赖 LLM 能力，复杂角色（如涉及多线剧情的角色）梗概质量需要调优 Prompt。  
**验收标准**：输入「凯尔希」「龙门」「第二次卡兹戴尔战役」能得到结构完整、有出处的梗概。

---

### v0.5 — 事实核查 Agent
**目标**：用户输入一个剧情说法，得到「真/假/存疑/无法确认」的判断和依据。

| 交付内容 | 说明 |
|----------|------|
| 事实核查 Workflow | 关键词提取 → 多次检索 → 证据汇总 → LLM 综合判断 |
| 话题切换检测 | 利用 LLM 判断新消息是否与当前对话相关，不相关则提示开新对话 |
| 追问支持 | 多轮对话保留上下文，支持「那……又是怎么回事？」式追问 |
| 结论 UI 标识 | 醒目的「✓ 正确」「✗ 错误」「? 存疑」标签，带颜色区分 |

**估时**：1.5 周  
**验收标准**：3 个典型事实（1真1假1存疑）判断准确，追问能正确延续上下文。

---

### v0.6 — 角色扮演 Agent
**目标**：用户选择角色后能与其进行多轮剧情沉浸式对话。

| 交付内容 | 说明 |
|----------|------|
| Tool：`get_character_info` | 检索角色 Wiki 信息：性格、身份、相关剧情摘要 |
| 角色搜索界面 | 输入角色名 → 模糊匹配本地索引 → 建议列表 |
| 角色信息卡 | 展示性格/身份/登场剧情，来源标注，风格与主题一致 |
| 场景描述输入 | 可选文本框，填写当前对话发生的剧情背景 |
| 角色扮演 Workflow | 角色卡 + 场景 + RAG 上下文 → System Prompt 构建 → 多轮对话 |
| 对话存档 | 保存对话历史，支持「继续上次对话」和「重新开始」 |

**估时**：2 周  
**风险**：角色语气和性格保持是软约束，依赖 Prompt 工程，需针对几个典型角色（如阿米娅、凯尔希、W）测试效果。  
**验收标准**：与阿米娅对话时语气、用词与游戏内一致，追加剧情背景后对话内容有对应变化。

---

### v0.7 — Wiki 智能联动
**目标**：Wiki 浏览过程中可直接触发 AI 功能，消除上下文切换摩擦。

| 交付内容 | 说明 |
|----------|------|
| 长按文字浮动菜单 | WebView JavaScript Bridge 捕获文字选中事件 |
| 「问 AI」跳转 | 将选中文字 + 当前 URL 带入 AI 对话（自动填充输入框）|
| 「添加书签」 | 快速保存当前段落位置 |

**估时**：1 周  
**风险**：iOS WebView 的文字选中事件监听限制较多，需测试兼容性。  
**验收标准**：在 PRTS Wiki 长按任意段落，能正确弹出菜单并跳转到 AI 对话页。

---

### v0.8 — UI 精修与动画打磨
**目标**：整体视觉质量达到「第一眼惊艳」的水准。

| 交付内容 | 说明 |
|----------|------|
| 主题 A 动画 | 扫光、扫描线、档案翻页过渡完整实现 |
| 主题 B 动画 | 全息环、网格漂移、粒子发光完整实现 |
| 主题切换动画 | 切换时 shimmer 扫过屏幕 |
| 启动页 | 两套主题各自专属启动动画 |
| 引用卡片精修 | 展开/收起弹性动画，卡片内排版优化 |
| 响应式细节 | 不同屏幕尺寸适配，横屏模式基础支持 |

**估时**：1.5 周  
**验收标准**：动画帧率稳定 60fps，切换主题无卡顿，视觉效果符合设计规范截图。

---

### v0.9 — 测试与稳定性
**目标**：找出并修复主要 Bug，为发布做准备。

| 交付内容 | 说明 |
|----------|------|
| 核心路径单元测试 | RAG 检索、Agent Workflow、LLM 客户端的关键路径测试 |
| 错误处理完善 | API 超时、网络断开、空向量库等边界情况的友好提示 |
| 性能测试 | 首次索引 1000 页耗时、检索延迟、内存占用 |
| Beta 测试 | 发出 10~20 个内测版，收集真实玩家反馈 |
| 问题修复 | 根据反馈修复 P0/P1 Bug |

**估时**：1.5 周

---

### v1.0 — 正式发布
**目标**：代码质量、文档、社区准备到位，正式开源。

| 交付内容 | 说明 |
|----------|------|
| GitHub 仓库建立 | 规范目录结构，`.gitignore`，`CHANGELOG.md` |
| README.md | 项目介绍、截图、功能说明、配置 API Key 指引、贡献说明 |
| LICENSE | GPL-3.0 文件，`AUTHORS` 文件明确署名要求 |
| CONTRIBUTING.md | 贡献指南，PR 规范，Code Style |
| GitHub Actions | 自动构建 APK / IPA，发布到 Release |
| F-Droid / 侧载 | 提交 F-Droid 或发布签名 APK 供直接安装 |

**估时**：1 周  

---

### 总估时概览

| 版本 | 主要内容 | 估时 | 累计 |
|------|----------|------|------|
| v0.1 | 骨架 + 双主题 | 1 周 | 1 周 |
| v0.2 | Wiki 浏览器 | 1.5 周 | 2.5 周 |
| v0.3 | LLM + 知识库基础设施 | 2 周 | 4.5 周 |
| v0.4 | 梗概生成 Agent | 2 周 | 6.5 周 |
| v0.5 | 事实核查 Agent | 1.5 周 | 8 周 |
| v0.6 | 角色扮演 Agent | 2 周 | 10 周 |
| v0.7 | Wiki 智能联动 | 1 周 | 11 周 |
| v0.8 | UI 精修 + 动画 | 1.5 周 | 12.5 周 |
| v0.9 | 测试 + 稳定性 | 1.5 周 | 14 周 |
| v1.0 | 正式发布 | 1 周 | **15 周** |

> [!TIP]
> 如果优先验证 AI 功能的实用性，可以在 v0.3 完成后先内测，用真实玩家反馈来调整 Agent Prompt，再继续开发后续版本。

---

## 已确认决策（全部）

| 问题 | 决策 |
|------|------|
| App 名称 | **ArkLores**（英文，与 Arknights 读音相近，意为「方舟传说/方舟知识库」） |
| 书籍导入方式 | **文件导入**（PDF / TXT），自动提取文本并建立向量索引 |
| 书籍导入入口 | 底部导航独立 **资料 Tab**（非设置内嵌） |
| 多本书籍支持 | 支持同时导入多本书籍，可分别管理和删除 |
| 最低系统版本 | Android 8.0（API 26）/ iOS 14 |
| sqlite-vec 方案 | FFI 绑定优先，不可用时回退纯 Dart cosine similarity |
| 作者署名 | **hhikr**（写入 `AUTHORS` 文件、README、LICENSE 头部） |
| GitHub 仓库 | `github.com/hhikr/ArkLores` |
| AI 资料可信度 | 书籍来源内容全局应用信任策略，以 Wiki 为优先参考，引用时马色区分并附免责声明 |

> [!NOTE]
> 架构设计已全部确认。下一步可开始建立项目、搜索库名并初始化 Flutter 工程（v0.1）。



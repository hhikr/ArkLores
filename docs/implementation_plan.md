# ArkLores — 明日方舟剧情助手 · 架构设计文档

> 一款为《明日方舟》剧情爱好者打造的 AI 增强阅读工具。开源、无服务器、用户自带 API Key。

---

## 项目概览

| 项目 | 决策 |
|------|------|
| **App 名称** | **ArkLores**（英文，与 Arknights 读音相近，一语双关） |
| 目标平台 | Android + iOS（Flutter） |
| 最低系统版本 | Android 8.0（API 26）/ iOS 14 |
| AI 接入 | 用户自带 API Key，OpenAI 兼容接口（Chat + Embedding 可分开指定不同提供商）；Embedding 是召回补充，不再作为唯一检索入口 |
| 数据存储 | 本地 SQLite（结构化 GameData + FTS + chunk metadata）+ 可选向量检索 |
| 向量方案 | sqlite-vec FFI 暂不可用；当前使用 sqflite + 纯 Dart cosine similarity 作为临时向量回退。生产检索以结构化查询 / FTS / 标题匹配优先 |
| 本地化 | **中文优先**；UI 保留 EN / 中文双语框架，知识库 v0.4.5 起仅构建中文 GameData |
| Agent 实现 | 纯 Dart 手写 ReAct Loop |
| 状态管理 | Riverpod |
| 开源协议 | GPL-3.0 + README 道义声明"非商业" |
| 作者署名 | `hhikr`（GitHub ID，写入 AUTHORS 文件和 README） |
| 视觉主题 | **双主题可切换**：① 明日方舟·战术档案风 ② 终末地·全息投影风 |
| 知识来源 | **中文 GameData 解包数据（主知识源，release asset 下载）** + 指定 Wiki 在线搜索补充 + 书籍文件（用户导入 PDF/TXT） |
| 迭代路线 | v0.1: 项目骨架与双主题；v0.2: Wiki 浏览器；v0.3: LLM + Wiki RAG 原型基础设施；v0.4: Agent 基础设施 + 可替换知识源抽象 + Summary MVP；v0.4.5: 中文 GameData 知识库重构；v0.5: 基于 GameData 的事实核查 Agent；v0.6: 基于 GameData 的角色扮演 Agent；v0.7: Wiki 智能联动；v0.8: UI 精修；v0.9: 测试；v1.0: 发布 |

> [!IMPORTANT]
> **2026-07 架构转向决策**：v0.3 的 Wiki seed + built-in embedding 已验证为原型链路，不再作为长期主知识库方案。后续主知识源改为中文 GameData 解包数据，通过 GitHub release asset 在 App 内下载；Wiki 仅作为受限在线补充检索工具，Book 仍作为用户导入的低可信辅助来源。

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
│  │  │  search_local_lore | get_entity_profile    │  │  │
│  │  │  get_story_context | search_wiki | cite    │  │  │
│  │  └────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────────────┬───────────────────────────┘
                             │
         ┌───────────────────┼──────────────────┐
         ▼                   ▼                  ▼
┌──────────────┐   ┌──────────────────────────┐  ┌──────────────┐
│ SQLite + FTS │   │   内容摄取层               │  │  LLM Client  │
│ 结构化索引     │   │  ┌──────────────────────┐  │  │  OpenAI 兼容 │
│ + 可选向量     │   │  │ GameData 解包导入器    │  │  │  Embedding + │
│ 检索回退       │   │  │ Release Asset DB     │  │  │  Chat API    │
└──────────────┘   │  ├──────────────────────┤  │  └──────────────┘
                   │  │ Wiki 在线补充搜索      │  │
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

  > ⚠️ **资料内容属用户导入，可能包含非官方解读、翻译误差或个人总结。AI 将小心引用，并以 GameData 游戏原文为最高优先参考，Wiki 作为补充。**

---

### 4. 知识库（RAG 引擎）

知识库支持三类内容来源。v0.4.5 起，中文 GameData 解包数据是主知识源；Wiki 不再作为主 RAG seed，而是受限在线补充搜索；用户导入 Book 仍作为辅助资料。Agent 必须透明感知来源类型，并按可信度优先级使用证据。

#### 来源一：中文 GameData 解包数据（主知识源）

```
中文解包数据（角色 / 剧情 / 语音 / 物品 / 组织等）
  → 解析结构化实体、剧情行、语音台词、档案字段
  → 写入 SQLite structured tables + FTS index
  → 生成 lore_chunks（带 entity_id / story_id / speaker / source_path）
  → 可选生成 embedding（API 或内置模型）
  → 打包为 GitHub release asset，App 内下载安装
```

#### 来源二：指定 Wiki 在线补充搜索

```
受限 Wiki 搜索工具（PRTS / Warfarin 等允许站点）
  → 只在 Agent 需要查缺补漏或交叉验证时调用
  → 不作为默认主知识源
  → 返回时标注 source_type = 'wiki'
```

#### 来源三：书籍文件导入（大地巡旅等）

```
用户通过文件选择器选取 PDF 或 TXT 文件
  → PDF：使用 syncfusion_flutter_pdf 提取纯文本
  → TXT：直接读取
  → 按段落/固定窗口切块（~500 Token，50 Token 重叠）
  → 写入本地 chunks + FTS + 可选 embedding
  → source_type = 'book'，file_name 记录书名
```

> [!NOTE]
> 书籍文件仅存储提取后的纯文本块，不保留原始 PDF。引用卡片展示时来源显示为「书籍·[文件名]」。

#### 索引策略

| 操作 | 触发方式 |
|------|----------|
| 首次建立 | 用户在知识库页面下载中文 GameData release asset |
| 更新 GameData | 下载新版 release asset，校验 manifest 后替换或迁移本地 DB |
| Wiki 补充搜索 | Agent 运行时按需调用受限 Wiki 搜索工具 |
| 导入书籍 | 知识库管理页「导入书籍」按钮，选择文件后自动索引 |
| 删除书籍 | 知识库管理页列表中删除，同步清除对应向量 |

#### SQLite Schema（v0.3 原型 / v0.4.5 将升级）

> [!NOTE]
> v0.3 schema 是 Wiki RAG 原型。v0.4.5 将新增 `entities`、`story_lines`、`lore_chunks`、FTS 表和 GameData manifest。详细设计见 `docs/GAMEDATA_KNOWLEDGE_PLAN.md`。

```sql
CREATE TABLE chunks (
  id          TEXT PRIMARY KEY,  -- UUID
  source_type TEXT NOT NULL,     -- 'game_story' | 'operator_profile' | 'operator_voice' | 'wiki' | 'book' 等
  -- Wiki 来源字段
  source_url  TEXT,              -- 原始 Wiki 页面 URL（wiki 类型）
  wiki        TEXT,              -- 'prts' | 'warfarin'（wiki 类型）
  -- 书籍来源字段
  book_id     TEXT,              -- 关联 books.id（book 类型）
  -- 通用字段
  page_title  TEXT,              -- Wiki 页面标题 或 书籍章节标题
  section     TEXT,              -- 所属小节标题
  content     TEXT NOT NULL,     -- 原文内容
  updated_at  INTEGER,           -- Unix timestamp
  embedding_status TEXT DEFAULT 'ok' -- 'ok' | 'zero_vector'
);

CREATE TABLE chunk_embeddings (
  chunk_id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL,
  dimension INTEGER NOT NULL,
  embedding BLOB NOT NULL
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

> GameData 解包数据是主知识源；Wiki 是社区整理的补充证据；用户导入的书籍内容来源不稳定，可能包含翻译误差、非官方解读或进度要求。AI 必须按来源可信度使用证据。

这不是“不用书籍内容”，而是“使用但标注并警醒”。具体实现如下：

#### System Prompt 插入（每个 Agent 均注入）

```
下面提供的检索结果包含三类来源：
- [GameData] 来自中文游戏解包数据（角色档案、剧情原文、语音、物品描述等），作为最高优先级证据
- [Wiki] 来自指定 Wiki 站点（社区整理，用于补充和交叉验证）
- [Book] 来自用户导入的书籍资料（可能包含非官方解读或翻译误差）

引用规则：
1. 当 [GameData] 与 [Wiki] / [Book] 冲突时，优先采信 [GameData]
2. [Wiki] 可作为补充说明，但不得覆盖 GameData 原文证据
3. 引用 [Book] 内容时，必须明确标注为「来自书籍资料」
4. 如果 [Book] 内容无法被 [GameData] 或 [Wiki] 佐证，应说明“此信息仅来自用户导入资料，建议自行核实”
5. 不得将 [Book] 来源的内容以确定语气表述为官方设定
```

#### 引用卡片视觉区分

| 来源类型 | 卡片标识 | 颜色 |
|----------|----------|------|
| GameData 原文 | 🎮 GameData · [类型] | 主题强调色 / 高可信标识 |
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

**配置模型**（Chat + Embedding 分离）：
```dart
class LLMConfig {
  // Chat API
  final String chatBaseUrl;
  final String chatApiKey;
  final String chatModel;

  // Embedding API（可为空，运行时回退到 Chat 配置）
  final String embedBaseUrl;
  final String embedApiKey;
  final String embedModel;

  bool get isValid => chatApiKey.isNotEmpty;
}
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
│   │   │   ├── llm_client.dart     # 抽象接口 + LLMConfig（Chat/Embed 分离）
│   │   │   ├── llm_provider.dart   # Riverpod Provider
│   │   │   └── openai_client.dart  # OpenAI 兼容实现
│   │   ├── agent/
│   │   │   └── agent_prompts.dart  # Agent Prompt 模板（信任策略）
│   │   ├── rag/
│   │   │   ├── vector_store.dart   # SQLite + FTS + 可选向量检索
│   │   │   ├── vector_store_provider.dart
│   │   │   ├── chunker.dart        # 文本分块
│   │   │   ├── embedder.dart       # Embedding 调用（动态维度检测）
│   │   │   └── embedder_provider.dart
│   │   ├── gamedata/               # v0.4.5 中文 GameData 导入与 schema
│   │   │   ├── gamedata_importer.dart
│   │   │   ├── gamedata_models.dart
│   │   │   └── gamedata_manifest.dart
│   │   ├── wiki/
│   │   │   ├── wiki_crawler.dart   # MediaWiki API 爬取
│   │   │   └── wiki_models.dart
│   │   └── agent/
│   │       ├── react_loop.dart     # 通用 ReAct 执行器
│   │       ├── tools/
│   │       │   ├── search_local_lore.dart
│   │       │   ├── get_entity_profile.dart
│   │       │   ├── get_story_context.dart
│   │       │   ├── search_wiki.dart
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
│   │       ├── settings_service.dart   # SecureStorage 存取
│   │       ├── api_settings_page.dart  # Chat/Embed 分开配置
│   │       ├── knowledge_base_page.dart # Wiki 知识库管理
│   │       └── onboarding_page.dart    # 首次引导流程
│   └── shared/
│       ├── l10n/
│       │   ├── app_en.arb             # 英文翻译
│       │   ├── app_zh.arb             # 中文翻译（平行结构）
│       │   ├── generated/             # gen-l10n 自动生成
│       │   ├── l10n.dart              # context.t 便利扩展
│       │   └── locale_provider.dart   # Riverpod 语言切换
│       ├── theme/
│       │   ├── app_theme.dart           # 抽象 Token 接口
│       │   ├── ark_theme_tokens.dart    # 主题A：战术档案风
│       │   └── endfield_theme_tokens.dart # 主题B：全息投影风
│       ├── widgets/
│       │   ├── citation_card.dart       # 可展开引用卡片（Wiki/Book 颜色区分）
│       │   ├── floating_action.dart
│       │   └── theme_aware_card.dart    # 自适应主题的基础卡片组件
│       └── providers/
│           ├── settings_provider.dart   # API 配置（Chat/Embed 分离）
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
  flutter_localizations: sdk:flutter  # 多语言本地化
  intl: any                           # 国际化基础库
  sqflite: ^2.x                       # SQLite
  http: ^1.x                          # HTTP 客户端
  flutter_markdown: ^0.x              # Markdown 渲染
  flutter_secure_storage: ^9.x        # API Key 安全存储
  google_fonts: ^6.x                  # Rajdhani / Exo2 / Noto Sans SC
  file_picker: ^8.x                   # 书籍文件选择（PDF/TXT）
  syncfusion_flutter_pdf: ^26.x       # PDF 文本提取（免费社区版）
  tflite_flutter: ^0.x                # 内置固定 embedding 模型运行时（v0.3 spike）
  path_provider: ^2.x                 # 本地文件路径
  uuid: ^4.x                          # Chunk UUID 生成
```

> [!WARNING]
> **v0.3 实现结论**：当前使用纯 Dart cosine similarity 回退，`sqlite_vec` FFI 路径因包构建不完整暂不可用。
> - 向量的维度不再写死 1536——`Embedder` 自动从首次 API 响应中检测维度（兼容 OpenAI 1536、DeepSeek 2048 等）
> - Chat 和 Embedding 的 API 配置已分离，允许混合使用不同提供商
> - 内置固定 embedding 模型已打包为 TFLite 资产（512 维，512 seq len），支持离线 embedding profile、预构建 seed DB 和移动端 fallback embedding
> - Embedding 已引入 profile 隔离机制：切换 API provider/model 或内置模型时保留旧 profile，当前检索和索引只作用于 active profile；API Key 不参与 profile 身份识别
> - v0.3 已新增桌面端 seed 构建流程：`tool/build_seed.py` 在电脑端爬取 PRTS / Warfarin Wiki、分块、生成 embedding、校验并复制到 `assets/seeds/`，避免用户首次安装后在手机端长时间建库
> - 详情见 `docs/v0.3_SUMMARY.md`

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

### v0.3 — 基础设施：LLM + 知识库（已完成）
**目标**：跑通从 Wiki 爬取 → Embedding → SQLite 本地向量检索的原型链路，为后续 Agent/UI 验证提供临时数据源。

| 交付内容 | 说明 |
|----------|------|
| 设置页：API Key 配置 | **Chat/Embedding 分开配置**，独立 Base URL / API Key / 模型，位于子页面「API Settings」；支持混合使用不同提供商（如 DeepSeek + OpenAI） |
| LLM 客户端 | `OpenAICompatibleClient` 实现，支持 Chat + Embedding+ Streaming，配置按方法路由不同 API |
| MediaWiki 爬取器 | 调用 `api.php` 批量拉取页面内容，支持 PRTS + 终末地 |
| 文本分块器 | ~500 Token 窗口，50 Token 重叠，按标题层级切分 |
| sqlite-vec 集成 | **纯 Dart cosine similarity 回退**（FFI 因包构建不完整暂不可用）；向量维度**动态检测**，从首次 API 响应获取 |
| Wiki 知识库管理页 | 显示索引状态、页面数、向量数，支持后台异步索引、seed 页面快速跳过、清理废弃数据、失败 Embedding 条目统计与一键手动重试 |
| **资料 Tab 功能** | 书籍列表、PDF/TXT 导入、进度展示、显示名编辑、删除 |
| **AI 信任策略实现** | Prompt 插入参考第 5 节，引用卡片颜色区分 Wiki/书籍 |
| 首次引导流程 | 未配置 API Key 时，引导用户完成配置 + 首次 Wiki 索引建立 |
| **多语言本地化**（追加） | `flutter_localizations` + ARB 文件，EN / 中文双语平行，Riverpod 切换即时生效 |
| **预构建 seed 知识库**（追加） | 桌面端构建 `arklores_knowledge.db.gz` release asset + `wiki_cache.zip` + manifest，App 下载后安装到本地 files 目录 |

**估时**：2 周  
**风险**：sqlite-vec Flutter FFI 绑定不稳定，需预留备选方案时间。  
**验收标准**：能安装预构建 seed 知识库（当前 17087 chunks），能执行语义搜索并返回结果，Wiki 同步不会重复重建健康 seed 页面。

> [!WARNING]
> v0.3 的 Wiki seed 与 built-in embedding 已确认为原型能力。后续不再围绕该方案继续深度优化检索质量；v0.4.5 将以中文 GameData release asset 重建主知识库。

---

### v0.4 — Agent 基础设施 + 可替换知识源抽象 + Summary MVP
**目标**：建立稳定的 ReAct / Tool / Citation / UI 基础设施，并将 Agent 从 `search_wiki` 单一数据源中解耦。Summary Agent 交付 MVP，但不以 v0.3 Wiki RAG 质量作为最终验收目标。

| 交付内容 | 说明 |
|----------|------|
| ReAct Loop 稳定性 | 支持 Tool 调用、多轮思考、非严格 Action Input 修复、空回答保护、截断检测与续写 |
| Tool 抽象重构 | 引入 `search_local_lore` / `get_entity_profile` / `get_story_context` 的接口预留，`search_wiki` 降级为在线补充工具 |
| Tool：临时本地检索 | 当前可代理 v0.3 Wiki DB，但接口命名和返回结构必须兼容未来 GameData |
| Tool：`cite_source` | 根据 chunk_id 返回原文 + 来源 URL / source_path，支持 GameData / Wiki / Book 多来源 |
| Summary MVP | 实体分类 → 本地知识源检索 → 必要时 Wiki 补充 → 层级摘要 → Markdown 输出 |
| AI 对话界面骨架 | 三模式顶部 Tab，气泡消息列表，Markdown 渲染，真正流式最终回答 |
| 引用卡片 UI | 引用卡片按 GameData / Wiki / Book 区分来源、可信度和跳转方式 |

**估时**：2 周  
**风险**：v0.3 Wiki RAG 数据质量有限，Summary MVP 只验证 Agent 链路与信息源抽象；高质量内容依赖 v0.4.5 GameData DB。  
**验收标准**：输入「阿米娅」「凯尔希」「罗德岛」不会返回空回答或无提示截断；工具参数解析稳定；引用来源类型清晰；若数据不足必须明确说明限制。

---

### v0.4.5 — 中文 GameData 知识库重构
**目标**：以中文解包数据重建主知识库，作为 v0.5 / v0.6 的可靠数据基础。数据库通过 GitHub release asset 发布，App 内下载安装。

| 交付内容 | 说明 |
|----------|------|
| GameData 导入管线 | 解析中文角色档案、剧情文本、语音、物品描述、组织/事件相关数据 |
| 结构化 SQLite Schema | 新增 `entities`、`story_lines`、`lore_chunks`、FTS 表、manifest 表 |
| Release asset 分发 | 构建 `arklores_gamedata_zh.db.gz` + manifest，App 内下载、校验、安装 |
| FTS / 结构化检索 | 标题、别名、speaker、剧情 ID、正文关键词优先，向量检索为补充 |
| 引用定位 | 引用卡片能显示 GameData 类型、source_path、剧情行号或实体字段 |
| 检索验收 | 固定查询集：阿米娅、凯尔希、罗德岛、龙门、莱茵生命、第二次卡兹戴尔战争 |

**估时**：2 周  
**风险**：解包数据格式稳定性、数据版权/体积、GameData 版本更新策略。  
**验收标准**：中文 GameData DB 可下载并安装；固定查询能稳定命中正确实体或剧情；Fact Check / Roleplay 可直接基于 GameData 开发。

---

### v0.5 — 事实核查 Agent
**目标**：基于 GameData 原文优先的证据链，用户输入一个剧情说法后得到「真/假/存疑/无法确认」的判断和依据。

| 交付内容 | 说明 |
|----------|------|
| 事实核查 Workflow | 关键词提取 → GameData 原文/结构化检索 → 必要时 Wiki 补充 → 证据汇总 → LLM 综合判断 |
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
| Tool：`get_character_info` | 读取 GameData 角色档案、语音、干员密录和剧情上下文 |
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
| v0.3 | LLM + Wiki RAG 原型基础设施 | 2 周 | 4.5 周 |
| v0.4 | Agent 基础设施 + Summary MVP | 2 周 | 6.5 周 |
| v0.4.5 | 中文 GameData 知识库重构 | 2 周 | 8.5 周 |
| v0.5 | 基于 GameData 的事实核查 Agent | 1.5 周 | 10 周 |
| v0.6 | 基于 GameData 的角色扮演 Agent | 2 周 | 12 周 |
| v0.7 | Wiki 智能联动 | 1 周 | 13 周 |
| v0.8 | UI 精修 + 动画 | 1.5 周 | 14.5 周 |
| v0.9 | 测试 + 稳定性 | 1.5 周 | 16 周 |
| v1.0 | 正式发布 | 1 周 | **17 周** |

> [!TIP]
> v0.3 后不要继续围绕 Wiki RAG 深调 Prompt。v0.4 先完成 Agent 基础设施和知识源抽象，v0.4.5 完成中文 GameData 主知识库后，再进入 Fact Check 与 Roleplay 的质量打磨。

---

## 已确认决策（全部）

| 问题 | 决策 |
|------|------|
| App 名称 | **ArkLores**（英文，与 Arknights 读音相近，意为「方舟传说/方舟知识库」） |
| 书籍导入方式 | **文件导入**（PDF / TXT），自动提取文本并建立向量索引 |
| 书籍导入入口 | 底部导航独立 **资料 Tab**（非设置内嵌） |
| 多本书籍支持 | 支持同时导入多本书籍，可分别管理和删除 |
| 最低系统版本 | Android 8.0（API 26）/ iOS 14 |
| sqlite-vec 方案 | **纯 Dart cosine similarity 回退**（FFI 因包构建不完整暂不可用） |
| Chat/Embedding 配置 | **可分开指定不同提供商**（如 Chat 用 DeepSeek，Embedding 用 OpenAI），设置页位于子页面「API Settings」 |
| Embedding 维度 | **动态检测**——从首次 API 响应自动获取，不写死 1536，兼容 OpenAI / DeepSeek / 其他模型 |
| 内置 Embedding | **接受安装包体积增大**；仅支持一个固定内置模型，不提供用户替换模型能力；v0.3 已打包固定 512 维 TFLite 模型并用于 seed embedding 与移动端 fallback |
| Embedding Profile | **保留旧 profile**；用户切换 provider/model/内置模型时创建或激活独立 profile，可切回旧 profile；删除 profile 需用户手动确认；profile 身份不包含 API Key |
| GameData 知识库 | **只做中文**；以解包数据构建主知识库，通过 GitHub release asset 在 App 内下载 |
| Wiki 定位 | Wiki 不再作为主 RAG seed；保留 WebView 阅读与受限在线补充搜索工具 |
| 本地化 | UI 保留 **EN / 中文双语**，`flutter_localizations` + ARB 文件（平行结构，编译时类型安全）；知识库内容中文优先 |
| 作者署名 | **hhikr**（写入 `AUTHORS` 文件、README、LICENSE 头部） |
| GitHub 仓库 | `github.com/hhikr/ArkLores` |
| AI 资料可信度 | 全局优先级：GameData / 游戏原始文本 > 指定 Wiki > 用户导入 Book；Book 引用必须附免责声明 |

> [!NOTE]
> 架构设计已全部确认。下一步可开始建立项目、搜索库名并初始化 Flutter 工程（v0.1）。

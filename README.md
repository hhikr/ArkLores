# ArkLores

> *Arknights AI-enhanced reading companion — 明日方舟剧情智能助手*

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-lightgrey)](https://flutter.dev)
[![Version](https://img.shields.io/badge/version-0.3.0-brightgreen)](CHANGELOG.md)

ArkLores 是一款面向《明日方舟》与《明日方舟：终末地》剧情爱好者的 AI 增强阅读助手。开源、无服务器、用户自带 API Key。

---

## 功能

| 版本 | 功能 | 状态 |
| :--- | :--- | :--- |
| v0.1 | 项目骨架 + 双主题系统 | ✅ 已发布 |
| v0.2 | Wiki 浏览器 (PRTS + 终末地) + 书签系统 | ✅ 已发布 |
| v0.3 | LLM 接入 + Wiki RAG 原型 + 资料导入 | ✅ 已发布 |
| v0.4 | Agent 基础设施 + 可替换知识源抽象 + Summary MVP | 🚧 开发中 |
| v0.4.5 | 中文 GameData 知识库重构（release asset 下载） | 📋 规划中 |
| v0.5 | 基于 GameData 的事实核查 Agent | 📋 规划中 |
| v0.6 | 基于 GameData 的角色扮演 Agent | 📋 规划中 |
| v0.7 | Wiki 智能联动 | 📋 规划中 |
| v0.8 | UI 精修 + 动画 | 📋 规划中 |

### 核心特色

- **双主题视觉系统** — 明日方舟「战术档案」与终末地「全息投影」两套完整主题，一键切换
- **双站 Wiki 浏览器** — 内置 PRTS Wiki 与终末地 Wiki 双站 WebView，Tab 点击切换，可展开悬浮工具栏，支持单手操作
- **Wiki 深色模式** — CSS 智能反色注入，适配所有 Wiki 页面，支持亮暗一键切换
- **书签系统** — SQLite 持久化书签，支持收藏/删除/快速跳转
- **LLM 与 Embedding 分离配置** — Chat / Embedding 可使用不同 OpenAI 兼容提供商
- **本地知识库** — v0.3 提供 PRTS + Warfarin Wiki seed 原型；v0.4.5 起主知识源转为中文 GameData release asset
- **资料管理** — 导入 PDF/TXT 书籍（如《大地巡旅》），自动分块、向量化并纳入检索
- **Embedding Profile 隔离** — API / 内置模型索引互不混用，可切换、保留、删除
- **AI 剧情助手** — 三种 Agent 模式：事实核查、梗概生成、角色扮演（v0.4+）
- **隐私优先** — API Key 加密保存在本地，知识库数据库位于设备本地

---

## 开始使用

### 前置要求

- Android 8.0（API 26）或更高 / iOS 14 或更高

### 从源码构建

请参考 [Android 构建指南](docs/ANDROID_SETUP_GUIDE.md) 配置开发环境。

```bash
# 克隆仓库
git clone https://github.com/hhikr/ArkLores.git
cd ArkLores

# 获取依赖
flutter pub get

# 运行（需连接设备）
flutter run
```

### API Key 配置

ArkLores 需要 OpenAI 兼容接口的 API Key 才能使用 AI 功能：

1. 启动 App 后进入「设置」页
2. 进入「API Settings」，分别填写 Chat 和 Embedding 的 Base URL、API Key、模型名
3. v0.3 可从 release asset 下载 Wiki seed 原型知识库；v0.4.5 起将提供中文 GameData 知识库下载
4. API Key 通过 `flutter_secure_storage` 加密存储在本地

> 建议使用 OneAPI / NewAPI 等中转服务，支持大多数国产 LLM。
> **你的 API Key 仅存于本地，不会上传到任何第三方服务器。**

---

## 技术栈

| 类别 | 选型 |
| :--- | :--- |
| 框架 | Flutter (Dart) |
| 状态管理 | Riverpod |
| 知识库 | SQLite structured tables + FTS + 可选向量检索；v0.4.5 起中文 GameData 为主知识源 |
| AI 接入 | OpenAI 兼容 API（用户自备 Key） |
| 本地 Embedding | 固定 TFLite 模型（512 维，作为召回补充；不作为唯一检索入口） |
| Agent 引擎 | 纯 Dart 手写 ReAct Loop（v0.4+） |
| WebView | flutter_inappwebview |
| PDF 提取 | syncfusion_flutter_pdf |

---

## 项目结构

```text
arklores/
├── lib/
│   ├── main.dart                          # 应用入口
│   ├── app.dart                           # 导航与主题壳
│   ├── core/                              # 核心逻辑层
│   │   ├── llm/                           # LLM 客户端
│   │   ├── rag/                           # 知识库引擎
│   │   ├── wiki/                          # Wiki 爬取
│   │   └── agent/                         # Agent 执行器
│   ├── features/                          # 功能页面
│   │   ├── wiki/                          # Wiki 浏览
│   │   ├── ai/                            # AI 对话
│   │   ├── materials/                     # 资料管理
│   │   └── settings/                      # 设置
│   └── shared/                            # 共享层
│       ├── theme/                         # 双主题系统
│       ├── widgets/                       # 通用组件
│       └── providers/                     # 全局状态
├── android/
├── ios/
└── docs/
    ├── implementation_plan.md             # 架构设计文档
    ├── GIT_GUIDE.md                       # Git 规范
    ├── ANDROID_SETUP_GUIDE.md             # 构建环境配置
    └── ...
```

---

## 开发

### 分支策略

简化 GitFlow：

```text
main     ← 稳定发布版本
dev      ← 日常集成分支
feature/*  ← 新功能（从 dev 分支）
fix/*      ← Bug 修复（从 dev 分支）
```

详见 [GIT_GUIDE.md](docs/GIT_GUIDE.md)。

### 贡献

欢迎提交 Issue 和 PR！请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

---

## 许可

本项目基于 **GNU General Public License v3.0** 开源。

> **署名要求**：所有衍生作品必须保留原作者署名 `hhikr`。
> **非商业声明**：虽然 GPL-3.0 允许商业使用，但作者以道义要求：**请勿将本项目或衍生作品用于商业盈利目的。**

---

## 致谢

- [PRTS Wiki](https://prts.wiki) — 明日方舟中文维基
- [Warfarin Wiki](https://warfarin.wiki/cn) — 明日方舟：终末地中文维基
- 明日方舟中文 GameData 社区整理与相关工具生态
- Flutter 及所有开源依赖的作者们

---

Made for the Arknights lore community

# ArkLores

> *Arknights AI-enhanced reading companion — 明日方舟剧情智能助手*

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-lightgrey)](https://flutter.dev)
[![Version](https://img.shields.io/badge/version-0.1.0--dev-brightgreen)](CHANGELOG.md)

ArkLores 是一款面向《明日方舟》与《明日方舟：终末地》剧情爱好者的 AI 增强阅读助手。开源、无服务器、用户自带 API Key。

---

## 功能

| 版本 | 功能 | 状态 |
| :--- | :--- | :--- |
| v0.1 | 项目骨架 + 双主题系统 | ✅ 已发布 |
| v0.2 | Wiki 浏览器 (PRTS + 终末地) | 📋 规划中 |
| v0.3 | LLM 接入 + 知识库 RAG | 📋 规划中 |
| v0.4 | 梗概生成 Agent | 📋 规划中 |
| v0.5 | 事实核查 Agent | 📋 规划中 |
| v0.6 | 角色扮演 Agent | 📋 规划中 |
| v0.7 | Wiki 智能联动 | 📋 规划中 |
| v0.8 | UI 精修 + 动画 | 📋 规划中 |

### 核心特色

- **双主题视觉系统** — 明日方舟「战术档案」与终末地「全息投影」两套完整主题，一键切换
- **Wiki 知识库** — 接入 PRTS Wiki 与终末地 Wiki，构建本地语义搜索引擎
- **AI 剧情助手** — 三种 Agent 模式：事实核查、梗概生成、角色扮演
- **资料管理** — 导入 PDF/TXT 书籍（如《大地巡旅》），AI 自动索引并辅助阅读
- **隐私优先** — 本地向量数据库，你的数据不出设备

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
2. 填写 Base URL、API Key、模型名
3. API Key 通过 `flutter_secure_storage` 加密存储在本地

> 建议使用 OneAPI / NewAPI 等中转服务，支持大多数国产 LLM。
> **你的 API Key 仅存于本地，不会上传到任何第三方服务器。**

---

## 技术栈

| 类别 | 选型 |
| :--- | :--- |
| 框架 | Flutter (Dart) |
| 状态管理 | Riverpod |
| 知识库 | SQLite + sqlite-vec（向量搜索） |
| AI 接入 | OpenAI 兼容 API（用户自备 Key） |
| Agent 引擎 | 纯 Dart 手写 ReAct Loop |
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
- [终末地 Wiki](https://endfield.wiki) — 明日方舟：终末地中文维基
- Flutter 及所有开源依赖的作者们

---

Made with ❤️ for the Arknights lore community

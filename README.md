<div align="center">

<img src="docs/images/cover.png" width="200" alt="ArkLores">

# ArkLores

**明日方舟与终末地的剧情阅读与问答 App**

[![Release](https://img.shields.io/github/v/release/hhikr/ArkLores?style=flat-square&color=2f6f4f&label=release)](https://github.com/hhikr/ArkLores/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/hhikr/ArkLores/total?style=flat-square&color=2f6f4f)](https://github.com/hhikr/ArkLores/releases)
[![Platform](https://img.shields.io/badge/platform-Android-3ddc84?style=flat-square&logo=android&logoColor=white)](https://github.com/hhikr/ArkLores/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-02569B?style=flat-square&logo=flutter&logoColor=white)](https://flutter.dev)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial-555?style=flat-square)](LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/hhikr/ArkLores?style=flat-square&color=555)](https://github.com/hhikr/ArkLores/commits)

[下载](https://github.com/hhikr/ArkLores/releases/latest) · [功能介绍](docs/guide/INTRODUCTION.md) · [使用教程](docs/guide/GETTING_STARTED.md) · [更新日志](CHANGELOG.md)

</div>

---

ArkLores 把《明日方舟》和《明日方舟：终末地》的剧情文本整理成手机上的知识库。你可以在里面读全部剧情和档案，看每句台词配的立绘和场景，也可以向 AI 提问。AI 的每个论点都附原文出处，点一下就能跳到那段剧情核对。

## 功能

| | |
| --- | --- |
| **读剧情** | 两个游戏的主线、活动、故事集、干员档案、集成战略故事都能读。阅读器记住读到哪一行，可以拖动进度、查找、看目录。 |
| **剧情美术** | 立绘、场景、CG 和特写按剧本排在对话之间。点人名能看这个人的全部立绘和表情差分。 |
| **泰拉年表** | 收录 PRTS Wiki 的《泰拉年表》，按纪元和年份列出事件，点出处直接进对应的剧情。 |
| **AI 问答** | AI 查本地知识库、Wiki 和你添加的资料后作答。每个论点附原文出处，出处由代码核对是否真的读过。 |
| **Wiki** | 内置 PRTS 和终末地 Wiki，可以加书签，也可以换成别的站点。 |
| **自动更新** | 服务器每小时检查游戏数据，有新剧情就更新知识库，App 打开时会提示。 |

每个功能的动图演示见[功能介绍](docs/guide/INTRODUCTION.md)。

## 快速开始

1. 从 [Releases](https://github.com/hhikr/ArkLores/releases/latest) 下载 APK 并安装。目前只有 Android 版。
2. 打开 App，按新用户导览下载知识库。
3. 想用 AI 问答，配好对话 API 和向量 API。推荐智谱 `glm-5.3-flash` 和阿里云百炼 `qwen3.7-text-embedding`。

每一步怎么操作，见[使用教程](docs/guide/GETTING_STARTED.md)。

## 文档

**使用**

| 文档 | 内容 |
| --- | --- |
| [功能介绍](docs/guide/INTRODUCTION.md) | 每个功能是什么样子，附动图 |
| [使用教程](docs/guide/GETTING_STARTED.md) | 安装、配置 API、下载知识库、读剧情、提问，以及常见问题 |
| [下载与版本](docs/DOWNLOADS.md) | 安装包、知识库和美术包放在哪里，各版本的主要变化 |
| [已知问题](docs/KNOWN_ISSUES.md) | 还没解决的问题 |
| [更新日志](CHANGELOG.md) | 每个版本的完整改动 |

**开发**

| 文档 | 内容 |
| --- | --- |
| [开发](docs/DEVELOPMENT.md) | 本机运行、技术栈、目录结构 |
| [架构](docs/ARCHITECTURE.md) | 各模块怎么实现 |
| [问答 Agent](docs/ASK_AGENT.md) | 问答的流程、工具、出处核对和答案格式 |
| [问答实验记录](docs/ASK_EXPERIMENTS.md) | 问答试过的办法、实测结果和不再尝试的方向 |
| [知识库构建](docs/GAMEDATA_BUILD_PIPELINE.md) | 两个知识库怎么构建、更新和发布 |
| [建库经验](docs/KNOWLEDGE_BASE_LESSONS.md) | 建库时遇到的问题和注意事项 |
| [终末地剧情排列](docs/ENDFIELD_STORY_ORDER.md) | 终末地剧情怎么按任务步骤排列 |
| [剧情立绘与美术](docs/PORTRAITS.md) | 立绘和美术的数据、美术包、界面 |
| [补充资料](docs/MATERIALS.md) | 补充资料的选择、向量和引用 |
| [Wiki](docs/WIKI.md) | Wiki 浏览和问答查 Wiki |
| [模型服务](docs/LLM_PROVIDERS.md) | 各家模型服务的参数和兼容问题 |
| [界面设计](docs/DESIGN.md) | 颜色、字体、部件和交互约定 |
| [验收清单](docs/QA_CHECKLIST.md) | 按改动范围的测试和验收 |
| [Android 构建与发布](docs/ANDROID_SETUP_GUIDE.md) | 本机构建、试装和发布 |
| [参与开发](CONTRIBUTING.md) | 分支、提交和 PR 规范 |

## 鸣谢

ArkLores 用到了下面这些项目和站点的数据与工具，在此感谢。

| 项目 | 用途 |
| --- | --- |
| [Kengxxiao/ArknightsGameData](https://github.com/Kengxxiao/ArknightsGameData) | 明日方舟的解包数据，明日方舟知识库的来源 |
| [rmxlinux/EndfieldData](https://github.com/rmxlinux/EndfieldData) | 终末地的数据表和关卡数据 |
| [555me/beyondGameData](https://github.com/555me/beyondGameData) | 终末地的对话树 |
| [Variante/endfield_research_kit](https://github.com/Variante/endfield_research_kit) | 用其中的 AnimeStudio 在本机解包终末地客户端 |
| [NagiYume/AKEDatabase](https://github.com/NagiYume/AKEDatabase) | 第一份自动构建的终末地知识库用过它的数据 |
| [Arkwaifu](https://arkwaifu.cc) | 剧情美术包里的立绘、场景和 CG 图片（CC BY-NC 4.0） |
| [PRTS Wiki](https://prts.wiki) | 《泰拉年表》（CC BY-NC-SA 4.0），以及 Wiki 浏览和问答查资料 |
| [Warfarin](https://warfarin.wiki)、[fz.wiki](https://fz.wiki) | 终末地 Wiki 浏览。问答查的是 Warfarin |
| [LXGW WenKai Screen](https://github.com/lxgw/LxgwWenKai-Screen)、[Noto Sans SC](https://github.com/google/fonts/tree/main/ofl/notosanssc)、[Saira](https://github.com/Omnibus-Type/Saira) | 阅读与界面字体（SIL OFL 1.1） |
| [lhclbt/Endfield_Font](https://github.com/lhclbt/Endfield_Font) | 装饰用的终末地文字字体（CC BY-NC 4.0） |

## 许可

ArkLores 的代码按 [PolyForm Noncommercial 1.0.0](LICENSE) 授权：可以查看、修改和分享，但不能用于商业用途。

游戏内容（剧情文本、立绘等）的版权归鹰角网络（Hypergryph）所有。上表中第三方的数据、图片和字体按各自的许可使用。

## 支持这个项目

如果 ArkLores 对你有用，欢迎点个 Star，给b站视频一键三连；如果你觉得有什么有趣的功能可以添加、app当前有什么问题，可以在github上提issue、在b站评论区讨论，也是对开发者的一种帮助！如果你用完App后实在是龙颜大悦，决定[补贴个人创作者一些ai费用](docs/SPONSOR.md)，那你真的太好了，简直是我的牢望、费佳、特雷西斯啊（新三并感

[![Stars](https://img.shields.io/github/stars/hhikr/ArkLores?style=flat-square&logo=github&color=2f6f4f)](https://github.com/hhikr/ArkLores/stargazers)
[![Sponsor](https://img.shields.io/badge/sponsor-%E6%94%AF%E4%BB%98%E5%AE%9D-1677ff?style=flat-square&logo=alipay&logoColor=white)](docs/SPONSOR.md)

<a href="https://star-history.com/#hhikr/ArkLores&Date">
  <img src="https://api.star-history.com/svg?repos=hhikr/ArkLores&type=Date" alt="Star History" width="560">
</a>

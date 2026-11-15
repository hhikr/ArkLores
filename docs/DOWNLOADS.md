# 下载与版本

ArkLores 的安装包和知识库都发布在 GitHub Releases 上，分两处放：App 每个版本一个 Release，知识库固定放在一个 Release 里原地更新。

## App

到 [Releases](https://github.com/hhikr/ArkLores/releases) 下载最新版本的 `ArkLores-<版本>.apk`。目前只有 Android 版。

- 每个 Release 只放 APK 和它的 `.sha256` 校验文件。
- 安装包由 GitHub Actions 构建并签名，可以覆盖安装 v0.10.0 及之后的版本。从 v0.9 及更早的版本升级，要先卸载一次。
- v0.20.0 起，可以在 App 的“设置 → 帮助与引导”里检查和下载新版本。自动检查默认关闭。

### 版本

| 版本 | 日期 | 主要变化 |
| --- | --- | --- |
| [v1.0.0](https://github.com/hhikr/ArkLores/releases/tag/v1.0.0) | 2026-11-14 | 第一个正式版。终末地知识库改由服务器自动更新。资料页和问答加入泰拉年表（11-15 的 build 48）。问答可以引用官方梗概，停止时立即中止请求，长答案不再被截断。剧情美术高清包 |
| [v0.21.0](https://github.com/hhikr/ArkLores/releases/tag/v0.21.0) | 2026-11-02 | 问答省 token（同一问累计输入约少四分之三），不再把人物的话当作定论，显示回答价格。资料页的剧情美术总览。阅读器目录与人名下划线 |
| [v0.20.0](https://github.com/hhikr/ArkLores/releases/tag/v0.20.0) | 2026-10-27 | 剧情美术进入阅读、问答与资料页，包括立绘、场景、CG 与特写。问答不限步数，自动压缩上下文。App 内更新 |
| [v0.19.1](https://github.com/hhikr/ArkLores/releases/tag/v0.19.1) | 2026-10-25 | 阅读器拖动进度。Wiki 与问答往下读时收起顶栏和底栏 |
| [v0.19.0](https://github.com/hhikr/ArkLores/releases/tag/v0.19.0) | 2026-10-25 | 更跟手的界面，同时开几个对话，设置分类，开屏与字体 |
| [v0.18.0](https://github.com/hhikr/ArkLores/releases/tag/v0.18.0) | 2026-10-23 | 补充资料参与问答，预置《大地巡旅》 |
| [v0.17.0](https://github.com/hhikr/ArkLores/releases/tag/v0.17.0) | 2026-10-22 | 全 App 的新界面 |

更早的版本见 [Releases](https://github.com/hhikr/ArkLores/releases)，每个版本的完整改动见 [CHANGELOG](../CHANGELOG.md)。

说明：v1.0.0 在 11 月 15 日换成了带泰拉年表的 build 48，版本号没变，所以 build 47 的 App 内更新检查不到它。要用泰拉年表，请从 Release 页重新下载 APK 覆盖安装。

## 知识库与剧情美术包

知识库和剧情美术包都在 [gamedata-channel](https://github.com/hhikr/ArkLores/releases/tag/gamedata-channel) 这个 Release 上。App 启动、回到前台时从这里检查更新，也从这里下载，一般不用手动下载。

| 文件 | 内容 | 大小 |
| --- | --- | --- |
| `arklores_gamedata_zh.db.gz` | 明日方舟知识库：剧情、档案、语音、图鉴、立绘与美术数据、泰拉年表、剧情向量 | 约 130 MB |
| `arklores_endfield_zh.db.gz` | 终末地知识库：剧情对话与过场台词、档案、语音、情报档案库、剧情向量 | 约 16 MB |
| `arklores_story_art_zh.db` | 剧情美术包（标准版） | 约 400 MB |
| `arklores_story_art_hd_zh.db` | 剧情美术包（高清版，立绘保留原图尺寸） | 约 800 MB |
| `gamedata_channel.json` 等 | 渠道文件与清单，记着版本和 SHA-256，以及最低 App 版本 | — |

两个知识库都由服务器自动更新：

- 明日方舟：服务器每小时检查 [Kengxxiao/ArknightsGameData](https://github.com/Kengxxiao/ArknightsGameData)，有新内容就增量更新知识库和剧情美术包，补齐向量后发布。泰拉年表每天检查一次 PRTS Wiki 的版本。
- 终末地：数据取自 GitHub 上的终末地数据仓库，有比已发布版本新的提交时重建。一般比游戏晚几天到一周。

每个文件当前的版本和 SHA-256 写在 gamedata-channel 的 Release 说明和 `gamedata_channel.json` 里。构建与发布的细节见 [GAMEDATA_BUILD_PIPELINE.md](GAMEDATA_BUILD_PIPELINE.md)。

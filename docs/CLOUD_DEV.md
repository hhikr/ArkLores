# 云端开发（Claude Code 云会话，环境 ArkLores-Cloud）

云会话在 Anthropic 的 Ubuntu 24.04 虚拟机里运行，每次从 GitHub **重新克隆**仓库。
本机上没提交的东西（gitignored 的 key、`build/` 里的知识库、`~/.claude` 下的记忆和用户设置）云端都没有；
仓库里的 `CLAUDE.md` 和 `.claude/settings.json` 会随克隆生效。

## 1. 一次性配置环境（claude.ai/code → 环境 ArkLores-Cloud → 编辑）

### 安装脚本（Setup script）

把 `tools/cloud/environment_setup.sh` 的**全部内容**粘贴进去。它以 root 身份运行：装 libsqlite3、Flutter 3.47.5
（装到 `/opt/flutter`，链接到 `/usr/local/bin`），只预取跑测试需要的部分，不装 Android SDK。
脚本在约五分钟内跑完时，环境会被做成快照，之后的新会话直接复用，不再重装（快照约七天过期，改了脚本也会重建）。
脚本必须以 0 退出，否则会话起不来；这个脚本里每一步失败都只打日志、不退出。

### 网络访问（Network access）

默认的 **Trusted** 已包含 `github.com`、`storage.googleapis.com`、`pub.dev`，足够安装 Flutter、拉依赖、跑离线测试。
只有要跑**真实 API 测试**时才需要改：选 **Custom**，勾选 “Also include default list of common package managers”，
再添加你的模型 API 和向量 API 的域名（例如智谱国际站 `api.z.ai`、向量用的 `dashscope.aliyuncs.com`，以 `tools/api_info`、
`tools/embedding-apiKey.csv` 里的 URL 为准）。

### 环境变量（Environment variables，`.env` 格式，一行一个）

只在要跑真实 API 测试时填；不填时其余开发照常进行。

```text
ARKLORES_API_KEY=<模型 API key>
ARKLORES_API_MODEL=<模型名，与 tools/api_info 的 MODEL 相同>
ARKLORES_API_URL=<与 tools/api_info 的 URL 相同>
ARKLORES_EMBEDDING_API_KEY=<向量 API key，可选>
ARKLORES_EMBEDDING_URL=<与 tools/embedding-apiKey.csv 的 openAiCompatible 相同，可选>
```

- 值含 `#` 时要加引号（不加引号时 `#` 之后会被当作注释丢掉）。
- 这些值对**能使用该环境的人**都可见（个人环境就是你自己），也会出现在会话可运行的命令环境里；不要放进仓库。
- 改了变量后，已有会话要等虚拟机下次恢复才读到新值；新开会话立即生效。
- **不需要** GitHub PAT：云端的 git 和 `gh` 通过 GitHub 代理认证，你的 GitHub 凭据不进入虚拟机。

`tools/cloud/session_start.sh` 会把这些变量写成 `tools/api_info`、`tools/embedding-apiKey.csv`（文件已存在则不动，不打印值）。

### 建议：在 GitHub 上保护 main 和 dev

GitHub 代理只拒绝删分支和推 tag，**不限制推哪个分支**。“不直接 push main/dev”目前只靠 CLAUDE.md 约束；
想要硬保证，在 GitHub 仓库 Settings → Branches（或 Rules → Rulesets）给 `main`、`dev` 加保护规则（要求 PR）。

## 2. 每个会话开始

```bash
bash tools/cloud/session_start.sh
```

设置 git 作者（hhikr）、写 key 文件、`flutter pub get`。需要知识库（只有真实 API 测试需要）时再运行：

```bash
bash tools/cloud/fetch_gamedata.sh
```

它按 `tools/release_gamedata.env` 下载并校验当前 Release 上的两个知识库：明日方舟解压到
`build/gamedata_mobile/arklores_gamedata_zh.db`（live 测试的默认路径），终末地解压到 `build/endfield/arklores_endfield_zh.db`
（双游戏的 live 测试用 `ARKLORES_ENDFIELD_DB` 指向它；不给时测试里只装了明日方舟）。终末地库只能在本机从游戏客户端重建，云端只能下载已发布的。

## 3. 云端能做和不能做的

| 能做 | 不能做 / 要回本机 |
|---|---|
| 改代码、`flutter test`、`flutter analyze` | 构建 APK（没有 Android SDK；APK 一直由 GitHub Actions 构建签名） |
| 真实 API 测试（配好环境变量和网络后） | 真机验证（滚动手感、输入法等） |
| 提交、推送功能分支 | 读本机 `logs/`、本机 `build/live_sessions/` 的旧结果 |
| 发布：`tools/release_app.sh`（用 `gh`） | |

- Windows 上被跳过的、依赖 POSIX 文件替换语义的测试在 Linux 上会运行；如果它们失败，是真问题，不是环境问题。
- 全量测试正常约半分钟。明显变慢时先看磁盘（`df -h`）。
- 提交不带 AI 署名：`.claude/settings.json` 关掉了 `Co-Authored-By`、PR 署名和 `Claude-Session` 尾注。
- 发版：`tools/release_app.sh <版本> <说明.md>`（推 `release/v<版本>` → 等 CI → 下载 APK → 建预发布；`STABLE=1` 建正式版）。
  **云端会话不能建 Release**（2026-10-03 实测：GitHub 代理对创建/编辑 Release 返回 403 “not permitted for this session type”）；
  推分支、等 CI、下载 APK 都能做。云端跑到建 Release 这一步失败后，由开发者在 GitHub 网页或本机 `gh release create` 完成最后一步
  （tag `v<版本>`，target 为 release 分支那个提交，预发布勾选 pre-release（正式版不勾），上传 CI 产物里的 APK）；不要重推 release 分支。
  如果云端下载 CI 产物被网络拦下，回本机用 `tools/release_app.ps1` 发同一个版本（`release/v<版本>` 已存在时脚本会拒绝，
  这时只需在本机执行脚本后半段，或删掉分支后重新推——注意重推会重新构建，APK 哈希会变）。

## 4. 新会话的第一条消息（模板）

在 ArkLores-Cloud 环境、选当前开发分支（见 CLAUDE.md 开头）新建会话，粘贴：

```text
这是 ArkLores（明日方舟剧情阅读与问答 Flutter App）的云端会话。先做三件事，再开始工作：

1. 运行 `bash tools/cloud/session_start.sh`，然后 `flutter analyze` 和 `flutter test`，确认环境正常。
2. 读 CLAUDE.md（项目规则与当前进度）以及它的文档索引里与本轮有关的文档；改知识库先读 docs/KNOWLEDGE_BASE_LESSONS.md。
3. 用几句话复述当前版本、本轮目标和相关约束；我确认后再动手。

约束：提交作者只能是 hhikr，不加任何 AI 署名；不推 main；发版要我明确同意；真实 API 测试按成本约束并先问我；
长期有效的规则写进 CLAUDE.md，本轮进度写进 CLAUDE.md 的“当前进度”和相关 docs。
```
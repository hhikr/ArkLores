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
再添加你的模型 API 和向量 API 的域名（例如 `api.deepseek.com`、`dashscope.aliyuncs.com`，以 `tools/api_info`、
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

它按 `tools/release_gamedata.env` 下载并校验 v0.10.1 Release 上的知识库，解压到
`build/gamedata_mobile/arklores_gamedata_zh.db`（live 测试的默认路径）。

## 3. 云端能做和不能做的

| 能做 | 不能做 / 要回本机 |
|---|---|
| 改代码、`flutter test`、`flutter analyze` | 构建 APK（没有 Android SDK；APK 一直由 GitHub Actions 构建签名） |
| 真实 API 测试（配好环境变量和网络后） | 真机验证（滚动手感、输入法等） |
| 提交、推送功能分支 | 读本机 `logs/`、本机 `build/live_sessions/` 的旧结果 |
| 发预发布：`tools/release_app.sh`（用 `gh`） | |

- Windows 上被跳过的、依赖 POSIX 文件替换语义的测试在 Linux 上会运行；如果它们失败，是真问题，不是环境问题。
- 全量测试正常约半分钟。明显变慢时先看磁盘（`df -h`）。
- 提交不带 AI 署名：`.claude/settings.json` 关掉了 `Co-Authored-By`、PR 署名和 `Claude-Session` 尾注。
- 发版：`tools/release_app.sh <版本> <说明.md>`（推 `release/v<版本>` → 等 CI → 下载 APK → 建预发布）。
  如果云端下载 CI 产物被网络拦下，回本机用 `tools/release_app.ps1` 发同一个版本（`release/v<版本>` 已存在时脚本会拒绝，
  这时只需在本机执行脚本后半段，或删掉分支后重新推——注意重推会重新构建，APK 哈希会变）。

## 4. 新会话的第一条消息（模板）

在 ArkLores-Cloud 环境、**分支选 `feature/r18-answer-quality`** 新建会话，粘贴：

```text
这是 ArkLores（明日方舟剧情问答 Flutter App）的云端会话。先做三件事，再开始工作：

1. 运行 `bash tools/cloud/session_start.sh`，然后 `flutter analyze` 和 `flutter test`，确认环境正常（全量测试约半分钟）。
2. 读这些文档了解现状：CLAUDE.md（项目规则，尤其“禁止特判”“禁止针对验收样例编程”“提交规范”
   “真实 API 测试的成本约束”）、docs/CLOUD_DEV.md（云端环境）、docs/R17_TOOL_AGENT.md（当前问答 Agent）、
   docs/KNOWN_LIMITATIONS_AND_DEBT.md §5.9（本轮要做的问题）、CHANGELOG.md 最近两个版本。
3. 读完后用几句话复述：当前版本、问答 Agent 的结构、§5.9 的现象和候选方案；我确认后再动手。

本轮目标：处理 §5.9 的答案质量问题，先做成本最低的候选方案 1–3（两层答案、写作前先确认故事集的叙述框架、
人物问题先做全库覆盖统计）。先出计划给我看。约束：
- 提示词和代码里不得出现具体人物、章节、活动或剧情桥段（包括“梦境”“叙诡”这类词），只写对任意故事都成立的工作方式；
- 先离线（mock LLM）测试，再按成本约束挑最多 2 个用例跑真实 API，逐题串行；
- 提交作者只能是 hhikr，不加任何 AI 署名；不要推 main 或 dev；在 feature/r18-answer-quality 上工作；
- 版本号停在 0.10.x，发版要我明确说；
- 工作中发现的长期有效的规则、流程变化，更新到 CLAUDE.md（它在仓库里，会随克隆生效）；本轮进度写进
  CLAUDE.md 的“当前进度”一节和相关 docs，不要只留在对话里。
```

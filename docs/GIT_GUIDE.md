# Git Guide

## Branches

- `main`：稳定发布分支，不直接开发。
- `dev`：集成分支。
- 功能分支从 `dev` 创建。

不要直接 push 到 `main` 或 `dev`。

## Branch Naming

```text
feature/<scope>-<short-description>
fix/<scope>-<short-description>
docs/<scope>-<short-description>
refactor/<scope>-<short-description>
```

常用 scope：

- `gamedata`
- `agent`
- `rag`
- `settings`
- `wiki`
- `materials`
- `llm`
- `ui`

## Commit Message

使用 Conventional Commits：

```text
<type>(<scope>): <subject>
```

示例：

```text
feat(gamedata): build structured Chinese lore database
fix(agent): handle truncated react completion
docs(rag): document structured retrieval phases
```

## Safety Rules

- 不提交 API key、token、`.env` 内容。
- 不删除 `logs/`。
- 不回退他人未提交改动，除非用户明确要求。
- GameData release asset 是当前主知识库分发方式。
- Wiki 与用户资料不能被表述为官方游戏原文。

## Before PR

- 运行相关 unit tests。
- 大改动运行 `flutter analyze`。
- 涉及 GameData 构建时运行 schema smoke build。

# 模型服务的兼容记录

> App 只说 OpenAI 兼容协议（`lib/core/llm/openai_client.dart`）。各家的差异都在客户端里兼容，Agent 不知道用的是谁。
> 换模型后先看会话记录（设置 → 保存 AI 对话记录）里 `cite` / `coverage` / `from` 等的真实写法，再判断是不是格式问题。

## 思考档位（`ReasoningLevel` off / low / high）

- 每个角色都必须显式指定档位（deepseek 不传参数时默认 high）。默认全部 `off`；“深度思考”开关让本问的 Agent 用 `low`。
  不给剧情问答开 `high`：实测会延伸推测原文没写的内容。
- 映射在 `OpenAICompatibleClient.reasoningFieldsFor`：
  - deepseek：`thinking` + `reasoning_effort`；
  - 百炼：`enable_thinking`；
  - 智谱 GLM（host `z.ai` / `bigmodel.cn` 或模型名 `glm*`）：`reasoning_effort`，off→`low`、low→`high`、high→`max`。**不发 `thinking: disabled`**（glm-5.3-flash 以 1210 拒绝）；
  - Gemini（官方地址或模型名含 gemini）：`reasoning_effort` low/medium/high（思考算在 `max_tokens` 里）；
  - GPT-5、o 系列（`gpt-5*`、`o<数字>*`）：`reasoning_effort`；不接受 `max_tokens` 和非默认 `temperature`，被 400 拒绝时改发
    `max_completion_tokens`、去掉 `temperature` 并记住；
  - 其他：不发字段。
- 服务商因思考字段报 400/422 时去掉重发并记住；拒绝 `stream_options` 时去掉再流式重发，仍被拒才改非流式。

## 智谱 GLM（默认：`glm-5.3-flash`，`https://api.z.ai/api/paas/v4`）

- 不能关闭思考，但 `low` 几乎不思考（80 字回答：不设约 20 s，low 约 4 s）。
- 带工具时把整轮回复攒齐再发（工具轮次没有逐字流式；纯文字答案仍流式）。只接受 `tool_choice: auto`，所以不发 `none`。
- `api.z.ai` 与 `open.bigmodel.cn` 同一个 key 都能用。一道题约 4–6 分钟（带工具的调用有 4.5–6 s 底噪）。
- v0.10.6 教训：GLM 把 `cite` 写成平铺的 `["<id>.txt", 97, 127]`，解析器静默丢掉。提示词里凡是代码要解析的格式都给完整骨架，解析器对常见变体容错，
  丢弃的出处要计数并退回一次。

## 通用兼容（`_StreamAccumulator`，2026-10-07）

- `content` 是分段数组；思考在 `reasoning` / `thinking` 字段；请求流式却回普通 JSON（或反过来）；200 的流里夹着 `error`；
  流式工具调用不带 `index`（按 id 区分）；参数是对象而不是字符串；每行一个 JSON、没有 `data:` 前缀的流；JSON 数组形式的块。
- 工具调用轮次的空文本被 400 拒绝时改发 `content: null` 并记住（Gemini 拒绝空文本段）。
- 一轮完全为空（或读不懂的 200 回复）时，依次改用 非流式 → 文本方式调用工具（流式）→ 文本方式（非流式）重试同一轮；都不行才报错，
  报错写出结束原因（`length` 提示输出上限，`content_filter`/`safety` 提示内容审核）和回复开头 160 字。
- 回复是网页（`<` 开头，多半是 Base URL 少了 `/v1`）时不重试，直接提示检查 Base URL。
- 429 按 `Retry-After` 或 2/5/10 秒重试三次；连接中断（无 HTTP 状态）的一轮重发最多 2 次。

## 中转站（开发者用的灵算 `https://lingsuan.top/v1`，2026-10-07 实测）

- `gemini-3-flash`：对话、工具调用、流式、`reasoning_effort` 正常；端到端一题 27 次调用、约 38 万输入 token、3.5 分钟。
  它名义上是 Gemini 3 Flash，经中转无法核实。
- `gemini-3.5-flash` 上游 404；`gemini-3.7-flash` 不存在（只有 -low/-medium/-high）；`gemini-3.6-flash`、`3.7-flash-*` 常把英文思考摘要写进 `content`
  （中转站的问题，App 不过滤）。

## 向量服务

- 默认百炼 `https://dashscope.aliyuncs.com/compatible-mode/v1`，`qwen3.7-text-embedding`，512 维。实测 0.706 token/字。
- 并发 ≥5 不被限流。

## 测试

- 离线：`test/core/llm/openai_client_test.dart` 覆盖以上全部怪癖（mock HTTP）。
- 真实：`test/live/ask_pipeline_live_test.dart`、`concurrency_probe_live_test.dart`，按 CLAUDE.md 的成本约束、开发者同意后才跑。

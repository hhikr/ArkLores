# R3 设计决策：AI 检索优化阶段 P1 的三个设计补充点

> 决策日期：2026-08-24
> 决策人：项目负责人（经选型分析后逐项确认）
> 依据：`docs/FEASIBILITY_ANALYSIS.md` §2.4 的三个补充设计点 + 本回合选型分析。
> 本文档是 R3（P1 跨章节推理）实现的契约依据；实现细节与 QA 记录见
> `R3_INVESTIGATION_LAYER_SUMMARY.md`。
>
> 状态：四项决策已全部在 R3 核心实现中落地（2026-08-24），实现方式见各节末尾
> "落地"标注；UI 接线与真实谜题 QA 列入 R3b。

## 决策 1：工具观察的机器可读契约 —— 结构化 JSON 块

**决定**：P1 新工具（`find_detail_echoes` / `collect_suspect_evidence` 及 P0 三个工具
的补充标记）在观察文本尾部输出 `DATA: <json>` 块；transform 优先解析 JSON，解析失败
时回退文本标记（容错）。JSON 由**工具**生成（非模型），格式可靠性由代码保证。

**理由**：P1 证据链校验需要结构化数据（嫌疑人列表、每候选的证据集、行级引用列表），
JSON 表达力与解析健壮性优于正则文本；`validateCoverageReport` 等既有文本标记逻辑
保留不动，避免回归。

**契约约定**：
- 每个工具观察的 `DATA:` 块是最后一个顶层字段，单行 JSON（压缩）或缩进 JSON 均可，
  由 `GameDataObservationData` 解析器统一处理；
- `DATA:` 块出现解析失败时，transform 使用文本标记回退（如 `Coverage Count:`），
  保证旧格式/异常格式不崩溃；
- 新工具必须同时保持人类可读正文（模型阅读用）与 `DATA:` 块（代码校验用）。

## 决策 2：上下文预算策略 —— 静态上限 + 观察历史裁剪

**决定**：组合方案 D。
1. **静态上限（prompt + 工具约束）**：每次调查最多精读 N 个章节（默认 3）、每章最多
   M 页（默认 3 页，`max_lines` 上限）；超限时工具返回"调查预算耗尽，建议聚焦以下
   章节"引导，并在 `DATA:` 块标记 `budget_exhausted`，明确这不是证据不足。
2. **观察历史裁剪（ReActLoop）**：`loopMessages` 中保留最近 K 条完整 Observation
   （默认 8），更旧的 Observation 消息替换为占位文本（`Observation: [历史观察已裁剪]`）；
   最终 transform 的校验仍基于**完整 observations 快照**（`_finalizeAnswer` 传入），
   裁剪只影响模型可见历史，不影响代码级校验。

**理由**：静态上限保证成本可预测与确定性出口；历史裁剪从根上控制上下文增长；
transform 快照与 loopMessages 解耦，裁剪无校验副作用。运行时章节摘要压缩（决策 B）
被否决：摘要会丢失伏笔细节，对侦探类任务风险最高。

## 决策 3：实体覆盖边界 —— speaker 扩展落地 + 词频挖掘入 P2

**决定**：组合方案 D。
1. **P1 落地（确定性）**：`StoryCoverageBuilder` 增加 speaker 名扩展——从
   `story_lines.speaker` 提取出现次数 ≥ 阈值（默认 ≥ 3 行）的说话人；若该名字在
   `entities` 表中不存在，则创建轻量实体（`id='speaker:<name>'`，
   `entity_type='speaker'`，`source_type='story_speaker'`，含 canonical alias），
   加入 trie 使 `entity_story_mentions` 覆盖有台词 NPC；正式实体优先，不重复创建。
2. **P2 立项（门禁）**：词频挖掘候选实体（高频人名模式）与组织/概念实体合并为
   P2 数据工程，走固定 QA 门禁。
3. **已知边界**：艺术化指称（"那个女人"、代词回指等）任何确定性方案无法覆盖，
   写入 `KNOWN_LIMITATIONS_AND_DEBT.md`，由多候选对比 + 置信度 + 替代解读兜底。

**理由**：speaker 扩展确定性、零模型成本，与 R1 的 speaker+content 扫描天然衔接，
补上"有台词 NPC"的最大覆盖缺口；词频挖掘噪声与质量成本不适合混入 P1。

## 决策 4：单次调查成本 —— 无步数上限（安全网兜底）

**决定（2026-08 修订，取代原"固定预算"）**：任何 AI 服务都不限制推理步数，
让 Agent 一直推理到给出最终回答为止。`ReActLoop` 不再接受 `maxIterations`；
仅保留可注入的 `safetyMaxIterations`（默认 1000）作为防失控安全网，超过时记日志
并走兜底回答路径。`stepMaxTokens=4096`、`minimumToolCalls>=4` 保留；
`RETRIEVAL_QA.md` 记录单次调查的调用次数与 token 量级（随真实用例 QA 补测）。

**理由**：固定 12 轮在真实长线调查中会提前耗尽预算，模型被迫把未完成的分析
作为"最终回答"输出（真机日志复现：12 轮耗尽后返回 Action 文本）；移除上限后
成本改为由观察历史裁剪（决策 2）与上下文预算（决策 3）兜底，而非硬性截断推理。

---

## 关联实现要点（R3 落地清单）

1. `StoryCoverageBuilder`：speaker 名扩展（频次阈值 + 去重 + 轻量实体写入）。
2. 新工具 `find_detail_echoes`：特征词提取（排除实体名/别名、停用字符、标点、数字；
   用 `rare_terms` 做 IDF），`story_lines_fts` 检索（<3 字符词 LIKE 回退），返回
   term/story_id/行号/snippet + `DATA:` 块。
3. 新工具 `collect_suspect_evidence`：经 `entity_story_mentions` 返回实体全部出场行，
   按 scope 分组、分页 + `DATA:` 块。
4. `StoryInvestigationAgent`：S0–S8 阶段协议（门槛由 transform 代码级校验）；
   预算见决策 4 修订（无步数上限；R8 起已迁移 Planner 三角色架构，见
   `AI_REFACTOR_SUMMARY.md`）。
5. `validateInvestigationVerdict` transform：culprit 门槛（S6）、证据链行级
   provenance、已读范围报告比对；`DATA:` 优先、文本回退。
6. ReActLoop 观察历史裁剪（决策 2 的 K 值默认 8，可配；R6 起由分层记忆取代）。
7. UI：证据卡扩展"证据链"与"已读范围"条目（§5.4）。
8. QA：合成 fixture（伏笔/误导/揭示三要素）+ 门槛测试（虚构已读/未达 S6 的 culprit
   拒绝）+ 回归全绿。

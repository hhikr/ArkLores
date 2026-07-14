# ArkLores GameData Source Discovery

> 目标：在不假设数据源已定的前提下，为《明日方舟》与《明日方舟：终末地》分别选出可长期维护的 GameData 来源。

## 硬性要求

- GameData 来源必须是社区解包仓库。
- ArkLores 不直接把社区仓库原始目录作为 App 数据源。
- ArkLores 构建自己的 SQLite 知识库，数据库必须包含：
  - 游戏原文 / 结构化文本
  - FTS 可检索文本
  - chunk embedding 向量
  - manifest / source snapshot metadata
- 生成物和 APK 一起放进 GitHub Release。

## 当前事实

- 当前代码运行时仍以 v0.3 的 Wiki / Book 本地库为底层兼容数据源。
- `search_local_lore` 目前只是过渡抽象，不是已完成的 GameData structured lookup。
- v0.4.5 的中文 GameData 主库尚未接入。

## 已确认的现状边界

### 明日方舟

- 现有 app 侧仍有 PRTS / Warfarin 爬虫与 seed 构建逻辑。
- 这条链路适合做临时兼容层，不适合作为长期 GameData 主源。
- 需要重新确认可用的解包来源、版本更新方式和许可边界。

### 终末地

- 当前仓库没有真正的 GameData 导入管线。
- 现有实现仅覆盖 wiki-style 内容抓取的旧原型思路。
- 需要先确认是否存在稳定、可自动化、可持续更新的数据来源。

## 选型标准

1. 可自动化获取。
2. 可稳定版本化。
3. 适合中文优先。
4. 可映射为结构化 schema。
5. 允许 release asset 分发。
6. 维护成本可控。
7. 许可风险可接受。

## 候选来源类型

### A. 社区解包仓库

- 优点：最接近原始文本，覆盖面通常最好。
- 风险：解析成本高，版本变动频繁。
- 适合：最终 GameData 主库。

### B. 社区整理数据集

- 优点：更容易直接消费。
- 风险：来源透明度和更新频率不稳定。
- 适合：过渡阶段或补充验证。

### C. Wiki / 文本缓存

- 优点：现成可用。
- 风险：不应继续作为长期主源。
- 适合：fallback / 补充。

## 推荐执行顺序

1. 先使用《明日方舟》社区解包仓库跑通完整 DB 构建闭环。
2. 用同一套中间层 schema 试跑最小闭环。
3. 再接入《终末地》候选仓库。
4. 构建产物统一进入 ArkLores GitHub Release。

## 已锁定候选

### 明日方舟

首选：

- Repo: `Kengxxiao/ArknightsGameData`
- URL: `https://github.com/Kengxxiao/ArknightsGameData`
- Branch: `master`
- 说明：社区维护的《明日方舟》游戏数据仓库，README 标明基于 `OpenArknightsFBS` 解析部分数据。
- 最近状态：GitHub metadata 显示 2026-07 仍有更新。
- 可用中文路径：
  - `zh_CN/gamedata/excel/character_table.json`
  - `zh_CN/gamedata/excel/handbook_info_table.json`
  - `zh_CN/gamedata/excel/charword_table.json`
  - `zh_CN/gamedata/excel/item_table.json`
  - `zh_CN/gamedata/excel/story_table.json`
  - `zh_CN/gamedata/story/**/*.txt`
- 适配优先级：最高，先用它跑通 ArkLores GameData DB v1。

### 终末地

候选 A：

- Repo: `wuyilingwei/EndfieldGameData`
- URL: `https://github.com/wuyilingwei/EndfieldGameData`
- Branch: `main`
- 说明：社区解包结果仓库，包含 `TableCfg/*.json` 和 `VFBlockMainInfo/*.json`。
- 风险：README 标明是技术测试一测数据，仓库已 archived，不适合作为长期唯一来源。
- 可用中文路径：
  - `TableCfg/I18nTextTable_CN.json`
  - `TableCfg/Character.json`
  - `TableCfg/Dialog.json`
  - `TableCfg/PrtsDocument.json`
  - `TableCfg/Item.json`

候选 B：

- Repo: `3aKHP/EndFieldGameData`
- URL: `https://github.com/3aKHP/EndFieldGameData`
- Branch: `main`
- 说明：面向 release asset 的 text-only JSON tables 镜像；README 写明通过 GitHub Releases 发布 `endfield-tables.zip`。
- 优点：有 manifest、release asset、SHA-256、结构清楚。
- 风险：覆盖面偏 mechanics / lookup，剧情原文覆盖需继续验证。
- 适配优先级：作为第二阶段候选，先确认是否有足够 lore / story text。

## 初步决策

1. v0.4.5 首个闭环只做《明日方舟》中文 GameData。
2. 首选源为 `Kengxxiao/ArknightsGameData`。
3. 终末地不阻塞 v0.4.5；等明日方舟管线稳定后再接。
4. 终末地优先评估 `3aKHP/EndFieldGameData` release asset，如果剧情覆盖不足，再评估 `wuyilingwei/EndfieldGameData` 的 raw table。

## 下一步产出

- 数据源对照表
- 风险与许可备注
- 首个可导入样本
- schema 映射草案
- release asset 打包方案

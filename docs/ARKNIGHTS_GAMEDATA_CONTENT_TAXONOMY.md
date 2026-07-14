# Arknights GameData Content Taxonomy

> 本文档定义《明日方舟》社区解包数据进入 ArkLores 前的内容普查、分类枚举和分块原则。

## 核心原则

不能按“我们已经想到的几个类别”直接写 importer。解包数据必须先经过普查和归一化：

1. 遍历仓库文件树。
2. 找出所有含中文文本、剧情、档案、描述、语音、回顾、活动说明的来源。
3. 建立层级分类枚举。
4. 将原始 JSON / txt 转成 normalized records。
5. 再从 normalized records 生成 chunk。

## 枚举设计

枚举需要同时支持两种形态：

- 层级路径：便于表达包含关系。
- 扁平 `content_type`：便于 SQLite 过滤、FTS、agent tool 参数和测试。

例如：

```text
roguelike
  monthly_squad
  monthly_record
  ending
  ending_story
  collectible
  stage
  event
  topic_mechanic
```

落库时可同时保存：

```text
content_category = "roguelike"
content_subtype = "monthly_record"
content_type = "roguelike_monthly_record"
```

## 建议顶层分类

### `operator`

包含：

- `operator_basic_profile`
- `operator_handbook_profile`
- `operator_voice`
- `operator_record_story`
- `operator_module`
- `operator_skin`

主要来源：

- `excel/character_table.json`
- `excel/handbook_info_table.json`
- `excel/charword_table.json`
- `excel/uniequip_table.json`
- `excel/skin_table.json`
- `story/obt/memory/*.txt`

### `story`

包含：

- `main_story`
- `activity_story`
- `side_story`
- `mini_story`
- `tutorial_story`
- `story_review`
- `record_story`

主要来源：

- `story/obt/main/**/*.txt`
- `story/activities/**/*.txt`
- `story/obt/record/**/*.txt`
- `excel/story_table.json`
- `excel/story_review_table.json`
- `excel/story_review_meta_table.json`

### `roguelike`

包含：

- `roguelike_topic`
- `roguelike_ending`
- `roguelike_ending_story`
- `roguelike_monthly_squad`
- `roguelike_monthly_record`
- `roguelike_collectible`
- `roguelike_stage`
- `roguelike_zone`
- `roguelike_event`
- `roguelike_mechanic`

主要来源：

- `excel/roguelike_table.json`
- `excel/roguelike_topic_table.json`
- `story/obt/rogue/**/*.txt`
- `story/obt/roguelike/**/*.txt`
- `levels/activities/act*d6/level_rogue*.json`

### `world_item`

包含：

- `item_description`
- `material_description`
- `collectible_description`
- `medal_description`
- `skin_description`
- `module_description`

主要来源：

- `excel/item_table.json`
- `excel/medal_table.json`
- `excel/skin_table.json`
- `excel/uniequip_table.json`
- `excel/battle_equip_table.json`

### `enemy`

包含：

- `enemy_profile`
- `enemy_race`
- `enemy_level_data`

主要来源：

- `excel/enemy_handbook_table.json`
- `bakemuzzledata/enemy/*.json`

### `stage`

包含：

- `stage_description`
- `zone_description`
- `campaign_description`
- `activity_zone_description`
- `tutorial_stage_description`

主要来源：

- `excel/stage_table.json`
- `excel/zone_table.json`
- `excel/campaign_table.json`
- `levels/**/*.json`

### `activity`

包含：

- `activity_basic_info`
- `activity_mission`
- `activity_rule`
- `activity_reward`
- `activity_archive`

主要来源：

- `excel/activity_table.json`
- `excel/retro_table.json`
- `excel/mission_table.json`
- `story/activities/**/*.txt`

### `sandbox`

包含：

- `sandbox_story`
- `sandbox_ending`
- `sandbox_stage`
- `sandbox_item`
- `sandbox_event`
- `sandbox_mechanic`

主要来源：

- `excel/sandbox_table.json`
- `excel/sandbox_perm_table.json`
- `story/obt/sandboxperm/**/*.txt`
- `story/activities/act1sandbox/**/*.txt`
- `levels/activities/act1sandbox/**/*.json`

### `system_text`

包含：

- `worldview_tip`
- `loading_tip`
- `ui_text`
- `building_text`
- `base_skill_text`

主要来源：

- `excel/tip_table.json`
- `excel/main_text.json`
- `excel/init_text.json`
- `excel/building_data.json`

## 普查结果摘要

基于 `Kengxxiao/ArknightsGameData` 的 `zh_CN/gamedata` 快照：

- 全仓库文件数：10634
- 含中文文本文件数：5999
- `story/`: 5606 files, 5605 `.txt`
- `excel/`: 57 JSON files
- `levels/`: 3743 JSON files
- `bakemuzzledata/`: 702 JSON files
- `story_table.json`: 2368 entries
- `story_table.json` 与 `.txt` 大小写归一后缺失数：0

文本密集 JSON 文件前列：

- `roguelike_topic_table.json`
- `charword_table.json`
- `skill_table.json`
- `activity_table.json`
- `building_data.json`
- `stage_table.json`
- `character_table.json`
- `handbook_info_table.json`
- `main_text.json`
- `sandbox_perm_table.json`
- `enemy_handbook_table.json`
- `skin_table.json`
- `item_table.json`

全文件级 audit 的候选分类摘要：

| Category | Files | Notes |
|---|---:|---|
| `activity_story` | 1933 | 活动剧情文本 |
| `main_story` | 986 | 主线 / 教程 / 主线相关文本 |
| `operator_record_story` | 764 | 干员秘录和干员相关剧情文本 |
| `roguelike_story` | 250 | 肉鸽结局、月度记录、挑战等剧情文本 |
| `sandbox_story` | 255 | 生息演算相关剧情文本 |
| `operator` | 3 | 干员基础、档案、语音主表 |
| `roguelike` | 2 | 肉鸽主题结构化主表 |
| `world_item` | 5 | 物品、模组、皮肤、奖章等文本 |
| `enemy` | 1 | 敌人图鉴主表 |
| `stage` | 3 | 关卡、区域、战役文本 |
| `level` | 2853 | 大量关卡 JSON，少量含中文，需要进一步筛选 |
| `roguelike_level` | 557 | 肉鸽关卡 JSON，少量含中文 |
| `sandbox_level` | 333 | 生息演算关卡 JSON，少量含中文 |

注意：`levels/`、`bakemuzzledata/`、`building/`、`[uc]lua/` 不应默认排除。全文件 audit 显示：

- `levels/enemydata/enemy_database.json` 含大量敌人文本候选。
- `building_data.json` 含大量基建 / 技能 / UI 文本，部分可能是 lore 辅助资料。
- `skill_table.json`、`skin_table.json`、`medal_table.json` 也含高密度中文文本。
- `[uc]lua/` 中文文本极少，暂列人工复核，不进入首批 importer。

## 分块前的 Normalized Record

每个原始条目先转成 normalized record：

```text
record_id
game
language
category
subtype
content_type
entity_id
entity_name
parent_id
parent_type
title
section
speaker
content
source_path
raw_id
line_start
line_end
source_repo
source_commit
```

然后再生成 `lore_chunks`。

## 层级关系

需要显式保存包含关系，不只靠字符串路径猜：

```text
activity -> stage
activity -> story
activity -> item
operator -> voice
operator -> profile
operator -> record_story
roguelike_topic -> monthly_squad
roguelike_topic -> ending
roguelike_topic -> collectible
roguelike_topic -> stage
sandbox_activity -> sandbox_stage
sandbox_activity -> sandbox_story
enemy_race -> enemy
zone -> stage
```

建议表：

```sql
CREATE TABLE entity_relations (
  id              TEXT PRIMARY KEY,
  source_entity_id TEXT NOT NULL,
  target_entity_id TEXT NOT NULL,
  relation_type  TEXT NOT NULL,
  source_path    TEXT,
  raw_id         TEXT
);
```

## Agent 使用方式

Agent 不应该直接搜所有 chunk。推荐流程：

1. 先查 `entities` / alias。
2. 根据实体类型查关系。
3. 按 `content_type` 优先级取结构化资料。
4. 再用 FTS 查局部文本。
5. 最后用向量补充召回。

例如“凯尔希梗概”：

```text
operator entity
  -> operator_profile
  -> operator_voice
  -> operator_record_story
  -> story_dialogue where speaker = 凯尔希
  -> related factions / activities
```

例如“肉鸽第五主题结局”：

```text
roguelike_topic rogue_5
  -> roguelike_ending
  -> roguelike_ending_story
  -> roguelike_monthly_record
  -> roguelike_collectible
```

## 后续任务

1. 先完成全文件 audit 人工复核，不直接扩 importer。
2. 将文件标注为 `core` / `candidate` / `low` / `exclude`。
3. 扩展 builder：先产 normalized records。
4. 为每个来源文件写 adapter，而不是直接写 chunks。
5. 增加 content taxonomy smoke test。
6. 增加 coverage report：每次构建输出每类记录数量。
7. importer 覆盖后再接 `search_local_lore`。

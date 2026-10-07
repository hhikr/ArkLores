/// 0.12: how the Endfield knowledge base is arranged (part of
/// [loreGamesGuide]). Derived from the build's own structure
/// (`build/endfield/`); names no character, place or event.
library;

const String loreEndfieldLibraryGuide = '''
终末地库的结构（与明日方舟库的不同之处）
- 剧情：story_lines 里每个 story_id 是一段对话 ef/<对话 id>.txt。对话 id 的前缀说明种类：dlg_ 是剧情对话，radio_ 是通讯，sns_ 是短信。
  同一任务的对话归在一个集合（collections.id 形如 ef/mission_<任务 id>，name 是任务名），任务按游戏任务面板的分类归在书架下：collections.kind 为 ef/main 主线任务、ef/discovery 探索任务、ef/side 支线任务、ef/activity 活动任务、ef/other 委派任务；
  干员自己的任务、与干员的短信话题和礼物对话 kind 为 ef/memory，parent_id 指向该干员；地图上可交互物件的文字和敌人遭遇时的通讯 kind 为 ef/world，
  按地点或敌人归组（collections.name 是地点名或敌人名）。story_catalog 的 collection_type 是 EF_MAIN、EF_SIDE 等，synopsis 是游戏给的对话摘要（只作定位）；
  entries.type = mission_intro 是任务自己的简介。同一任务内对话的先后按 story_catalog.story_sort。
- 主角“管理员”的台词在游戏里分男女两种写法，库里只收一种；“管理员”在原文里也是其他角色对主角的称呼。
- 干员（entries.type = operator，id 形如 operator:ef/chr_…）：档案（基础档案、人事简述、档案资料）和语音，原文在 normalized_records。
- 档案库（ef/archive 书架，entries.type = document）：游戏内收集到的文件、纸张、记录、媒体，每条一份文档，原文在 normalized_records，可作出处；
  investigation 是一项调查及其线索，part_of 把调查涉及的文档连到它。
- 图鉴：敌人（enemy）、武器（weapon）、物品（item）的描述文字，是设定与背景，常交代来历和与事件的关系。
- 终末地库没有关卡、活动档案、肉鸽等明日方舟特有的表；没有剧情向量时 find 只做关键词检索。''';

/// 0.12: how the Endfield knowledge base is arranged (part of
/// [loreGamesGuide]). Derived from the build's own structure
/// (`build/endfield/`); names no character, place or event.
library;

const String loreEndfieldLibraryGuide = '''
终末地库的结构（与明日方舟库的不同之处）
- 剧情：一个任务是一篇剧情 ef/<任务 id>.txt（地图上一处地点的交互文字、一种敌人遭遇时的通讯、一个短信话题也各是一篇），任务里的每段对话都以一行 kind = 'section' 开头，
  这一行的内容是这段的种类：对话（剧情对话）、通讯、远程通话、闲话（角色在玩家身边说的话，说话人多半不明）、短信。一篇里先是全部对话，再是通讯、远程通话、闲话、短信，
  每种按游戏的编号排；不同种类之间谁先谁后游戏数据没有给出，不要从行号推断两段不同种类的内容的先后。kind = 'choice' 是玩家的选项：
  一行里用“／”隔开的是同一处的几个选项；单独一个选项的行后面紧跟的是选它之后的回应，几个选项依次排开后剧情从汇合处接着往下。
  任务所在的集合 collections.id 形如 ef/mission_<任务 id>，name 是任务名；任务按游戏任务面板的分类归在书架下：collections.kind 为 ef/main 主线任务、ef/discovery 探索任务、ef/side 支线任务、ef/activity 活动任务、ef/other 委派任务；
  干员自己的任务、与干员的短信话题和礼物对话 kind 为 ef/memory，parent_id 指向该干员；地点的交互文字和敌人遭遇的通讯 kind 为 ef/world（collections.name 是地点名或敌人名）。
  story_catalog 的 collection_type 是 EF_MAIN、EF_SIDE 等，synopsis 是游戏给这个任务各段对话的摘要（只作定位）；entries.type = mission_intro 是任务自己的简介，group_name 是任务所在的地区。
- 主角“管理员”的台词在游戏里分男女两种写法，库里只收一种；“管理员”在原文里也是其他角色对主角的称呼。
- 干员（entries.type = operator，id 形如 operator:ef/chr_…）：档案（基础档案、人事简述、档案资料）和语音，原文在 normalized_records。
- 档案库（ef/archive 书架，entries.type = document）：游戏内收集到的文件、纸张、记录、媒体，每条一份文档，原文在 normalized_records，可作出处；
  investigation 是一项调查及其线索，part_of 把调查涉及的文档连到它。
- 图鉴：敌人（enemy，含分布地点）、武器（weapon）、物品（item）的描述文字，是设定与背景，常交代来历和与事件的关系；关卡（stage，各种副本）有一句简介，
  敌人 appears_in 关卡；邮件（mail）是角色寄来的信。
- 文档（document）除档案库外，还有任务里、地图上读到的留言与告示，归在所在任务或地点的集合里；entries.group_name 是所在地区（按游戏的地区表）。
- 终末地库没有关卡、活动档案、肉鸽等明日方舟特有的表；没有剧情向量时 find 只做关键词检索。''';

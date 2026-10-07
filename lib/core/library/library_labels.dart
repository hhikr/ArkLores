/// Display names of the knowledge base's own vocabulary: entry types and
/// bindings. The game text is Chinese, so these are too.
library;

import 'library_queries.dart';

/// Chinese name of an entry type (the type itself when unknown).
String entryTypeName(String type) => switch (type) {
      'story' => '剧情',
      'operator' => '干员',
      'token' => '召唤物',
      'trap' => '装置',
      'npc' => '人物',
      'power' => '势力',
      'operator_stage' => '悖论模拟',
      'enemy' => '敌人',
      'stage' => '关卡',
      'zone' => '章节',
      'item' => '物品',
      'skin' => '皮肤',
      'skin_brand' => '皮肤系列',
      'module' => '模组',
      'medal' => '奖章',
      'charm' => '标志物',
      'mail' => '邮件',
      'worldview' => '世界观',
      'home_theme' => '界面主题',
      'activity' => '活动',
      'activity_text' => '活动文本',
      'sandbox_item' => '物品',
      'sandbox_text' => '生息演算文本',
      'sandbox_stage' => '关卡',
      'sandbox_topic' => '概述',
      'sandbox_act' => '篇章',
      'sandbox_event' => '事件',
      'roguelike_item' => '收藏品',
      'roguelike_scene' => '事件',
      'roguelike_choice' => '事件选项',
      'roguelike_ending' => '结局',
      'roguelike_stage' => '关卡',
      'roguelike_zone' => '区域',
      'roguelike_topic' => '概述',
      'roguelike_tip' => '注释',
      'roguelike_prize' => '稀有奖励',
      // Named by its groups where they have names (see the topic page).
      'roguelike_buff' => '特殊设定',
      'roguelike_squad' => '月度小队',
      'archive_log' => '行动日志',
      'archive_landmark' => '地标',
      'archive_book' => '书籍',
      'archive_file' => '档案文件',
      'archive_news' => '新闻',
      'archive_avg' => '档案剧情',
      // 0.12: Endfield (the PRTS archive's terms as the game names them).
      'weapon' => '武器',
      'document' => '档案',
      'investigation' => '调查',
      _ => _familyName(type),
    };

/// What a type nobody has named yet is called: the family its id says
/// (`roguelike_…`, `sandbox_…`, `archive_…`), else the id itself, so a table
/// a later build adds is shown and never breaks a page. The order of names:
/// the name the game or the wiki gives (the switch above), the family, the id.
String _familyName(String type) {
  for (final (prefix, name) in const [
    ('roguelike_', '集成战略资料'),
    ('sandbox_', '生息演算资料'),
    ('archive_', '档案资料'),
    ('activity_', '活动资料'),
  ]) {
    if (type.startsWith(prefix)) return name;
  }
  return type;
}

/// Types whose `code` is the game's own serial number of the character
/// (`RCX7`), not a stage code: it is said as "编号", after the name.
const Set<String> numberedTypes = {'operator', 'token', 'trap', 'npc'};

/// The code of an entry as it is shown, or null when it is not for the
/// reader: `编号 RCX7` for characters, the code itself for stages.
String? codeCaption(LibraryEntry entry) {
  final code = entry.code;
  if (code == null || code.isEmpty) return null;
  return numberedTypes.contains(entry.type) ? '编号 $code' : code;
}

/// How an entry reads in a list: `代号 名称`, or just the name. A
/// character's serial number does not lead its name.
String entryHeadline(LibraryEntry entry) {
  final name = entry.name.isEmpty ? entry.id : entry.name;
  final code = entry.code;
  if (code == null ||
      numberedTypes.contains(entry.type) ||
      name.startsWith(code)) {
    return name;
  }
  return '$code  $name';
}

/// The order of an entry type among a collection's related texts: what tells
/// the story of the set first (endings, squads), the long lists of items,
/// events and choices last. Unknown types go after the known ones.
int typeRank(String type) {
  const order = [
    'roguelike_topic',
    'sandbox_act',
    'roguelike_ending',
    'roguelike_squad',
    'roguelike_zone',
    'roguelike_stage',
    'roguelike_item',
    'roguelike_buff',
    'roguelike_scene',
    'roguelike_tip',
    'roguelike_prize',
    'sandbox_stage',
    'sandbox_event',
    'sandbox_item',
  ];
  final i = order.indexOf(type);
  return i < 0 ? order.length : i;
}

/// A group heading as the reader sees it. Groups the tables give in Chinese
/// (stage zones, story squads, brands) pass through; the game's own codes
/// (`TRADE`, `FOODMAT`) are named, and a code with no name is null: it is
/// not shown rather than shown raw.
String? groupLabel(String type, String? raw) {
  final g = raw?.trim() ?? '';
  if (g.isEmpty) return null;
  // Anything with Chinese, spaces or punctuation is already a heading.
  if (RegExp(r'[^\x00-\x7F]|[ .:]').hasMatch(g)) return g;
  final key = g.toUpperCase();
  bool has(String s) => key.contains(s);
  switch (type) {
    // The names the wiki pages of each mode use. A kind nobody named has no
    // heading rather than an invented one.
    case 'roguelike_item':
      return switch (g.toLowerCase()) {
        'relic' => '藏品',
        'capsule' => '剧目',
        'totem' => '密文板',
        'explore_tool' => '调查装备',
        'fragment' => '思绪',
        'copper' => '通宝',
        'legacy' => '黄色襁褓生灵',
        'start' => '蓝色襁褓生灵',
        'scrap' => '零件',
        'character' => '干员',
        _ => null,
      };
    case 'roguelike_buff':
      // Named when built; the old table keys are not names.
      return null;
    case 'medal':
      return switch (g) {
        'playerMedal' => '履历奖章',
        'stageMedal' => '章节奖章',
        'campMedal' => '剿灭奖章',
        'towerMedal' => '保全奖章',
        'growthMedal' => '成长奖章',
        'storyMedal' => '记录奖章',
        'buildMedal' => '基建奖章',
        'activityMedal' => '活动奖章',
        'rogueMedal' => '远行奖章',
        'hiddenMedal' => '加密奖章',
        _ => null,
      };
    case 'zone':
      return switch (key) {
        'MAINLINE' => '主线',
        'MAINLINE_ACTIVITY' => '主线活动',
        'MAINLINE_RETRO' => '主线复刻',
        'ACTIVITY' => '活动',
        'SIDESTORY' => 'SideStory',
        'BRANCHLINE' => '插曲',
        _ => null,
      };
    case 'npc':
      return switch (g.toLowerCase()) {
        'rhodes' => '罗德岛',
        'lungmen' => '龙门',
        _ => null,
      };
    case 'item':
      // Only the names the wiki's item pages use (材料, 活动道具, 货币,
      // 表情套组, 奖章); a kind nobody named has no heading.
      if (key == 'MATERIAL') return '材料';
      if (key.startsWith('ACTIVITY')) return '活动道具';
      if (has('COIN') || has('SHD') || key == 'GOLD' || has('DIAMOND')) {
        return '货币';
      }
      if (key == 'MEDAL') return '奖章';
      if (has('EMOTICON')) return '表情套组';
      return null;
    case 'sandbox_item':
      // Named by the table when built (its item types); the codes are not.
      return null;
    default:
      // Brands, authors, dates: names the tables give (a brand can be written
      // in Latin letters).
      return g;
  }
}

/// Chinese phrase for a binding, seen from the opened entry: [outgoing] is
/// true when the opened entry is the source of the binding.
String bindingName(
  String relation, {
  required bool outgoing,
  String? ownerType,
}) =>
    switch ((relation, outgoing)) {
      // A month squad features its protagonist.
      ('features', true) when ownerType == 'roguelike_squad' => '主角',
      ('part_of', true) => '属于',
      ('part_of', false) => '包含',
      ('appears_in', true) => '出现在',
      ('appears_in', false) => '出场',
      ('belongs_to', true) => '属于',
      ('belongs_to', false) => '包含',
      ('belongs_to_stage', true) => '所属关卡',
      ('belongs_to_stage', false) => '关卡剧情',
      ('leads_to', true) => '通向',
      ('leads_to', false) => '来自',
      ('features', true) => '涉及',
      ('features', false) => '出现于',
      // Two operators that are one person: the alternate points at the
      // original, both ways read the same.
      ('same_person', _) => '同一人物',
      ('summoned_by', true) => '召唤者',
      ('summoned_by', false) => '召唤物',
      ('reads_story', true) => '阅读剧情',
      ('reads_story', false) => '收录于',
      // A relation of a later build: said plainly, not as its id.
      (_, _) => '相关',
    };

/// 0.12: names of the Endfield shelves (collection kinds without the `ef/`
/// namespace) where they differ from the Arknights ones. As in-game terms.
const Map<String, String> endfieldShelfNames = {
  'main': '主线',
  'side': '支线任务',
  'character': '干员任务',
  'event': '活动',
  'world': '世界',
  'archive': '档案库',
  'memory': '干员',
};

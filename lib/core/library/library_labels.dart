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
      'module' => '干员模组',
      'medal' => '勋章',
      'charm' => '护符',
      'mail' => '邮件',
      'worldview' => '世界观',
      'home_theme' => '界面主题',
      'activity' => '活动',
      'activity_text' => '活动文本',
      'sandbox_item' => '生息演算物品',
      'sandbox_text' => '生息演算文本',
      'roguelike_item' => '收藏品',
      'roguelike_scene' => '事件',
      'roguelike_choice' => '事件选项',
      'roguelike_ending' => '结局',
      'roguelike_stage' => '关卡',
      'roguelike_zone' => '区域',
      'roguelike_topic' => '概述',
      'roguelike_tip' => '背景词条',
      'roguelike_prize' => '奖励',
      'roguelike_buff' => '加成',
      'roguelike_squad' => '月度小队',
      'archive_log' => '探索记录',
      'archive_landmark' => '地标',
      'archive_book' => '书籍',
      'archive_file' => '档案文件',
      'archive_news' => '新闻',
      'archive_avg' => '档案剧情',
      _ => type,
    };

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
    'roguelike_ending',
    'roguelike_squad',
    'roguelike_zone',
    'roguelike_stage',
    'roguelike_item',
    'roguelike_buff',
    'roguelike_scene',
    'roguelike_tip',
    'roguelike_prize',
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
    case 'roguelike_item':
      return switch (g.toLowerCase()) {
        'relic' => '藏品',
        'capsule' => '胶囊',
        'totem' => '图腾',
        'totem_effect' => '图腾效果',
        'explore_tool' => '探索工具',
        'fragment' => '碎片',
        'custom_ticket' => '票券',
        'divination_kit' => '占卜工具',
        'copper' => '铜钱',
        'copper_buff' => '铜钱效果',
        'legacy' => '遗产',
        'scrap' => '废料',
        'character' => '干员',
        _ => null,
      };
    case 'roguelike_choice':
      final base = key
          .replaceAll(RegExp(r'_(ALL|PROB_SHOW|PROB|SHOW)$'), '');
      return switch (base) {
        'TRADE' => '交易',
        'NEXT' => '前进',
        'LEAVE' => '离开',
        'WISH' => '祈愿',
        'SACRIFICE' || 'SACRIFICE_TOTEM' => '献祭',
        'TELEPORT' => '传送',
        'EXPEDITION' || 'EXPEDITION_RETURN' => '远征',
        'USE_STASHED_TICKET' => '使用票券',
        'ITEM_REROLL' => '重掷',
        'JUMP' => '跳转',
        'PACIFY_WRATH' => '安抚',
        'ITEM_TOP_UP' => '补充',
        'GILD_COPPER' => '镀金铜钱',
        'ZONE_END' => '区域结束',
        'MOVE' => '移动',
        'VISION' => '视野',
        'SCRAP_PAY' => '支付废料',
        _ => null,
      };
    case 'roguelike_buff':
      return switch (g) {
        'charBuffData' => '干员加成',
        'squadBuffData' => '分队加成',
        'variationData' => '变奏',
        _ => null,
      };
    case 'medal':
      return switch (g) {
        'activityMedal' => '活动勋章',
        'storyMedal' => '剧情勋章',
        'rogueMedal' => '集成战略勋章',
        'growthMedal' => '成长勋章',
        'stageMedal' => '关卡勋章',
        'buildMedal' => '基建勋章',
        'campMedal' => '阵营勋章',
        'hiddenMedal' => '隐藏勋章',
        'playerMedal' => '玩家勋章',
        _ => null,
      };
    case 'zone':
      return switch (key) {
        'MAINLINE' => '主线',
        'MAINLINE_ACTIVITY' => '主线活动',
        'MAINLINE_RETRO' => '主线复刻',
        'ACTIVITY' => '活动',
        'SIDESTORY' => '支线',
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
      if (has('MATERIAL')) return '材料';
      if (key.startsWith('ACTIVITY')) return '活动道具';
      if (key.startsWith('AP_')) return '理智与补给';
      if (has('TKT') || has('VOUCHER')) return '凭证与券';
      if (has('COIN') || has('SHD') || key == 'GOLD' || has('DIAMOND')) {
        return '货币';
      }
      if (has('PACK') || has('GIFT')) return '补给包';
      if (has('EXP')) return '经验';
      if (key == 'PLOT_ITEM') return '剧情道具';
      if (key == 'MEDAL') return '勋章';
      if (has('EMOTICON')) return '表情';
      if (key == 'UNI_COLLECTION') return '收藏品';
      return null;
    case 'sandbox_item':
      if (has('BUILDINGMAT') || has('SPECIALMAT') || key == 'PRODUCT' || key == 'CRAFT') {
        return '材料与制作';
      }
      if (has('BUILDING')) return '建筑';
      if (has('FOOD') || has('COOKBOOK')) return '食物';
      if (key == 'TACTICAL' || key == 'BASETACTICAL') return '战术物资';
      if (has('RECIPE')) return '配方';
      if (has('ANIMAL') || key == 'INSECT') return '动物与昆虫';
      if (has('RELIC')) return '藏品';
      if (has('COIN') || key == 'GOLD' || key == 'CURRENCY') return '货币';
      return null;
    default:
      // Brands, authors, dates: names the tables give.
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
      ('reads_story', true) => '阅读剧情',
      ('reads_story', false) => '收录于',
      (_, true) => relation,
      (_, false) => relation,
    };

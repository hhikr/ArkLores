/// Display names of the knowledge base's own vocabulary: entry types and
/// bindings. The game text is Chinese, so these are too.
library;

import 'library_queries.dart';

/// Chinese name of an entry type (the type itself when unknown).
String entryTypeName(String type) => switch (type) {
      'story' => '剧情',
      'operator' => '干员档案',
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
      'roguelike_item' => '集成战略收藏品',
      'roguelike_scene' => '集成战略事件',
      'roguelike_choice' => '集成战略选项',
      'roguelike_ending' => '集成战略结局',
      'roguelike_stage' => '集成战略关卡',
      'roguelike_zone' => '集成战略区域',
      'roguelike_topic' => '集成战略概述',
      'roguelike_tip' => '集成战略提示',
      'roguelike_prize' => '集成战略奖励',
      'roguelike_buff' => '集成战略加成',
      'roguelike_squad' => '集成战略分队',
      'archive_log' => '探索记录',
      'archive_landmark' => '地标',
      'archive_book' => '书籍',
      'archive_file' => '档案文件',
      'archive_news' => '新闻',
      'archive_avg' => '档案剧情',
      _ => type,
    };

/// How an entry reads in a list: `代号 名称`, or just the name.
String entryHeadline(LibraryEntry entry) {
  final name = entry.name.isEmpty ? entry.id : entry.name;
  final code = entry.code;
  if (code == null || name.startsWith(code)) return name;
  return '$code  $name';
}

/// Chinese phrase for a binding, seen from the opened entry: [outgoing] is
/// true when the opened entry is the source of the binding.
String bindingName(String relation, {required bool outgoing}) =>
    switch ((relation, outgoing)) {
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

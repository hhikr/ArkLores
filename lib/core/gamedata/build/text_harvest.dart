/// Text extraction helpers of the entry importer (0.11).
///
/// The old importer copied every field whose key was on a fixed whitelist
/// (`name`, `description`, `usage`, …) into one row per field. That lost the
/// narrative stored under other keys (news, letters, event text …) and kept
/// gameplay text (effects, rules, how to obtain). The helpers here decide
/// what to keep from the *content and the path*, never from a story, an
/// activity or a character:
///
/// - [isMechanical]: text that states numbers or effects (gameplay);
/// - [harvestNarrative]: walks a subtree and keeps prose and the text under
///   narrative keys (news, dialog, event, letter …), dropping the text under
///   gameplay keys (rule, task, reward, buff, shop …).
///
/// Everything is deterministic: the same source yields the same text.
library;

/// Rich-text markup: `<@x.y>`, `<$x.y>`, `</…>`, `<color=…>`, and the other
/// ASCII-only tags (`<newsimg/>`).
final RegExp _tag = RegExp(r'<[@$/][^>]*>|<[A-Za-z][^>一-鿿]*>');

/// A name the game writes between angle brackets (`<热泵通道>`): it is text,
/// only the brackets go.
final RegExp _bracketedName = RegExp(r'<(?![\d\s=])([^<>\n]*[一-鿿][^<>\n]*)>');
final RegExp _cjk = RegExp(r'[一-鿿]');
final RegExp _mechanicalWords = RegExp(
  r'(攻击力|攻击速度|生命上限|最大生命|生命值|防御力|法术抗性|每秒|部署费用|技力|冷却|阻挡数|'
  r'提升|降低|增加|减少|恢复|获得|消耗|持续|概率|额外|可携带|解锁|通关|累计|完成|击败|'
  r'敌方|我方|友方|造成|触发|施放|层数|回合|部署|撤退|技能|特性|天赋|伤害|提供|干员被|招募)',
);

/// Whether [text] has any Chinese character.
bool hasChinese(String text) => _cjk.hasMatch(text);

/// [value] without its rich-text markup. Only markup goes: a name between
/// angle brackets stays, without the brackets.
String stripMarkup(String value) {
  var text = value.replaceAll(_tag, '');
  // A name can be bracketed twice (`<<名字>>`).
  for (var again = true; again;) {
    final next = text.replaceAllMapped(_bracketedName, (m) => m.group(1)!);
    again = next != text;
    text = next;
  }
  return text;
}

/// Removes rich-text tags, turns literal `\n` into a newline and collapses
/// blanks. The text of a game table is stored with `<@tag>` markup.
String cleanRichText(String value) {
  return stripMarkup(value)
      .replaceAll(r'\n', '\n')
      .replaceAll(RegExp(r'[ \t　]+'), ' ')
      .replaceAll(RegExp(r'\n[ \t]+'), '\n')
      .trim();
}

/// Drops the lines of [value] that are gameplay hints (they carry the
/// `<@lv.` level-hint markup) and cleans the rest.
String cleanDescription(String value) {
  final kept = value
      .replaceAll(r'\n', '\n')
      .split('\n')
      .where((line) => !line.contains('<@lv.'))
      .join('\n');
  return cleanRichText(kept);
}

/// Whether [text] states game mechanics: digits, percentages, plus signs or
/// effect words in a short sentence. Used on fields that hold either flavor
/// or effect text depending on the item (`usage`, `desc`, `description`).
bool isMechanical(String text) {
  final clean = cleanRichText(text);
  if (clean.isEmpty) return false;
  if (RegExp(r'[0-9０-９％%＋+]|\{\d*\}').hasMatch(clean)) return true;
  // A leading bracketed name is how skills and traits are written.
  if (RegExp(r'^【[^】]+】').hasMatch(clean)) return true;
  return clean.length < 80 && _mechanicalWords.hasMatch(clean);
}

/// Path segments whose text is gameplay and is never harvested.
const List<String> _gameplayKeys = [
  'rule', 'task', 'mission', 'reward', 'cond', 'unlock', 'toast', 'guide',
  'tutorial', 'shop', 'pool', 'recruit', 'buff', 'effect', 'skill', 'tech',
  'bond', 'card', 'equip', 'stageaddition', 'zoneaddition', 'mapmode',
  'team', 'const', 'tip', 'button', 'btn', 'login', 'checkin', 'lock',
  'difficult', 'cost', 'condition', 'obtain', 'usage', 'function', 'param',
];

/// Path segments whose text is narrative (kept even when short).
const List<String> _narrativeKeys = [
  'news', 'eventdes', 'treasuredes', 'dialog', 'plot', 'principal',
  'festival', 'blessing', 'archive', 'landmark', 'photo', 'perform',
  'letter', 'chat', 'speech', 'bark', 'narrat', 'diary', 'lore', 'words',
];

/// One piece of harvested text with the key it came from.
class HarvestedText {
  const HarvestedText(this.key, this.text);

  /// Last named path segment (`newsText`, `landmarkDesc` …).
  final String key;
  final String text;
}

/// Whether a cleaned string reads like narrative prose: long enough, written
/// in sentences, not mostly numbers and without format placeholders.
bool looksLikeProse(String clean) {
  if (clean.length < 40 || clean.contains('{')) return false;
  if (RegExp(r'[，。！？、…；：]').allMatches(clean).length < 2) return false;
  final digits = RegExp(r'[0-9０-９％%]').allMatches(clean).length;
  return digits * 100 ~/ clean.length < 8;
}

bool _hasToken(List<String> segments, List<String> tokens) {
  for (final segment in segments) {
    for (final token in tokens) {
      if (segment.contains(token)) return true;
    }
  }
  return false;
}

/// Collects the narrative text of [node] in document order. [rootKey] is the
/// key [node] was stored under; it counts as the first path segment, so a
/// whole gameplay structure (`taskData`, `bondInfoDict`) is dropped by name.
///
/// A string is kept when its path has a narrative key (news, dialog, event
/// description, letter …) or when it reads as prose; any gameplay key on its
/// path (rule, task, reward, shop, buff …) drops it first. Strings that only
/// restate mechanics are dropped everywhere.
List<HarvestedText> harvestNarrative(Object? node, {String rootKey = ''}) {
  final out = <HarvestedText>[];
  final seen = <String>{};

  void visit(Object? value, List<String> path) {
    if (value is String) {
      if (!hasChinese(value)) return;
      final clean = cleanRichText(value);
      if (clean.isEmpty) return;
      final segments = [for (final s in path) s.toLowerCase()];
      if (_hasToken(segments, _gameplayKeys)) return;
      final narrative = _hasToken(segments, _narrativeKeys);
      if (!narrative && !looksLikeProse(clean)) return;
      if (!narrative && isMechanical(clean)) return;
      // Narrative keys still hold labels and UI strings: placeholders and
      // short fragments are not text of the story.
      if (clean.contains('{') || (narrative && clean.length < 12)) return;
      // Short lines with numbers are effects, even under a narrative key.
      if (clean.length < 120 && RegExp(r'[0-9０-９％%＋+]').hasMatch(clean)) {
        return;
      }
      if (!seen.add(clean)) return;
      out.add(HarvestedText(path.isEmpty ? '' : path.last, clean));
    } else if (value is List) {
      for (final item in value) {
        visit(item, path);
      }
    } else if (value is Map) {
      for (final entry in value.entries) {
        visit(entry.value, [...path, '${entry.key}']);
      }
    }
  }

  visit(node, rootKey.isEmpty ? const [] : [rootKey]);
  return out;
}

/// Splits [text] into pieces of at most [max] characters on line
/// boundaries (a single longer line is kept whole).
List<String> splitText(String text, {int max = 1500}) {
  if (text.length <= max) return [text];
  final pieces = <String>[];
  final buffer = StringBuffer();
  for (final line in text.split('\n')) {
    if (buffer.length > 0 && buffer.length + line.length + 1 > max) {
      pieces.add(buffer.toString());
      buffer.clear();
    }
    if (buffer.length > 0) buffer.write('\n');
    buffer.write(line);
  }
  if (buffer.length > 0) pieces.add(buffer.toString());
  return pieces;
}

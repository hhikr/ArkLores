import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../story_catalog.dart' show storyCatalogTable;
import '../terra_timeline.dart';

/// Reads PRTS Wiki's "泰拉年表" from its wikitext and writes it into a
/// knowledge base (`terra_timeline.dart`).
///
/// The page: `==era==`, `===century===`, `====year====` headings; under
/// them tables whose header cells (`!…`) give a date or a period and whose
/// cells are `{{并行折叠框|event|sources}}`. The sources are `*` lines,
/// `<collection>：[[<story page>/BEG|label]]、…`. Everything is taken as
/// the page writes it; a source is tied to a story only when the catalog
/// has exactly one story with the link's level code, chapter name and
/// before/after/interlude ([mapStoryLink]) — nothing is guessed from a name.

/// One parsed source, before it is matched to a story.
class ParsedTimelineSource {
  const ParsedTimelineSource(this.label, this.target);
  final String label;
  final String? target;
}

/// One parsed event.
class ParsedTimelineEvent {
  ParsedTimelineEvent({
    required this.era,
    this.period,
    this.heading,
    this.timeLabel,
    required this.content,
    required this.parallel,
    required this.sources,
  });

  final String era;
  final String? period;
  final String? heading;
  final String? timeLabel;
  final String content;
  final bool parallel;
  final List<ParsedTimelineSource> sources;

  ({int from, int to})? get years {
    for (final text in [heading, period]) {
      final years = [
        for (final m in RegExp(r'(?<!\d)(\d{4})(?!\d)').allMatches(text ?? ''))
          int.parse(m.group(1)!),
      ];
      if (years.isNotEmpty) {
        years.sort();
        return (from: years.first, to: years.last);
      }
    }
    return null;
  }
}

/// Sections that are not part of the timeline.
const _skippedSections = {'注释与链接'};

/// The events of the page's [wikitext], in its order.
List<ParsedTimelineEvent> parseTerraTimeline(String wikitext) {
  final text = wikitext.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  final events = <ParsedTimelineEvent>[];
  String? era;
  String? period;
  String? heading;
  String? timeLabel;
  var skipping = false;
  var i = 0;
  while (i < text.length) {
    var lineEnd = text.indexOf('\n', i);
    if (lineEnd < 0) lineEnd = text.length;
    final line = text.substring(i, lineEnd);
    final trimmed = line.trim();
    final h = RegExp(r'^(={2,4})\s*(.*?)\s*\1\s*$').firstMatch(trimmed);
    if (h != null) {
      final level = h.group(1)!.length;
      final title = _cleanInline(h.group(2)!);
      if (level == 2) {
        era = title;
        period = null;
        heading = null;
        skipping = _skippedSections.contains(title);
      } else if (level == 3) {
        period = title;
        heading = null;
      } else {
        heading = title;
      }
      timeLabel = null;
      i = lineEnd + 1;
      continue;
    }
    if (era == null || skipping) {
      i = lineEnd + 1;
      continue;
    }
    if (trimmed.startsWith('{|')) timeLabel = null;
    if (trimmed.startsWith('!')) {
      // A header cell, possibly with attributes and continued on the next
      // lines ("1098 年\n（时间未知）").
      var label = trimmed.substring(1);
      final bar = _topLevelBar(label);
      if (bar >= 0 && label.substring(0, bar).contains('=')) {
        label = label.substring(bar + 1);
      }
      var next = lineEnd + 1;
      while (next < text.length) {
        var end = text.indexOf('\n', next);
        if (end < 0) end = text.length;
        final more = text.substring(next, end).trim();
        if (more.isEmpty ||
            more.startsWith('|') ||
            more.startsWith('!') ||
            more.startsWith('{') ||
            more.startsWith('=')) {
          break;
        }
        label = '$label $more';
        next = end + 1;
      }
      final cleaned = _cleanInline(label);
      timeLabel = cleaned.isEmpty ? null : cleaned;
      i = next;
      continue;
    }
    final start = line.indexOf('{{并行折叠框');
    if (start >= 0) {
      final from = i + start;
      final end = _templateEnd(text, from);
      final args = _splitArgs(text.substring(from + 2, end - 2));
      if (args.length >= 2) {
        final raw = args[1];
        final content = _cleanBlock(raw);
        if (content.isNotEmpty) {
          events.add(
            ParsedTimelineEvent(
              era: era,
              period: period,
              heading: heading,
              timeLabel: timeLabel,
              content: content,
              parallel: RegExp(r'\{\{\s*popup[^}]*平行世界').hasMatch(raw),
              sources: args.length > 2
                  ? _parseSources(args.sublist(2).join('|'))
                  : const [],
            ),
          );
        }
      }
      i = end;
      continue;
    }
    i = lineEnd + 1;
  }
  return events;
}

/// The end (exclusive) of the template starting at [start] (`{{`).
int _templateEnd(String text, int start) {
  var depth = 0;
  var i = start;
  while (i < text.length - 1) {
    final two = text.substring(i, i + 2);
    if (two == '{{') {
      depth++;
      i += 2;
    } else if (two == '}}') {
      depth--;
      i += 2;
      if (depth == 0) return i;
    } else {
      i++;
    }
  }
  return text.length;
}

/// The index of the first `|` outside templates and links, or -1.
int _topLevelBar(String text) {
  var depth = 0;
  for (var i = 0; i < text.length; i++) {
    final two = i + 1 < text.length ? text.substring(i, i + 2) : '';
    if (two == '{{' || two == '[[') {
      depth++;
      i++;
    } else if (two == '}}' || two == ']]') {
      depth--;
      i++;
    } else if (text[i] == '|' && depth == 0) {
      return i;
    }
  }
  return -1;
}

/// A template's body split at its top-level `|`.
List<String> _splitArgs(String body) {
  final args = <String>[];
  var rest = body;
  while (true) {
    final bar = _topLevelBar(rest);
    if (bar < 0) {
      args.add(rest);
      return args;
    }
    args.add(rest.substring(0, bar));
    rest = rest.substring(bar + 1);
  }
}

List<ParsedTimelineSource> _parseSources(String raw) {
  final sources = <ParsedTimelineSource>[];
  for (var line in raw.split('\n')) {
    line = line.trim();
    if (line.startsWith('*')) line = line.substring(1).trim();
    if (line.isEmpty) continue;
    // "<collection>：" before the links, when the line has one.
    String? prefix;
    final colon = line.indexOf('：');
    if (colon > 0 && !line.substring(0, colon).contains('[[')) {
      prefix = _cleanInline(line.substring(0, colon));
    }
    final links =
        RegExp(r'\[\[([^\]|]+)(?:\|([^\]]*))?\]\]').allMatches(line).toList();
    if (prefix != null && links.isNotEmpty) {
      // One source per link: "<collection>：<label>".
      for (final m in links) {
        final label = _cleanInline(m.group(2) ?? m.group(1)!);
        sources.add(
          ParsedTimelineSource('$prefix：$label', m.group(1)!.trim()),
        );
      }
    } else {
      final first = links.isEmpty ? null : links.first.group(1)!.trim();
      final label = _cleanInline(line);
      if (label.isNotEmpty) sources.add(ParsedTimelineSource(label, first));
    }
  }
  return sources;
}

/// One line of markup as plain text.
String _cleanInline(String text) =>
    _cleanBlock(text).replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();

/// Markup as plain text, keeping line breaks.
String _cleanBlock(String text) {
  var t = text;
  // Templates: ruby keeps its base text; the rest (popups, icons) go.
  t = t.replaceAllMapped(
    RegExp(r'\{\{\s*ruby\s*\|([^|}]*)\|[^}]*\}\}', caseSensitive: false),
    (m) => m.group(1)!,
  );
  while (RegExp(r'\{\{[^{}]*\}\}').hasMatch(t)) {
    t = t.replaceAll(RegExp(r'\{\{[^{}]*\}\}'), '');
  }
  t = t.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  t = t.replaceAll(RegExp(r'<[^>]+>'), '');
  t = t.replaceAllMapped(
    RegExp(r'\[\[([^\]|]+)\|([^\]]*)\]\]'),
    (m) => m.group(2)!,
  );
  t = t.replaceAllMapped(RegExp(r'\[\[([^\]]+)\]\]'), (m) => m.group(1)!);
  t = t.replaceAllMapped(
    RegExp(r'\[(https?://\S+)\s+([^\]]+)\]'),
    (m) => m.group(2)!,
  );
  t = t.replaceAll("'''", '').replaceAll("''", '');
  t = t.replaceAll('&nbsp;', ' ');
  return t
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .where((l) => l.isNotEmpty)
      .join('\n');
}

/// The catalog's stories by level code, chapter name and kind.
class StoryLinkIndex {
  StoryLinkIndex(this._rows);

  final List<({String id, String? code, String? name, String? tag})> _rows;

  static Future<StoryLinkIndex> load(DatabaseExecutor db) async {
    final has = (await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      [storyCatalogTable],
    ))
        .isNotEmpty;
    if (!has) return StoryLinkIndex(const []);
    return StoryLinkIndex([
      for (final r in await db.rawQuery(
        'SELECT story_id, story_code, story_name, avg_tag '
        'FROM $storyCatalogTable',
      ))
        (
          id: '${r['story_id']}',
          code: r['story_code'] as String?,
          name: r['story_name'] as String?,
          tag: r['avg_tag'] as String?,
        ),
    ]);
  }

  /// The story a wiki story link names: `<code> <name>/BEG|END|NBT` (or
  /// `<code>/NBT`), when exactly one story of the catalog has that level
  /// code, chapter name (when the link gives one) and before / after /
  /// interlude. Anything else (an operator page, an anchor, an extra
  /// `/part`) is not a story link.
  String? mapStoryLink(String target) {
    final parts = target.split('/');
    if (parts.length != 2) return null;
    final tag = switch (parts[1].trim()) {
      'BEG' => '行动前',
      'END' => '行动后',
      'NBT' => '幕间',
      _ => null,
    };
    if (tag == null) return null;
    final head = parts[0].replaceAll('_', ' ').trim();
    final space = head.indexOf(' ');
    final code = space < 0 ? head : head.substring(0, space);
    final name = space < 0 ? null : head.substring(space + 1).trim();
    final hits = [
      for (final r in _rows)
        if (r.code == code &&
            r.tag == tag &&
            (name == null || name.isEmpty || r.name == name))
          r.id,
    ];
    return hits.length == 1 ? hits.single : null;
  }
}

/// `timeline/<hash>` for each event, from its text; equal texts get `-2`,
/// `-3` … in page order.
List<String> timelineEventIds(List<ParsedTimelineEvent> events) {
  final seen = <String, int>{};
  return [
    for (final e in events)
      () {
        final hash = sha1
            .convert(utf8.encode('${e.era}\n${e.content}'))
            .toString()
            .substring(0, 12);
        final n = (seen[hash] ?? 0) + 1;
        seen[hash] = n;
        return '$terraTimelineRecordPrefix$hash${n == 1 ? '' : '-$n'}';
      }(),
  ];
}

/// What [writeTerraTimeline] wrote.
class TerraTimelineReport {
  const TerraTimelineReport({
    required this.events,
    required this.sources,
    required this.storyLinks,
    required this.mapped,
  });

  final int events;
  final int sources;

  /// Sources linking a story page (`…/BEG|END|NBT`), and how many of them
  /// were tied to a story of the catalog.
  final int storyLinks;
  final int mapped;

  @override
  String toString() => 'events $events, sources $sources, '
      'story links $storyLinks, tied to a story $mapped';
}

/// Replaces the timeline in [db] with [events] (from [revision] of the
/// page).
Future<TerraTimelineReport> writeTerraTimeline(
  Database db,
  List<ParsedTimelineEvent> events, {
  String? revision,
  DateTime? builtAt,
}) async {
  final index = await StoryLinkIndex.load(db);
  final ids = timelineEventIds(events);
  var sources = 0;
  var storyLinks = 0;
  var mapped = 0;
  await db.transaction((txn) async {
    await txn.execute(terraTimelineDdl);
    await txn.execute(terraTimelineSourcesDdl);
    await txn.execute(terraTimelineMetaDdl);
    await txn.delete(terraTimelineSourcesTable);
    await txn.delete(terraTimelineTable);
    await txn.delete(terraTimelineMetaTable);
    final batch = txn.batch();
    for (final (n, e) in events.indexed) {
      final years = e.years;
      batch.insert(terraTimelineTable, {
        'id': ids[n],
        'sort': n,
        'era': e.era,
        'period': e.period,
        'heading': e.heading,
        'year_from': years?.from,
        'year_to': years?.to,
        'time_label': e.timeLabel,
        'content': e.content,
        'parallel': e.parallel ? 1 : 0,
      });
      for (final (k, s) in e.sources.indexed) {
        final target = s.target;
        final isStory =
            target != null && RegExp(r'/(BEG|END|NBT)\b').hasMatch(target);
        final story = target == null ? null : index.mapStoryLink(target);
        if (isStory) storyLinks++;
        if (story != null) mapped++;
        sources++;
        batch.insert(terraTimelineSourcesTable, {
          'event_id': ids[n],
          'sort': k,
          'label': s.label,
          'target': target,
          'story_id': story,
        });
      }
    }
    batch.insert(terraTimelineMetaTable, {
      'key': 'page',
      'value': terraTimelinePage,
    });
    batch.insert(terraTimelineMetaTable, {
      'key': 'license',
      'value': terraTimelineLicense,
    });
    if (revision != null) {
      batch.insert(terraTimelineMetaTable, {
        'key': 'revision',
        'value': revision,
      });
    }
    batch.insert(terraTimelineMetaTable, {
      'key': 'built_at',
      'value': (builtAt ?? DateTime.now().toUtc()).toIso8601String(),
    });
    await batch.commit(noResult: true);
  });
  return TerraTimelineReport(
    events: events.length,
    sources: sources,
    storyLinks: storyLinks,
    mapped: mapped,
  );
}

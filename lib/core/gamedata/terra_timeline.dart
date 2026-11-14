import 'package:sqflite_common/sqlite_api.dart';

/// PRTS Wiki's "泰拉年表" (Terra timeline, CC BY-NC-SA 4.0) in the Arknights
/// knowledge base: the events of the story in the order the wiki's editors
/// put them, each with the places in the game it is drawn from
/// (2026-11-14, developer: the first thing to look at for when things
/// happened and how the story fits together). The editors infer the dates
/// from the stories; details are settled by the story text.
///
/// Built by `tools/build_terra_timeline.dart`
/// (`build/terra_timeline_importer.dart`); optional — a knowledge base
/// without it has no timeline.
const String terraTimelineTable = 'terra_timeline';
const String terraTimelineSourcesTable = 'terra_timeline_sources';
const String terraTimelineMetaTable = 'terra_timeline_meta';

/// The wiki page the timeline is taken from.
const String terraTimelinePage = '泰拉年表';

/// The license of the page (and of the timeline data built from it).
const String terraTimelineLicense = 'CC BY-NC-SA 4.0';

/// Starts the record id an event is shown and cited with
/// (`record:timeline/<hash>`); it names no game, so it is Arknights'.
const String terraTimelineRecordPrefix = 'timeline/';

/// The category a timeline event is shown with.
const String terraTimelineCategory = '泰拉年表';

bool isTerraTimelineRecord(String id) =>
    id.startsWith(terraTimelineRecordPrefix);

const String terraTimelineDdl = '''
  CREATE TABLE IF NOT EXISTS $terraTimelineTable (
    id         TEXT PRIMARY KEY,
    sort       INTEGER NOT NULL,
    era        TEXT NOT NULL,
    period     TEXT,
    heading    TEXT,
    year_from  INTEGER,
    year_to    INTEGER,
    time_label TEXT,
    content    TEXT NOT NULL,
    parallel   INTEGER NOT NULL DEFAULT 0
  )
''';

const String terraTimelineSourcesDdl = '''
  CREATE TABLE IF NOT EXISTS $terraTimelineSourcesTable (
    event_id  TEXT NOT NULL,
    sort      INTEGER NOT NULL,
    label     TEXT NOT NULL,
    target    TEXT,
    story_id  TEXT,
    PRIMARY KEY (event_id, sort)
  )
''';

const String terraTimelineMetaDdl = '''
  CREATE TABLE IF NOT EXISTS $terraTimelineMetaTable (
    key   TEXT PRIMARY KEY,
    value TEXT
  )
''';

/// One place an event is drawn from: what the wiki shows ([label]) and,
/// when the wiki links a story that the catalog has exactly once (level
/// code, chapter name and before/after/interlude all equal), the story.
class TimelineSource {
  const TimelineSource({required this.label, this.target, this.storyId});

  final String label;

  /// The wiki page linked, if any.
  final String? target;

  /// The knowledge base's story file, when the link names one.
  final String? storyId;
}

/// One event of the timeline.
class TimelineEvent {
  const TimelineEvent({
    required this.id,
    required this.sort,
    required this.era,
    this.period,
    this.heading,
    this.yearFrom,
    this.yearTo,
    this.timeLabel,
    required this.content,
    this.parallel = false,
    this.sources = const [],
  });

  /// `timeline/<hash of the text>`: stable while the event's text is.
  final String id;

  /// Order in the timeline (the page's order).
  final int sort;

  /// The page's sections: era (`结晶纪元`), century, year heading.
  final String era;
  final String? period;
  final String? heading;

  /// The years the heading names, when it names any.
  final int? yearFrom;
  final int? yearTo;

  /// The row label: a date, a season, "（时间未知）" …
  final String? timeLabel;

  final String content;

  /// Marked by the wiki as a parallel world's event.
  final bool parallel;

  final List<TimelineSource> sources;

  /// Where the event sits, most specific last ("结晶纪元 · 1098 年 · 7 月").
  String get where => [
        era,
        if (period != null && period != era) period,
        if (heading != null) heading,
        if (timeLabel != null && timeLabel != heading) timeLabel,
      ].whereType<String>().join(' · ');
}

/// The whole timeline of a knowledge base.
class TerraTimeline {
  const TerraTimeline({
    required this.events,
    this.revision,
    this.builtAt,
  });

  final List<TimelineEvent> events;

  /// The page revision it was built from.
  final String? revision;
  final String? builtAt;

  TimelineEvent? byId(String id) {
    for (final e in events) {
      if (e.id == id) return e;
    }
    return null;
  }

  bool get isEmpty => events.isEmpty;
}

Future<bool> _hasTable(DatabaseExecutor db, String name) async =>
    (await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      [name],
    ))
        .isNotEmpty;

/// The timeline in [db], or null when the knowledge base has none.
Future<TerraTimeline?> loadTerraTimeline(DatabaseExecutor db) async {
  if (!await _hasTable(db, terraTimelineTable)) return null;
  final sources = <String, List<TimelineSource>>{};
  if (await _hasTable(db, terraTimelineSourcesTable)) {
    for (final r in await db.rawQuery(
      'SELECT event_id, label, target, story_id '
      'FROM $terraTimelineSourcesTable ORDER BY event_id, sort',
    )) {
      sources.putIfAbsent('${r['event_id']}', () => []).add(
            TimelineSource(
              label: '${r['label']}',
              target: r['target'] as String?,
              storyId: r['story_id'] as String?,
            ),
          );
    }
  }
  final meta = <String, String>{};
  if (await _hasTable(db, terraTimelineMetaTable)) {
    for (final r in await db.rawQuery(
      'SELECT key, value FROM $terraTimelineMetaTable',
    )) {
      meta['${r['key']}'] = '${r['value'] ?? ''}';
    }
  }
  final events = [
    for (final r in await db.rawQuery(
      'SELECT * FROM $terraTimelineTable ORDER BY sort',
    ))
      TimelineEvent(
        id: '${r['id']}',
        sort: r['sort']! as int,
        era: '${r['era']}',
        period: r['period'] as String?,
        heading: r['heading'] as String?,
        yearFrom: r['year_from'] as int?,
        yearTo: r['year_to'] as int?,
        timeLabel: r['time_label'] as String?,
        content: '${r['content']}',
        parallel: r['parallel'] == 1,
        sources: sources['${r['id']}'] ?? const [],
      ),
  ];
  if (events.isEmpty) return null;
  return TerraTimeline(
    events: events,
    revision: meta['revision'],
    builtAt: meta['built_at'],
  );
}

/// An event as text for the agent and for a cited record: where it sits,
/// what happened, what it is drawn from.
String timelineEventText(TimelineEvent e, {bool withSources = true}) {
  final buffer = StringBuffer()
    ..writeln('【${e.where}】${e.parallel ? '（平行世界）' : ''}')
    ..writeln(e.content);
  if (withSources && e.sources.isNotEmpty) {
    buffer.writeln(
      '出处：${e.sources.map((s) => s.storyId == null ? s.label : '${s.label}（${s.storyId}）').join('；')}',
    );
  }
  return buffer.toString().trimRight();
}

part of '../lore_tools.dart';

/// 2026-11-14 (developer): `timeline` — PRTS Wiki's Terra timeline in the
/// Arknights knowledge base. The first thing to look at for when things
/// happened and how the story fits together: events in the timeline's
/// order, each with the places it is drawn from (a story the knowledge base
/// has is named by its id, ready for `read_story`). Code calls it once in
/// the first steps of every question (`lore_agent_loop.dart`), with the
/// question's names; the model can call it again.
///
/// The events shown are registered as records (`record:timeline/<hash>`):
/// they can be cited, as the timeline, the story text settling details.
class TimelineTool extends AgentTool {
  TimelineTool(this.store, this.seen);

  final GameDataRetrieval store;
  final SeenLines seen;

  @override
  String get name => 'timeline';

  @override
  String get description =>
      '查泰拉年表（PRTS Wiki 编者按剧情整理的明日方舟编年）：按名字、年份或时期列出事件，按年表的先后排，'
      '每件写明时期、日期和出处；出处能对上库里剧情的附 story_id，可以直接 read_story。'
      '不给参数时列出各时期和事件数。涉及时间、先后和整体脉络时先查它，再读它指向的原文。'
      '年表的日期是编者推断的，细节、台词和人物的态度以原文为准；引用一件事写 record:timeline/<编号>。';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'names': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '人物、组织、地点、事件的名字；列出提到任意一个的事件（可选）',
          },
          'year_from': {'type': 'integer', 'description': '从哪一年起（可选）'},
          'year_to': {'type': 'integer', 'description': '到哪一年为止（可选）'},
          'period': {
            'type': 'string',
            'description': '只看一个时期，写不给参数时列出的时期名（可选）',
          },
        },
      };

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final timeline = await store.terraTimeline();
    if (timeline == null || timeline.isEmpty) {
      return '知识库里没有泰拉年表（只有明日方舟的知识库带年表，需要较新的知识库）。';
    }
    final names = _stringList(arguments['names']);
    final yearFrom = _int(arguments['year_from']);
    final yearTo = _int(arguments['year_to']);
    final period = '${arguments['period'] ?? ''}'.trim();
    final periods = _periods(timeline);
    final buffer = StringBuffer()
      ..writeln('泰拉年表（PRTS Wiki，版本 ${timeline.revision ?? '未知'}；'
          '日期由编者按剧情推断，细节以原文为准；引用写 record:timeline/<编号>）');
    if (names.isEmpty && yearFrom == null && yearTo == null && period.isEmpty) {
      buffer.writeln('各时期（时期名 · 年份 · 事件数）：');
      for (final p in periods) {
        buffer.writeln('${p.name}${p.years == null ? '' : ' · ${p.years}'} · ${p.count} 件');
      }
      buffer.write('用 names、year_from/year_to 或 period 查具体事件。');
      return buffer.toString().trimRight();
    }
    bool inYears(TimelineEvent e) {
      if (yearFrom == null && yearTo == null) return true;
      final from = e.yearFrom;
      final to = e.yearTo ?? from;
      if (from == null || to == null) return false;
      return (yearTo == null || from <= yearTo) &&
          (yearFrom == null || to >= yearFrom);
    }

    bool mentions(TimelineEvent e) =>
        names.isEmpty ||
        names.any(
          (n) =>
              e.content.contains(n) || e.sources.any((s) => s.label.contains(n)),
        );
    final hits = [
      for (final e in timeline.events)
        if ((period.isEmpty || _periodOf(e) == period || e.where.contains(period)) &&
            inYears(e) &&
            mentions(e))
          e,
    ];
    final asked = [
      if (names.isNotEmpty) '提到 ${names.join('、')}',
      if (yearFrom != null || yearTo != null)
        '${yearFrom ?? '…'}–${yearTo ?? '…'} 年',
      if (period.isNotEmpty) '时期 $period',
    ].join('，');
    if (hits.isEmpty) {
      buffer
        ..writeln('没有$asked的事件。')
        ..write('各时期：${periods.map((p) => '${p.name}（${p.count}）').join('、')}');
      return buffer.toString().trimRight();
    }
    if (names.length > 1) {
      final counts = [
        for (final n in names)
          '$n ${hits.where((e) => e.content.contains(n) || e.sources.any((s) => s.label.contains(n))).length}',
      ];
      buffer.writeln('$asked的事件 ${hits.length} 件（${counts.join('，')}），按年表先后：');
    } else {
      buffer.writeln('$asked的事件 ${hits.length} 件，按年表先后：');
    }
    var shown = 0;
    String? lastPeriod;
    for (final e in hits) {
      final text = _event(e);
      if (buffer.length + text.length > maxToolResultChars) break;
      final p = _periodOf(e);
      if (p != lastPeriod) {
        buffer.writeln('— $p');
        lastPeriod = p;
      }
      buffer.writeln(text);
      seen.addRecord(e.id);
      shown++;
    }
    if (shown < hits.length) {
      final rest = <String, int>{};
      for (final e in hits.skip(shown)) {
        rest.update(_periodOf(e), (n) => n + 1, ifAbsent: () => 1);
      }
      buffer.write('……还有 ${hits.length - shown} 件没有列出，在'
          '${rest.entries.map((r) => '${r.key}（${r.value}）').join('、')}；'
          '加 period 或 year_from/year_to 缩小范围再查。');
    }
    return buffer.toString().trimRight();
  }

  static String _periodOf(TimelineEvent e) => e.heading ?? e.period ?? e.era;

  static List<({String name, String? years, int count})> _periods(
    TerraTimeline timeline,
  ) {
    final order = <String>[];
    final counts = <String, int>{};
    final years = <String, (int, int)>{};
    for (final e in timeline.events) {
      final p = _periodOf(e);
      if (!counts.containsKey(p)) order.add(p);
      counts.update(p, (n) => n + 1, ifAbsent: () => 1);
      if (e.yearFrom case final from?) {
        final to = e.yearTo ?? from;
        final was = years[p];
        years[p] = was == null
            ? (from, to)
            : (from < was.$1 ? from : was.$1, to > was.$2 ? to : was.$2);
      }
    }
    return [
      for (final p in order)
        (
          name: p,
          years: switch (years[p]) {
            null => null,
            (final a, final b) when a == b => '$a',
            (final a, final b) => '$a–$b',
          },
          count: counts[p]!,
        ),
    ];
  }

  static String _event(TimelineEvent e) {
    final when = [
      if (e.timeLabel != null && e.timeLabel != e.heading) e.timeLabel,
      if (e.parallel) '平行世界',
    ].whereType<String>().join('，');
    final sources = [
      for (final s in e.sources)
        s.storyId == null ? s.label : '${s.label}（${s.storyId}）',
    ];
    return 'record:${e.id}'
        '${when.isEmpty ? '' : ' [$when]'} ${e.content.replaceAll('\n', '；')}'
        '${sources.isEmpty ? '' : '\n  出处：${sources.join('；')}'}';
  }

  static int? _int(Object? raw) => switch (raw) {
        final int n => n,
        final num n => n.toInt(),
        final String s => int.tryParse(s.trim()),
        _ => null,
      };
}

import 'dart:io';

import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/gamedata/build/terra_timeline_importer.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/terra_timeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/gamedata_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

/// 2026-11-14: the Terra timeline — parsed from the wiki's markup, written
/// into a knowledge base, read back, and shown by the `timeline` tool. The
/// page below is made up in the wiki's format: the parser knows no event.
const _page = r"""
{{cbox2|lv=1|text=页首说明。}}
{| class="wikitable"
!来源||链接格式
|-
|主线
|<code><nowiki>章节名：[[剧情链接|XX-X 行动前]]</nowiki></code>
|}

==远古==
{|class="wikitable"
|-
!rowspan="2" style="width:130px"|上古时期
|{{并行折叠框|甲国建立<!--编者注释-->|* 第一章 起点：[[1-1 开端/BEG|1-1 行动前]]}}
|-
|{{并行折叠框|乙在{{ruby|远方|Far}}出生<br>后来离开|* 丙：[[丙#档案|档案资料一]]
* [https://example.com/v “一段录音”]}}
|}

==纪元==
===11世纪===
===='''1098 年'''====
{|class="wikitable"
|-
!rowspan="3"|1098 年
（时间未知）
|{{并行折叠框|甲国与丁国交战|* 某活动：[[AB-3 交锋/END|AB-3 行动后]]、[[AB-ST-1_余波/NBT|AB-ST-1]]}}
|-
|{{并行折叠框|甲国与丁国交战|* 另一个故事集：[[XY-ST1 同名/NBT|同名]]}}
|-
!7 月
|{{并行折叠框|{{popup|内容=本条为平行世界内容，与主世界线发展存在差异|mdi=eye-circle}}戊来到甲国|*[[情报处理室#某处|某处]]}}
|}

== 注释与链接 ==
{{并行折叠框|不是事件|* 无}}
""";

void main() {
  group('parseTerraTimeline', () {
    final events = parseTerraTimeline(_page);

    test('takes the events under the headings, skips notes and the format '
        'table', () {
      expect(events.map((e) => e.content), [
        '甲国建立',
        '乙在远方出生\n后来离开',
        '甲国与丁国交战',
        '甲国与丁国交战',
        '戊来到甲国',
      ]);
    });

    test('keeps the era, century, year heading and row label', () {
      expect(events.first.era, '远古');
      expect(events.first.timeLabel, '上古时期');
      expect(events.first.years, isNull);
      final war = events[2];
      expect(war.era, '纪元');
      expect(war.period, '11世纪');
      expect(war.heading, '1098 年');
      // A header cell continued on the next line.
      expect(war.timeLabel, '1098 年 （时间未知）');
      expect(war.years, (from: 1098, to: 1098));
      expect(events.last.timeLabel, '7 月');
    });

    test('marks a parallel world and reads each source link', () {
      expect(events.last.parallel, isTrue);
      expect(events.first.parallel, isFalse);
      expect(events[2].sources.map((s) => (s.label, s.target)), [
        ('某活动：AB-3 行动后', 'AB-3 交锋/END'),
        ('某活动：AB-ST-1', 'AB-ST-1_余波/NBT'),
      ]);
      // A line without "<collection>：" is one source; an external link is
      // its label.
      expect(events[1].sources.map((s) => s.label), ['丙：档案资料一', '“一段录音”']);
      expect(events.last.sources.single.label, '某处');
    });

    test('ids come from the text; equal texts are numbered', () {
      final ids = timelineEventIds(events);
      expect(ids.toSet().length, ids.length);
      expect(ids[3], '${ids[2]}-2');
      expect(timelineEventIds(parseTerraTimeline(_page)), ids);
      expect(ids.every(isTerraTimelineRecord), isTrue);
    });
  });

  group('in a knowledge base', () {
    late Directory dir;
    late String path;
    late GameDataKnowledgeStore store;

    setUpAll(useSqfliteFfi);

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('arklores_timeline');
      path = p.join(dir.path, 'kb.db');
      final db = await createGameDataDb(path, catalog: true);
      Future<void> story(String id, String? code, String name, String tag) =>
          db.insert('story_catalog', {
            'story_id': id,
            'collection_id': 'c',
            'collection_name': '集',
            'collection_type': 'ACTIVITY',
            'story_code': code,
            'story_name': name,
            'avg_tag': tag,
            'story_sort': 1,
          });
      await story('s/1-1_beg.txt', '1-1', '开端', '行动前');
      await story('s/1-1_end.txt', '1-1', '开端', '行动后');
      await story('s/ab3_end.txt', 'AB-3', '交锋', '行动后');
      await story('s/abst1.txt', 'AB-ST-1', '余波', '幕间');
      // No level code in the catalog: the wiki's own code cannot be tied.
      await story('s/xy.txt', null, '同名', '幕间');
      final report = await writeTerraTimeline(
        db,
        parseTerraTimeline(_page),
        revision: '42',
      );
      expect(report.events, 5);
      expect(report.storyLinks, 4);
      expect(report.mapped, 3);
      await db.close();
      store = GameDataKnowledgeStore(dbPath: path);
    });

    tearDown(() async {
      await store.close();
      await deleteTempDir(dir);
    });

    test('a source is tied to a story by code, name and before/after only',
        () async {
      final timeline = (await store.terraTimeline())!;
      expect(timeline.revision, '42');
      expect(timeline.events.first.sources.single.storyId, 's/1-1_beg.txt');
      expect(
        timeline.events[2].sources.map((s) => s.storyId),
        ['s/ab3_end.txt', 's/abst1.txt'],
      );
      expect(timeline.events[3].sources.single.storyId, isNull);
      expect(timeline.events[1].sources.first.storyId, isNull);
    });

    test('an event reads like a record', () async {
      final id = (await store.terraTimeline())!.events.first.id;
      final record = (await store.readRecord(id))!;
      expect(record.category, terraTimelineCategory);
      expect(record.title, '远古 · 上古时期');
      expect(record.content, contains('甲国建立'));
      expect(record.content, contains('s/1-1_beg.txt'));
    });

    test('the tool lists the periods, then events by name or year, and '
        'registers what it shows', () async {
      final seen = SeenLines();
      final tool = TimelineTool(store, seen);
      final periods = await tool.execute({});
      expect(periods, contains('远古 · 2 件'));
      expect(periods, contains('1098 年 · 1098 · 3 件'));
      expect(seen.recordIds, isEmpty);

      final named = await tool.execute({
        'names': ['甲国'],
      });
      expect(named, contains('提到 甲国的事件 4 件'));
      expect(named.indexOf('甲国建立'), lessThan(named.indexOf('戊来到甲国')));
      expect(named, contains('（s/ab3_end.txt）'));
      expect(named, contains('[7 月，平行世界]'));
      expect(seen.recordIds.length, 4);
      expect(seen.recordIds.every(isTerraTimelineRecord), isTrue);

      final year = await tool.execute({'year_from': 1098, 'year_to': 1098});
      expect(year, contains('事件 3 件'));
      expect(year, isNot(contains('甲国建立')));

      final none = await tool.execute({
        'names': ['没有这个人'],
      });
      expect(none, contains('没有提到 没有这个人的事件'));
    });
  });

  test('a knowledge base without the timeline says so', () async {
    useSqfliteFfi();
    final dir = await Directory.systemTemp.createTemp('arklores_timeline0');
    final path = p.join(dir.path, 'kb.db');
    await (await createGameDataDb(path, catalog: true)).close();
    final store = GameDataKnowledgeStore(dbPath: path);
    try {
      expect(await store.terraTimeline(), isNull);
      expect(
        await TimelineTool(store, SeenLines()).execute({}),
        contains('没有泰拉年表'),
      );
    } finally {
      await store.close();
      await deleteTempDir(dir);
    }
  });
}

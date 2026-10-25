import 'package:arklores/core/agent/lore_agent_prompts.dart';
import 'package:arklores/core/agent/search_planner.dart';
import 'package:flutter_test/flutter_test.dart';

/// The first searches, planned by a small call of their own: what a reply is
/// read as and what the plan prompt offers. How a plan runs inside the loop
/// is in `lore_agent_loop_test.dart`.
void main() {
  test('a plan reads anchors, names only', () {
    final plan = parseSearchPlan(
      '{"anchors": ["甲", " 乙 ", "甲", "${'很长' * 11}", "丙", "丁", "戊", "己", "庚"]}',
    )!;
    // A plan of anchors alone is a plan; a repeat counts once, a long
    // phrase is not a name, six at most.
    expect(plan.queries, isEmpty);
    expect(plan.anchors, ['甲', '乙', '丙', '丁', '戊', '己']);
  });

  test('a reply that plans nothing is no plan', () {
    expect(parseSearchPlan('我不确定该查什么。'), isNull);
    expect(parseSearchPlan('{"search": []}'), isNull);
    expect(parseSearchPlan('{"search": [1, " "]}'), isNull);
    final plan = parseSearchPlan(
      '```json\n{"search": ["甲  乙", "甲 乙", "丙", "丁", "戊"], '
      '"wiki": ["甲", "乙"]}\n```',
    )!;
    // Spaces are single, a repeat counts once, three at most.
    expect(plan.queries, ['甲 乙', '丙', '丁']);
    expect(plan.wiki, '甲');
    expect(plan.outlines, isEmpty);
    expect(plan.wikiSearches, isEmpty);
  });

  // The first step may be a collection's outline or a wiki search, not
  // only a search.
  test('a plan may hold outlines and wiki searches', () {
    final only = parseSearchPlan('{"outline": "某个故事集"}')!;
    expect(only.outlines, ['某个故事集']);
    expect(only.queries, isEmpty);

    final all = parseSearchPlan(
      '{"search": ["甲", "乙", "丙"], "outline": ["子", "丑", "寅"], '
      '"wiki_search": ["卯", "辰"]}',
    )!;
    // Two outlines at most, four steps in all: outlines first, then
    // searches, then wiki searches.
    expect(all.outlines, ['子', '丑']);
    expect(all.queries, ['甲', '乙']);
    expect(all.wikiSearches, isEmpty);
    expect(
      parseSearchPlan('{"search": ["甲"], "wiki_search": ["卯", "辰", "巳"]}')!
          .wikiSearches,
      ['卯', '辰'],
    );
    expect(parseSearchPlan('{"outline": [], "wiki_search": " "}'), isNull);
  });

  test('the plan prompt offers the steps whose tools are there', () {
    final plain = loreRolePrompt(LoreRole.planner, searchDescription: '<检索说明>');
    expect(plain, contains('<检索说明>'));
    expect(plain, isNot(contains('outline')));
    expect(plain, isNot(contains('wiki')));
    final full = loreRolePrompt(
      LoreRole.planner,
      wiki: true,
      searchDescription: '<检索说明>',
      outlineDescription: '<目录说明>',
      wikiSearchDescription: '<搜索说明>',
    );
    expect(full, contains('- outline（故事集目录）：<目录说明>'));
    expect(full, contains('- wiki_search（Wiki 搜索）：<搜索说明>'));
    expect(
      full,
      contains('"outline": ["<故事集名>"], "wiki_search": ["<一个词>"], "wiki": "<一个词>"}'),
    );
    // No free hand to add names the question does not have.
    expect(full, contains('没有把握就不补'));
    // The wiki search needs the wiki option.
    expect(
      loreRolePrompt(
        LoreRole.planner,
        searchDescription: 's',
        wikiSearchDescription: '<搜索说明>',
      ),
      isNot(contains('wiki_search')),
    );
  });
}

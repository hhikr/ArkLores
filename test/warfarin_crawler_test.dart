import 'package:arklores/core/wiki/warfarin_crawler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Remix stream decoder', () {
    test('resolves indexed keys and nested values', () {
      final decoded = decodeRemixStream([
        {'version': 3},
        'route_a',
        {'_3': 4},
        'title',
        '佩丽卡',
      ]);

      expect(decoded['route_a'], {'title': '佩丽卡'});
      expect(decoded['title'], '佩丽卡');
    });

    test('returns empty data for incomplete streams', () {
      expect(decodeRemixStream(const []), isEmpty);
      expect(decodeRemixStream(const [1]), isEmpty);
    });
  });

  group('Warfarin markdown formatter', () {
    late WarfarinWikiCrawler crawler;

    setUp(() => crawler = WarfarinWikiCrawler());
    tearDown(() => crawler.dispose());

    test('formats operator metadata, archive and voice without game tags', () {
      final markdown = crawler.formatOperatorToMarkdown({
        'characterTable': {
          'name': {'zh': '佩丽卡'},
          'engName': 'Perlica',
          'charTypeId': 'electric',
          'cvName': {'ChiCVName': '测试声优'},
          'profileRecord': [
            {
              'recordTitle': '<@title>档案资料',
              'recordDesc': '<@text>来自终末地工业的管理员。',
            },
          ],
          'profileVoice': [
            {'voiceTitle': '问候', 'voiceDesc': '欢迎回来。'},
          ],
        },
        'charGrowthTable': {
          'rarity': 6,
          'profession': 5,
          'skillGroupMap': {
            'skill_1': {'name': '协议技', 'desc': '造成法术伤害。'},
          },
        },
        'charTagTable': {
          'blocId': 'power_endfield',
          'raceTagId': 'tag_race_liberi',
          'expertTagIds': ['tag_expert_manage'],
        },
        'charTagDesTable': {
          'tagDesc': {
            'tag_expert_manage': {'desc': '管理'},
          },
        },
      });

      expect(markdown, contains('# 佩丽卡'));
      expect(markdown, contains('> Perlica'));
      expect(markdown, contains('- 职业：术师'));
      expect(markdown, contains('- 阵营：终末地工业'));
      expect(markdown, contains('- 种族：黎博利'));
      expect(markdown, contains('- 专长：管理'));
      expect(markdown, contains('## 档案资料'));
      expect(markdown, contains('**问候**'));
      expect(markdown, isNot(contains('<@')));
    });

    test('formats lore text and ignores image-only records', () {
      final markdown = crawler.formatLoreToMarkdown({
        'prtsAllItem': {
          'name': {'zh': '弩箭残片的记录'},
          'type': '资料',
        },
        'richContentTable': {
          'contentList': [
            {'content': '<image>asset.png'},
            {'content': '这是一段可阅读的记录。'},
          ],
        },
      });

      expect(markdown, startsWith('# 弩箭残片的记录'));
      expect(markdown, contains('分类：资料'));
      expect(markdown, contains('这是一段可阅读的记录。'));
      expect(markdown, isNot(contains('asset.png')));
    });

    test('formats dialogue and excludes action/event rows', () {
      final markdown = crawler.formatMissionToMarkdown({
        'mission': {
          'name': '风平水不静',
          'typeName': '主线',
          'description': '调查异常信号。',
        },
        'dialog': [
          {'actorName': '佩丽卡', 'dialogText': '开始行动。', 'type': 'talk'},
          {'dialogText': '镜头切换', 'type': 'action'},
          {'dialogText': '通讯中断。', 'type': 'talk'},
        ],
      });

      expect(markdown, contains('# 风平水不静（主线）'));
      expect(markdown, contains('> 调查异常信号。'));
      expect(markdown, contains('**佩丽卡**：开始行动。'));
      expect(markdown, contains('通讯中断。'));
      expect(markdown, isNot(contains('镜头切换')));
    });
  });
}

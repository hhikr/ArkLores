import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import 'wiki_crawler.dart' show CrawlerException;

/// Crawler for warfarin.wiki (Arknights: Endfield Wiki).
///
/// Fetches structured data directly from the Remix `.data` JSON endpoints
/// to prevent scraping fragile HTML pages.
class WarfarinWikiCrawler {
  final http.Client _client;
  final Duration _requestDelay;

  static const String _baseUrl = 'https://warfarin.wiki/cn';
  static const String _userAgent =
      'ArkLores/0.3 (https://github.com/hhikr/ArkLores)';

  Duration get requestDelay => _requestDelay;

  WarfarinWikiCrawler({
    http.Client? client,
    Duration? requestDelay,
  })  : _client = client ?? http.Client(),
        _requestDelay = requestDelay ?? const Duration(milliseconds: 200);

  // ────────────────────────────────────────────────────────────────
  // Public API
  // ────────────────────────────────────────────────────────────────

  /// Fetches all operator slugs.
  Future<List<String>> fetchOperatorSlugs() async {
    final decoded = await _fetchAndDecode('$_baseUrl/operators.data');
    final indexData =
        decoded['routes/\$lang.operators._index'] as Map<String, dynamic>?;
    if (indexData == null) return [];
    final responseList = indexData['response'] as List<dynamic>? ?? [];
    return responseList
        .map((item) => (item as Map<String, dynamic>)['slug'] as String?)
        .where((slug) => slug != null && slug.isNotEmpty)
        .cast<String>()
        .toList();
  }

  /// Fetches a single operator's detail page and returns the parsed Map.
  Future<Map<String, dynamic>> fetchOperatorDetail(String slug) async {
    final decoded = await _fetchAndDecode('$_baseUrl/operators/$slug.data');
    final detailData =
        decoded['routes/\$lang.operators.\$slug'] as Map<String, dynamic>?;
    if (detailData == null || detailData['response'] == null) {
      throw CrawlerException('Failed to resolve operator detail: $slug');
    }
    return detailData['response'] as Map<String, dynamic>;
  }

  /// Fetches all lore/story slugs.
  Future<List<String>> fetchLoreSlugs() async {
    final decoded = await _fetchAndDecode('$_baseUrl/lore.data');
    final indexData =
        decoded['routes/\$lang.lore._index'] as Map<String, dynamic>?;
    if (indexData == null) return [];
    final responseList = indexData['response'] as List<dynamic>? ?? [];
    return responseList
        .map((item) => (item as Map<String, dynamic>)['slug'] as String?)
        .where((slug) => slug != null && slug.isNotEmpty)
        .cast<String>()
        .toList();
  }

  /// Fetches a single lore's detail.
  Future<Map<String, dynamic>> fetchLoreDetail(String slug) async {
    final decoded = await _fetchAndDecode('$_baseUrl/lore/$slug.data');
    final detailData =
        decoded['routes/\$lang.lore.\$slug'] as Map<String, dynamic>?;
    if (detailData == null || detailData['response'] == null) {
      throw CrawlerException('Failed to resolve lore detail: $slug');
    }
    return detailData['response'] as Map<String, dynamic>;
  }

  /// Fetches all mission slugs.
  Future<List<String>> fetchMissionSlugs() async {
    final decoded = await _fetchAndDecode('$_baseUrl/missions.data');
    final indexData =
        decoded['routes/\$lang.missions._index'] as Map<String, dynamic>?;
    if (indexData == null) return [];
    final responseList = indexData['response'] as List<dynamic>? ?? [];
    return responseList
        .map((item) => (item as Map<String, dynamic>)['slug'] as String?)
        .where((slug) => slug != null && slug.isNotEmpty)
        .cast<String>()
        .toList();
  }

  /// Fetches a single mission's detail.
  Future<Map<String, dynamic>> fetchMissionDetail(String slug) async {
    final decoded = await _fetchAndDecode('$_baseUrl/missions/$slug.data');
    final detailData =
        decoded['routes/\$lang.missions.\$slug'] as Map<String, dynamic>?;
    if (detailData == null || detailData['response'] == null) {
      throw CrawlerException('Failed to resolve mission detail: $slug');
    }
    return detailData['response'] as Map<String, dynamic>;
  }

  /// Releases HTTP client resources.
  void dispose() => _client.close();

  // ────────────────────────────────────────────────────────────────
  // Formatting helper methods
  // ────────────────────────────────────────────────────────────────

  /// Formats operator detailed map to a Markdown document.
  String formatOperatorToMarkdown(Map<String, dynamic> data) {
    final op = data['operator'] as Map<String, dynamic>? ?? {};
    final zhName = _getZh(op['name']);
    final rarity = op['rarity'] ?? 0;
    final profession = op['profession'] ?? '';
    final element = op['element'] ?? '';
    final profile = _getZh(op['profile']);

    final sb = StringBuffer();
    sb.writeln('# $zhName');
    sb.writeln('');
    sb.writeln('- 稀有度：$rarity 星');
    if (profession.isNotEmpty) sb.writeln('- 职业：$profession');
    if (element.isNotEmpty) sb.writeln('- 属性：$element');
    sb.writeln('');

    if (profile.isNotEmpty) {
      sb.writeln('## 个人简介');
      sb.writeln('$profile');
      sb.writeln('');
    }

    // Combat Stats (Max Level)
    final statsList = data['combatStats'] as List<dynamic>? ?? [];
    if (statsList.isNotEmpty) {
      statsList.sort((a, b) {
        final lvlA = (a['level'] as num?) ?? 0;
        final lvlB = (b['level'] as num?) ?? 0;
        return lvlB.compareTo(lvlA); // highest level first
      });
      final maxStats = statsList.first as Map<String, dynamic>;
      final level = maxStats['level'];
      final hp = maxStats['hp'];
      final atk = maxStats['atk'];
      final def = maxStats['def'];
      final thermalAtk = maxStats['thermalAtk'];
      final thermalDef = maxStats['thermalDef'];

      sb.writeln('## 基础属性（等级 $level）');
      if (hp != null) sb.writeln('- 生命上限：$hp');
      if (atk != null) sb.writeln('- 攻击力：$atk');
      if (def != null) sb.writeln('- 防御力：$def');
      if (thermalAtk != null) sb.writeln('- 元素攻击力：$thermalAtk');
      if (thermalDef != null) sb.writeln('- 元素防御力：$thermalDef');
      sb.writeln('');
    }

    // Talents
    final talents = data['talents'] as List<dynamic>? ?? [];
    if (talents.isNotEmpty) {
      sb.writeln('## 天赋设定');
      for (final t in talents) {
        final title = t['title'] ?? '';
        final desc = t['description'] ?? '';
        if (title.isNotEmpty) {
          sb.writeln('### $title');
          if (desc.isNotEmpty) sb.writeln('$desc');
          sb.writeln('');
        }
      }
    }

    // Skills
    final skills = data['skills'] as List<dynamic>? ?? [];
    if (skills.isNotEmpty) {
      sb.writeln('## 技能设定');
      for (final s in skills) {
        final title = s['title'] ?? '';
        final desc = s['description'] ?? '';
        if (title.isNotEmpty) {
          sb.writeln('### $title');
          if (desc.isNotEmpty) sb.writeln('$desc');
          sb.writeln('');
        }
      }
    }

    // Archive / Story
    final stories = data['story'] as List<dynamic>? ?? [];
    if (stories.isNotEmpty) {
      sb.writeln('## 档案资料');
      for (final st in stories) {
        final title = st['title'] ?? '';
        final content = st['content'] ?? '';
        if (title.isNotEmpty) {
          sb.writeln('### $title');
          if (content.isNotEmpty) sb.writeln('$content');
          sb.writeln('');
        }
      }
    }

    // Voice lines
    final voices = data['voices'] as List<dynamic>? ?? [];
    if (voices.isNotEmpty) {
      sb.writeln('## 语音记录');
      for (final v in voices) {
        final title = v['title'] ?? '';
        final desc = v['description'] ?? '';
        if (title.isNotEmpty) {
          sb.writeln('- **$title**：$desc');
        }
      }
      sb.writeln('');
    }

    return sb.toString().trim();
  }

  /// Formats lore detailed map to a Markdown document.
  String formatLoreToMarkdown(Map<String, dynamic> data) {
    final name = data['name'] ?? '';
    final typeName = data['typeName'] ?? '';
    final richContentTable =
        data['richContentTable'] as Map<String, dynamic>? ?? {};
    final contentList = richContentTable['contentList'] as List<dynamic>? ?? [];

    final sb = StringBuffer();
    sb.writeln('# $name');
    if (typeName.isNotEmpty) {
      sb.writeln('');
      sb.writeln('分类：$typeName');
    }
    sb.writeln('');

    if (contentList.isNotEmpty) {
      for (final item in contentList) {
        final text = (item as Map<String, dynamic>)['content'] ?? '';
        if (text.isNotEmpty) {
          sb.writeln('$text');
          sb.writeln('');
        }
      }
    }

    return sb.toString().trim();
  }

  /// Formats mission detailed map to a Markdown document.
  String formatMissionToMarkdown(Map<String, dynamic> data) {
    final name = data['name'] ?? '';
    final desc = data['desc'] ?? '';
    final typeName = data['typeName'] ?? '';
    final dialog = data['dialog'] as List<dynamic>? ?? [];

    final sb = StringBuffer();
    sb.writeln('# $name（$typeName任务）');
    sb.writeln('');
    if (desc.isNotEmpty) {
      sb.writeln('> $desc');
      sb.writeln('');
    }

    if (dialog.isNotEmpty) {
      sb.writeln('## 剧情对话');
      sb.writeln('');
      for (final item in dialog) {
        final talk = item as Map<String, dynamic>;
        final speaker = talk['speaker'] ?? '';
        final content = talk['content'] ?? '';
        final options = talk['options'] as List<dynamic>? ?? [];

        if (speaker.isNotEmpty || content.isNotEmpty) {
          if (speaker.isNotEmpty) {
            sb.writeln('**$speaker**：$content');
          } else {
            sb.writeln('$content');
          }
          if (options.isNotEmpty) {
            for (final opt in options) {
              sb.writeln('> *选择：$opt*');
            }
          }
          sb.writeln('');
        }
      }
    }

    return sb.toString().trim();
  }

  // ────────────────────────────────────────────────────────────────
  // Private Helpers
  // ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _fetchAndDecode(String url) async {
    final response = await _client.get(
      Uri.parse(url),
      headers: {'User-Agent': _userAgent},
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw CrawlerException(
        'HTTP Request failed for $url',
        statusCode: response.statusCode,
        uri: url,
      );
    }

    final body = response.body;
    return await Isolate.run(() {
      final rawArray = jsonDecode(body);
      if (rawArray is! List<dynamic>) {
        throw CrawlerException('Remix response is not a JSON array', uri: url);
      }
      return decodeRemixStream(rawArray);
    });
  }

  String _getZh(dynamic value) {
    if (value is String) return value;
    if (value is Map) {
      return (value['zh'] as String?) ?? '';
    }
    return '';
  }
}

// ──────────────────────────────────────────────────────────────────
// Remix Stream Decoder (Top-Level Function)
// ──────────────────────────────────────────────────────────────────

/// Decodes a Remix single-fetch stream array into a resolved Map by recursively
/// resolving integer references and the `_N` key-name encoding.
Map<String, dynamic> decodeRemixStream(List<dynamic> arr) {
  if (arr.length < 2) return {};

  final result = <String, dynamic>{};

  dynamic resolve(dynamic val, int depth) {
    if (depth > 100) return null; // Safety depth limit

    if (val is int) {
      if (val >= 0 && val < arr.length) {
        return resolve(arr[val], depth + 1);
      }
      return val;
    }

    if (val is Map) {
      final refKeys =
          val.keys.where((k) => k is String && k.startsWith('_')).toList();

      if (refKeys.isNotEmpty) {
        final built = <String, dynamic>{};
        for (final refKey in refKeys) {
          final idx = int.parse(refKey.substring(1));
          final resolvedKey = resolve(idx, depth + 1);
          if (resolvedKey is String) {
            built[resolvedKey] = resolve(val[refKey], depth + 1);
          }
        }
        return built;
      }

      return val.map((k, v) => MapEntry<String, dynamic>(
            k.toString(),
            resolve(v, depth + 1),
          ));
    }

    if (val is List) {
      return val.map((v) => resolve(v, depth + 1)).toList();
    }

    return val;
  }

  int i = 1;
  while (i < arr.length) {
    final key = arr[i];
    if (key is String) {
      if (i + 1 < arr.length) {
        result[key] = resolve(arr[i + 1], 0);
        i += 2;
      } else {
        i++;
      }
    } else {
      i++;
    }
  }

  return result;
}

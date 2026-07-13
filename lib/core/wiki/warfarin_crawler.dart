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
  // Response Extraction Helpers
  // ────────────────────────────────────────────────────────────────

  /// Extracts listing items from a decoded Remix index response,
  /// handling both `response` as direct List and `response.data` as List.
  List<WarfarinListingItem> _extractListingItems(Map<String, dynamic>? indexData) {
    if (indexData == null) return [];
    final rawResponse = _unwrapRemixResponse(indexData);
    List<dynamic> rawList;
    if (rawResponse is List) {
      rawList = rawResponse;
    } else if (rawResponse is Map && rawResponse['data'] is List) {
      rawList = rawResponse['data'] as List<dynamic>;
    } else {
      return [];
    }
    return rawList
        .map((item) {
          final map = item as Map<String, dynamic>;
          return WarfarinListingItem(
            slug: (map['slug'] as String?) ?? '',
            name: _getZh(map['name']),
          );
        })
        .where((item) => item.slug.isNotEmpty)
        .toList();
  }

  /// Extracts the route data from a decoded route map, unwrapping
  /// the `{"data": ...}` envelope used by Remix single-fetch.
  Map<String, dynamic>? _extractRouteData(Map<String, dynamic>? decoded) {
    if (decoded == null) return null;
    final routeData = decoded['data'];
    if (routeData is Map<String, dynamic>) return routeData;
    return null;
  }

  /// Unwraps a Remix response that may be wrapped in `{"data": ...}`.
  dynamic _unwrapRemixResponse(Map<String, dynamic> routeData) {
    final raw = routeData['response'];
    if (raw is Map && raw['data'] != null) return raw['data'];
    return raw;
  }

  /// Unwraps a detail response, extracting `data` if the response is
  /// a wrapper Map with `data` key (Remix single-fetch format).
  Map<String, dynamic> _unwrapResponse(dynamic rawResponse) {
    if (rawResponse is Map && rawResponse['data'] is Map) {
      return rawResponse['data'] as Map<String, dynamic>;
    }
    return rawResponse as Map<String, dynamic>;
  }

  // ────────────────────────────────────────────────────────────────
  // Public API
  // ────────────────────────────────────────────────────────────────

  /// Fetches all operator slugs.
  Future<List<String>> fetchOperatorSlugs() async {
    final items = await fetchOperatorListings();
    return items.map((e) => e.slug).toList();
  }

  /// Fetches operator listing items (slug + display name).
  Future<List<WarfarinListingItem>> fetchOperatorListings() async {
    final decoded = await _fetchAndDecode('$_baseUrl/operators.data');
    final rawRoute =
        decoded['routes/\$lang.operators._index'] as Map<String, dynamic>?;
    final routeData = _extractRouteData(rawRoute);
    return _extractListingItems(routeData);
  }

  /// Fetches a single operator's detail page and returns the parsed Map.
  Future<Map<String, dynamic>> fetchOperatorDetail(String slug) async {
    final decoded = await _fetchAndDecode('$_baseUrl/operators/$slug.data');
    final rawRoute =
        decoded['routes/\$lang.operators.\$slug'] as Map<String, dynamic>?;
    final routeData = _extractRouteData(rawRoute);
    if (routeData == null || routeData['response'] == null) {
      throw CrawlerException('Failed to resolve operator detail: $slug');
    }
    return _unwrapResponse(routeData['response']);
  }

  /// Fetches all lore/story slugs.
  Future<List<String>> fetchLoreSlugs() async {
    final items = await fetchLoreListings();
    return items.map((e) => e.slug).toList();
  }

  /// Fetches lore listing items (slug + display name).
  Future<List<WarfarinListingItem>> fetchLoreListings() async {
    final decoded = await _fetchAndDecode('$_baseUrl/lore.data');
    final rawRoute =
        decoded['routes/\$lang.lore._index'] as Map<String, dynamic>?;
    final routeData = _extractRouteData(rawRoute);
    return _extractListingItems(routeData);
  }

  /// Fetches a single lore's detail.
  Future<Map<String, dynamic>> fetchLoreDetail(String slug) async {
    final decoded = await _fetchAndDecode('$_baseUrl/lore/$slug.data');
    final rawRoute =
        decoded['routes/\$lang.lore.\$slug'] as Map<String, dynamic>?;
    final routeData = _extractRouteData(rawRoute);
    if (routeData == null || routeData['response'] == null) {
      throw CrawlerException('Failed to resolve lore detail: $slug');
    }
    return _unwrapResponse(routeData['response']);
  }

  /// Fetches all mission slugs.
  Future<List<String>> fetchMissionSlugs() async {
    final items = await fetchMissionListings();
    return items.map((e) => e.slug).toList();
  }

  /// Fetches mission listing items (slug + display name).
  Future<List<WarfarinListingItem>> fetchMissionListings() async {
    final decoded = await _fetchAndDecode('$_baseUrl/missions.data');
    final rawRoute =
        decoded['routes/\$lang.missions._index'] as Map<String, dynamic>?;
    final routeData = _extractRouteData(rawRoute);
    return _extractListingItems(routeData);
  }

  /// Fetches a single mission's detail.
  Future<Map<String, dynamic>> fetchMissionDetail(String slug) async {
    final decoded = await _fetchAndDecode('$_baseUrl/missions/$slug.data');
    final rawRoute =
        decoded['routes/\$lang.missions.\$slug'] as Map<String, dynamic>?;
    final routeData = _extractRouteData(rawRoute);
    if (routeData == null || routeData['response'] == null) {
      throw CrawlerException('Failed to resolve mission detail: $slug');
    }
    return _unwrapResponse(routeData['response']);
  }

  /// Releases HTTP client resources.
  void dispose() => _client.close();

  // ────────────────────────────────────────────────────────────────
  // Formatting helper methods
  // ────────────────────────────────────────────────────────────────

  static const Map<int, String> _professionNames = {
    0: '近卫',
    2: '重装',
    4: '辅助',
    5: '术师',
    7: '先锋',
    8: '突击',
  };

  static const Map<String, String> _blocNames = {
    'power_rhodes': '罗德岛',
    'power_endfield': '终末地工业',
  };

  static const Map<String, String> _raceNames = {
    'cat': '菲林',
    'fox': '沃尔珀',
    'lupo': '鲁珀',
    'bird': '黎博利',
    'liberi': '黎博利',
    'perro': '佩洛',
    'ursus': '乌萨斯',
    'lung': '龙',
    'draco': '德拉克',
    'vouivre': '瓦伊凡',
    'sarkaz': '萨卡兹',
    'savra': '萨弗拉',
    'on': '阿',
    'zalak': '札拉克',
    'elafia': '埃拉菲亚',
    'anaty': '阿纳缇',
    'feline': '菲林',
    'rabbit': '卡特斯',
  };

  static const Map<String, String> _tagPrefix = {
    'tag_race_': '种族',
    'tag_bloc_': '阵营',
    'tag_expert_': '专长',
    'tag_hobby_': '爱好',
    'tag_activity_': '行事',
  };

  static const Map<String, String> _voiceCategory = {
    '行动准备': '    ',
    '编入队伍': '    ',
    '作战': '    ',
    '战斗': '    ',
  };

  /// Strips <@...> game markup tags from a string.
  static String _stripGameTags(String text) {
    return text.replaceAll(RegExp(r'<@[^>]+>'), '');
  }

  /// Formats operator detailed map to a Markdown document.
  String formatOperatorToMarkdown(Map<String, dynamic> data) {
    final ct = data['characterTable'] as Map<String, dynamic>? ?? {};
    final cgt = data['charGrowthTable'] as Map<String, dynamic>? ?? {};
    final tagt = data['charTagTable'] as Map<String, dynamic>? ?? {};
    final tagDes = (data['charTagDesTable']
            as Map<String, dynamic>?)?['tagDesc'] as Map<String, dynamic>? ??
        {};

    final name = _getZh(ct['name']) ?? '';
    final engName = ct['engName'] as String? ?? '';
    final rarity = cgt['rarity'] as int? ?? 0;
    final profId = cgt['profession'] as int? ?? -1;
    final profession = profId >= 0 ? (_professionNames[profId] ?? '') : '';
    final charTypeId = ct['charTypeId'] as String? ?? '';
    final cvData = ct['cvName'] as Map<String, dynamic>? ?? {};
    final profileRecord = ct['profileRecord'] as List<dynamic>? ?? [];
    final profileVoice = ct['profileVoice'] as List<dynamic>? ?? [];

    final sb = StringBuffer();
    sb.writeln('# $name');
    if (engName.isNotEmpty) {
      sb.writeln('> $engName');
    }
    sb.writeln('');
    sb.writeln('- 稀有度：$rarity 星');
    if (profession.isNotEmpty) sb.writeln('- 职业：$profession');
    if (charTypeId.isNotEmpty) sb.writeln('- 属性：$charTypeId');

    // Faction
    final blocId = tagt['blocId'] as String? ?? '';
    if (blocId.isNotEmpty) {
      final blocName = _blocNames[blocId] ?? blocId;
      sb.writeln('- 阵营：$blocName');
    }

    // Race
    final raceId = tagt['raceTagId'] as String? ?? '';
    final raceName = _resolveRace(raceId);
    if (raceName.isNotEmpty) {
      sb.writeln('- 种族：$raceName');
    }

    // Expertise & Hobbies via tags
    final expertIds = tagt['expertTagIds'] as List<dynamic>? ?? [];
    for (final eid in expertIds) {
      final desc = _resolveTag('$eid', tagDes);
      if (desc.isNotEmpty) {
        sb.writeln('- 专长：$desc');
      }
    }
    final hobbyIds = tagt['hobbyTagIds'] as List<dynamic>? ?? [];
    for (final hid in hobbyIds) {
      final desc = _resolveTag('$hid', tagDes);
      if (desc.isNotEmpty) {
        sb.writeln('- 爱好：$desc');
      }
    }

    // CV
    final chiCv = cvData['ChiCVName'] as String? ?? '';
    if (chiCv.isNotEmpty) sb.writeln('- 中文CV：$chiCv');
    sb.writeln('');

    // Profile records (archive)
    for (final record in profileRecord) {
      final r = record as Map<String, dynamic>;
      final title = r['recordTitle'] as String? ?? '';
      var desc = r['recordDesc'] as String? ?? '';
      desc = _stripGameTags(desc).trim();

      if (title.isNotEmpty || desc.isNotEmpty) {
        final sectionTitle =
            title.replaceAll(RegExp(r'<@[^>]+>'), '').trim();
        if (sectionTitle.isNotEmpty) {
          sb.writeln('## $sectionTitle');
          sb.writeln('');
        }
        if (desc.isNotEmpty) {
          sb.writeln(desc);
          sb.writeln('');
        }
      }
    }

    // Skills from skillGroupMap
    final skillGroupMap =
        cgt['skillGroupMap'] as Map<String, dynamic>? ?? {};
    if (skillGroupMap.isNotEmpty) {
      sb.writeln('## 技能设定');
      sb.writeln('');
      for (final entry in skillGroupMap.entries) {
        final sg = entry.value as Map<String, dynamic>? ?? {};
        final skillName = sg['name'] as String? ?? '';
        final skillDesc = sg['desc'] as String? ?? '';
        if (skillName.isNotEmpty || skillDesc.isNotEmpty) {
          sb.writeln('### $skillName');
          if (skillDesc.isNotEmpty) {
            sb.writeln(skillDesc);
            sb.writeln('');
          }
        }
      }
    }

    // Voice lines
    if (profileVoice.isNotEmpty) {
      sb.writeln('## 语音记录');
      sb.writeln('');
      for (final v in profileVoice) {
        final voice = v as Map<String, dynamic>;
        final title = voice['voiceTitle'] as String? ?? '';
        final desc = voice['voiceDesc'] as String? ?? '';
        if (title.isNotEmpty && desc.isNotEmpty) {
          sb.writeln('**$title**');
          sb.writeln('');
          sb.writeln('$desc');
          sb.writeln('');
        }
      }
    }

    return sb.toString().trim();
  }

  /// Resolves a race tag ID to its Chinese name.
  String _resolveRace(String tagId) {
    if (tagId.isEmpty) return '';
    // Try direct key (e.g. 'tag_race_cat')
    final direct = _raceNames[tagId];
    if (direct != null) return direct;
    // Strip prefix and try (e.g. 'cat')
    const prefix = 'tag_race_';
    if (tagId.startsWith(prefix)) {
      final stripped = tagId.substring(prefix.length);
      return _raceNames[stripped] ?? stripped;
    }
    return tagId;
  }

  /// Resolves a tag ID to its human-readable description.
  String _resolveTag(String tagId, Map<String, dynamic> tagDes) {
    if (tagId.isEmpty) return '';
    // Direct lookup
    final entry = tagDes[tagId] as Map<String, dynamic>?;
    if (entry != null) {
      final desc = entry['desc'] as String? ?? '';
      if (desc.isNotEmpty) return desc;
    }
    // Fallback: strip prefix
    for (final prefix in _tagPrefix.keys) {
      if (tagId.startsWith(prefix)) {
        return tagId.substring(prefix.length);
      }
    }
    return tagId;
  }

  /// Formats lore detailed map to a Markdown document.
  String formatLoreToMarkdown(Map<String, dynamic> data) {
    final prtsItem =
        data['prtsAllItem'] as Map<String, dynamic>? ?? {};
    final name = _getZh(prtsItem['name']) ?? '';
    final type = prtsItem['type'] as String? ?? '';

    final rct = data['richContentTable'] as Map<String, dynamic>? ?? {};
    final title = rct['title'] as String? ?? '';
    final contentList = rct['contentList'] as List<dynamic>? ?? [];

    final sb = StringBuffer();
    final displayName = name.isNotEmpty ? name : title;
    sb.writeln('# $displayName');
    sb.writeln('');

    if (type.isNotEmpty) {
      sb.writeln('分类：$type');
      sb.writeln('');
    }

    if (contentList.isNotEmpty) {
      for (final item in contentList) {
        final text = (item as Map<String, dynamic>)['content'] as String? ?? '';
        if (text.isNotEmpty && !text.startsWith('<image>')) {
          sb.writeln(text);
          sb.writeln('');
        }
      }
    }

    return sb.toString().trim();
  }

  /// Formats mission detailed map to a Markdown document.
  String formatMissionToMarkdown(Map<String, dynamic> data) {
    final mission = data['mission'] as Map<String, dynamic>? ?? {};
    final name = '${mission['name'] ?? ''}';
    final typeName = '${mission['typeName'] ?? ''}';
    final desc = '${mission['description'] ?? ''}';
    final dialog = data['dialog'] as List<dynamic>? ?? [];

    final sb = StringBuffer();
    if (typeName.isNotEmpty) {
      sb.writeln('# $name（$typeName）');
    } else {
      sb.writeln('# $name');
    }
    sb.writeln('');
    if (desc.isNotEmpty) {
      sb.writeln('> $desc');
      sb.writeln('');
    }

    if (dialog.isNotEmpty) {
      sb.writeln('## 剧情对话');
      sb.writeln('');
      for (final item in dialog) {
        final d = item as Map<String, dynamic>;
        final speaker = d['actorName'] as String? ?? '';
        final text = d['dialogText'] as String? ?? '';
        final type = d['type'] as String? ?? '';

        if (type == 'action' || type == 'event') continue;

        if (speaker.isNotEmpty && text.isNotEmpty) {
          sb.writeln('**$speaker**：$text');
          sb.writeln('');
        } else if (text.isNotEmpty) {
          sb.writeln(text);
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

    final bytes = response.bodyBytes;
    return Isolate.run(() {
      final body = utf8.decode(bytes);
      final rawArray = jsonDecode(body);
      if (rawArray is! List<dynamic>) {
        throw CrawlerException('Remix response is not a JSON array', uri: url);
      }
      return decodeRemixStream(rawArray);
    }).timeout(const Duration(seconds: 30));
  }

  String _getZh(dynamic value) {
    if (value is String) return value;
    if (value is Map) {
      return (value['zh'] as String?) ?? '';
    }
    return '';
  }
}

/// A listing item from Warfarin Wiki index endpoints.
class WarfarinListingItem {
  final String slug;
  final String name;
  const WarfarinListingItem({required this.slug, required this.name});
}

// ──────────────────────────────────────────────────────────────────
// Remix Stream Decoder (Top-Level Function)
// ──────────────────────────────────────────────────────────────────

/// Decodes a Remix single-fetch stream array into a resolved Map by recursively
/// resolving integer references and the `_N` key-name encoding.
Map<String, dynamic> decodeRemixStream(List<dynamic> arr) {
  if (arr.length < 2) return {};

  final result = <String, dynamic>{};
  final memo = <int, dynamic>{};

  dynamic resolve(dynamic val, int depth) {
    if (depth > 100) return null;

    if (val is int) {
      if (val >= 0 && val < arr.length) {
        if (memo.containsKey(val)) return memo[val];
        final target = arr[val];
        // Primitives (strings, numbers, booleans, null) are literal values,
        // not references to further array positions.
        if (target is! Map && target is! List) {
          memo[val] = target;
          return target;
        }
        final resolved = resolve(target, depth + 1);
        memo[val] = resolved;
        return resolved;
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

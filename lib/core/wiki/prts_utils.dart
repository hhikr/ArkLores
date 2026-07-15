/// Pure-Dart utility functions for PRTS Wiki content parsing and formatting.
///
/// Extracted from WikiIndexingNotifier so both the Flutter app and the CLI
/// seed builder can import them without Flutter dependencies.
library;

/// Parses all occurrences of a template in a mediawiki wikitext.
///
/// When [exactMatch] is true (default), only templates whose name exactly
/// matches [templateName] are returned — e.g. searching for "人员档案" will
/// NOT match "人员档案set". Set to false for legacy prefix matching.
List<Map<String, String>> parseAllTemplates(
  String wikitext,
  String templateName, {
  bool exactMatch = true,
}) {
  final results = <Map<String, String>>[];
  final startKey = '{{$templateName';

  int searchOffset = 0;
  while (true) {
    int startIdx = wikitext.indexOf(startKey, searchOffset);
    if (startIdx == -1) {
      startIdx =
          wikitext.toLowerCase().indexOf(startKey.toLowerCase(), searchOffset);
      if (startIdx == -1) break;
    }

    if (exactMatch) {
      final afterKey = startIdx + startKey.length;
      if (afterKey < wikitext.length) {
        final nextChar = wikitext[afterKey];
        if (nextChar != '|' &&
            nextChar != '}' &&
            nextChar != '\n' &&
            nextChar != '\r' &&
            nextChar != ' ' &&
            nextChar != '\t') {
          searchOffset = afterKey;
          continue;
        }
      }
    }

    // Find matching closing }}
    var depth = 2;
    var endIdx = startIdx + startKey.length;
    while (endIdx < wikitext.length - 1 && depth > 0) {
      if (wikitext[endIdx] == '{' && wikitext[endIdx + 1] == '{') {
        depth++;
        endIdx += 2;
      } else if (wikitext[endIdx] == '}' && wikitext[endIdx + 1] == '}') {
        depth--;
        endIdx += 2;
      } else {
        endIdx++;
      }
    }

    final content = wikitext.substring(startIdx + startKey.length, endIdx - 2);
    searchOffset = endIdx;

    // Parse key=value pairs
    final params = <String, String>{};
    final paramParts = _splitTemplateParams(content);
    for (final part in paramParts) {
      final eqIdx = part.indexOf('=');
      if (eqIdx > 0) {
        final key = part.substring(0, eqIdx).trim();
        var value = part.substring(eqIdx + 1).trim();
        // Handle multiline values and nested brackets
        value = _unwrapValue(value);
        if (key.isNotEmpty) {
          params[key] = value;
        }
      }
    }

    if (params.isNotEmpty) {
      results.add(params);
    }
  }

  return results;
}

Map<String, String> parseTemplate(String wikitext, String templateName) {
  final list = parseAllTemplates(wikitext, templateName);
  return list.isEmpty ? <String, String>{} : list.first;
}

/// Cleans wikitext/HTML styling markup to obtain pure readable text.
String cleanFormattedText(String text) {
  var clean = text;
  clean = clean.replaceAllMapped(
    RegExp(r'\{\{[Cc]olor\|#[0-9A-Fa-f]{6}\|([^}]+)\}\}'),
    (m) => m.group(1)!,
  );
  clean = clean.replaceAllMapped(
    RegExp(r'\{\{术语\|[^|]*\|([^}]+)\}\}'),
    (m) => m.group(1)!,
  );
  clean = clean.replaceAll(RegExp(r'\{\{popup\|内容=[^}]*\}\}'), '');
  clean = clean.replaceAll(RegExp(r'<[^>]*>'), '');
  clean = clean.replaceAllMapped(
    RegExp(r'\[\[(?:[^|\]]*\|)?([^\]]+)\]\]'),
    (m) => m.group(1)!,
  );
  clean = clean.replaceAll(RegExp(r'\{\{[^{}]*\}\}'), '');
  return clean.trim();
}

/// Cleans wikitext script macros and templates from Arknights story pages.
///
/// Removes [Character(...)], [Background(...)], [PlayMusic(...)], HTML comments,
/// and navigation templates, keeping only actual dialogues and narrations.
String cleanStoryContent(String rawContent) {
  var content = rawContent;

  final match = RegExp(r'\n\[[Ii]mage\](?:\r?\n|$)').firstMatch(content);
  if (match != null) {
    content = content.substring(0, match.start);
  }

  content = content.replaceAllMapped(
    RegExp(r'\[name="([^"]+)"\]\s*'),
    (match) => '${match.group(1)}：',
  );

  content = content.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  content = content.replaceAll(RegExp(r'\{\{[Nn]avigator/[^}]*\}\}'), '');
  content = content.replaceAll(RegExp(r'\{\{[Pp]lot[^}]*\}\}'), '');
  content = content.replaceAll(RegExp(r'\{\{剧情模拟器[^}]*'), '');
  content = content.replaceAll(RegExp(r'\[[A-Za-z0-9_]+(?:\([^)]*\))?\]'), '');
  content = content.replaceAll(RegExp(r'\[[A-Za-z_]+=[^\]]*\]'), '');
  content = content.replaceAll(RegExp(r'\[[A-Za-z0-9_]+.*?\]'), '');

  final lines = content.split('\n');
  final cleanLines = lines.map((line) => line.trim()).where((line) {
    if (line.isEmpty) return false;
    if (line.startsWith('{{') && line.endsWith('}}')) return false;
    return true;
  }).toList();

  return cleanLines.join('\n');
}

/// Assembles operator raw wikitexts (main page, voice, token) into a unified markdown.
///
/// If [recordStoryWikitexts] is provided (map of story page title → raw wikitext),
/// operator record sections will include the full cleaned story dialogue instead
/// of just a page link.
String assembleOperatorMarkdown(
  String operatorName,
  String mainWikitext,
  String voiceWikitext,
  String tokenWikitext, {
  Map<String, String>? recordStoryWikitexts,
}) {
  final sb = StringBuffer();
  sb.writeln('# $operatorName\n');

  final archivesSet = parseTemplate(mainWikitext, '人员档案set');
  final archives = parseTemplate(mainWikitext, '人员档案');

  sb.writeln('## 个人档案');
  final basicFields = <String, String>{
    '性别': '性别',
    '战斗经验': '战斗经验',
    '出身地': '出身地',
    '生日': '生日',
    '种族': '种族',
    '身高': '身高',
    '矿石病感染情况': '矿石病感染情况',
    '物理强度': '物理强度',
    '战场机动': '战场机动',
    '生理耐受': '生理耐受',
    '战术规划': '战术规划',
    '战斗技巧': '战斗技巧',
    '源石技艺适应性': '源石技艺适应性',
    '体细胞与源石融合率': '体细胞与源石融合率',
    '血液源石结晶密度': '血液源石结晶密度',
  };

  for (final entry in basicFields.entries) {
    final val = archivesSet[entry.key];
    if (val != null && val.trim().isNotEmpty) {
      sb.writeln('- ${entry.value}：${val.trim()}');
    }
  }
  sb.writeln('');

  for (int i = 1; i <= 15; i++) {
    final title = archives['档案$i'];
    final text = archives['档案$i文本'];
    if (title != null &&
        title.trim().isNotEmpty &&
        text != null &&
        text.trim().isNotEmpty) {
      sb.writeln('### ${title.trim()}');
      sb.writeln('${text.trim()}\n');
    }
  }

  final tokenRel = parseTemplate(mainWikitext, '相关道具');
  final contract = tokenRel['干员简介'] ?? '';
  final contractSupp = tokenRel['干员简介补充'] ?? '';
  if (contract.isNotEmpty || contractSupp.isNotEmpty) {
    sb.writeln('## 招聘合同');
    if (contract.isNotEmpty) {
      sb.writeln(cleanFormattedText(contract));
    }
    if (contractSupp.isNotEmpty) {
      sb.writeln('\n${cleanFormattedText(contractSupp)}');
    }
    sb.writeln('');
  }

  final talentTemplates = parseAllTemplates(mainWikitext, '天赋列表3');
  if (talentTemplates.isNotEmpty) {
    sb.writeln('## 天赋设定');
    for (final t in talentTemplates) {
      final name = t['天赋1'] ?? '';
      final category = t['天赋'] ?? '';
      if (name.isNotEmpty) {
        sb.writeln('- $category：$name');
      }
    }
    sb.writeln('');
  }

  final seenSkillNames = <String>{};
  final skillTemplates = <Map<String, String>>[
    ...parseAllTemplates(mainWikitext, '技能'),
    ...parseAllTemplates(mainWikitext, '技能2'),
  ];
  if (skillTemplates.isNotEmpty) {
    sb.writeln('## 技能设定');
    for (final s in skillTemplates) {
      final name = s['技能名'] ?? '';
      if (name.isNotEmpty && seenSkillNames.add(name)) {
        sb.writeln('- 技能：$name');
      }
    }
    sb.writeln('');
  }

  final baseTemplates = parseAllTemplates(mainWikitext, '后勤技能');
  if (baseTemplates.isNotEmpty) {
    sb.writeln('## 后勤技能');
    for (final b in baseTemplates) {
      for (int j = 1; j <= 5; j++) {
        for (int k = 1; k <= 5; k++) {
          final name = b['后勤技能$j-$k'];
          final phase = b['后勤技能$j-$k阶段'] ?? '';
          if (name != null && name.trim().isNotEmpty) {
            final phaseStr = phase.isNotEmpty ? '（$phase）' : '';
            sb.writeln('- 后勤技能$phaseStr：${name.trim()}');
          }
        }
      }
    }
    sb.writeln('');
  }

  final moduleTemplates = parseAllTemplates(mainWikitext, '模组');
  if (moduleTemplates.isNotEmpty) {
    sb.writeln('## 模组设定');
    for (final m in moduleTemplates) {
      final name = m['名称'] ?? '';
      final info = m['基础信息'] ?? '';
      if (name.isNotEmpty) {
        sb.writeln('### 模组：$name');
        if (info.isNotEmpty) {
          final cleanInfo = cleanFormattedText(
              info.replaceAll('<br>', '\n').replaceAll('<br/>', '\n'));
          sb.writeln('$cleanInfo\n');
        }
      }
    }
  }

  final paradoxTemplates = parseAllTemplates(mainWikitext, '悖论模拟');
  if (paradoxTemplates.isNotEmpty) {
    sb.writeln('## 悖论模拟');
    for (final p in paradoxTemplates) {
      final name = p['name'] ?? '';
      final desc = p['description'] ?? '';
      if (name.isNotEmpty) {
        sb.writeln('### 悖论模拟：$name');
        if (desc.isNotEmpty) {
          sb.writeln('${cleanFormattedText(desc)}\n');
        }
      }
    }
  }

  final miluTemplates = parseAllTemplates(mainWikitext, '干员密录/list');
  if (miluTemplates.isNotEmpty) {
    sb.writeln('## 干员密录');
    for (final m in miluTemplates) {
      final name = m['storySetName'] ?? '';
      if (name.isEmpty) continue;
      sb.writeln('### $name');
      for (int j = 1; j <= 20; j++) {
        final rawPage = m['storyTxt$j'] ?? '';
        if (rawPage.isEmpty) break;
        final resolvedPage = rawPage
            .replaceAll('{{FULLPAGENAME}}', operatorName)
            .replaceFirst(RegExp(r'\s*\}\}+\s*$'), '')
            .trim();
        if (resolvedPage.isEmpty) continue;
        final intro = m['storyIntro$j'] ?? '';
        if (intro.isNotEmpty) {
          sb.writeln('${cleanFormattedText(intro)}\n');
        }
        if (recordStoryWikitexts != null &&
            recordStoryWikitexts.containsKey(resolvedPage)) {
          final cleaned =
              cleanStoryContent(recordStoryWikitexts[resolvedPage]!);
          sb.writeln(cleaned);
          sb.writeln('');
        } else if (resolvedPage.isNotEmpty) {
          sb.writeln('（剧情页面：$resolvedPage）\n');
        }
      }
    }
  }

  if (tokenWikitext.isNotEmpty) {
    final tokenInfo = parseTemplate(tokenWikitext, '道具信息');
    final tokenDesc = tokenInfo['itemDesc'] ?? '';
    if (tokenDesc.isNotEmpty) {
      sb.writeln('## 信物');
      sb.writeln('${cleanFormattedText(tokenDesc)}\n');
    }
  }

  if (voiceWikitext.isNotEmpty) {
    sb.writeln('## 语音记录');
    final voiceLines = parseAllTemplates(voiceWikitext, '语音');
    for (final v in voiceLines) {
      final title = v['标题'] ?? v['title'] ?? '';
      final textCN = v['中文'] ?? v['cn'] ?? '';
      final textJP = v['日文'] ?? v['jp'] ?? '';
      if (title.isNotEmpty) {
        sb.writeln('**$title**');
        if (textCN.isNotEmpty) {
          sb.writeln('$textCN\n');
        }
        if (textJP.isNotEmpty) {
          sb.writeln('$textJP\n');
        }
      }
    }
  }

  return sb.toString();
}

// ── Internal helpers ─────────────────────────────────────────────────────────

/// Splits template parameter content by `|`, respecting nested brackets.
List<String> _splitTemplateParams(String content) {
  final parts = <String>[];
  var depth = 0;
  var start = 0;

  for (var i = 0; i < content.length; i++) {
    final char = content[i];
    if (char == '{' || char == '[') {
      depth++;
    } else if (char == '}' || char == ']') {
      depth--;
    } else if (char == '|' && depth == 0) {
      parts.add(content.substring(start, i));
      start = i + 1;
    }
  }

  if (start < content.length) {
    parts.add(content.substring(start));
  }

  return parts;
}

/// Unwraps a value string by trimming whitespace and normalizing newlines.
String _unwrapValue(String value) {
  return value.trim();
}

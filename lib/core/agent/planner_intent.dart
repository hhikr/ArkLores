/// Intent protocol for the planner loop (R8, M-A).
///
/// The decision agent outputs exactly ONE intent per call — a short,
/// machine-parseable line — instead of the verbose ReAct Thought/Action/
/// Observation format. Short output means the request never grows with the
/// investigation and format compliance is high (the 103-iteration repeat loop
/// was driven by Thought-prefix drift in long-form output).
library;

import 'dart:convert';

/// A parsed intent.
class IntentRecord {
  const IntentRecord({required this.action, required this.args});
  final String action; // READ | SEARCH | COVER | FIND | MAP | OUTLINE | COLLECT | SUMMARIZE | ANSWER | DONE | RESELECT
  final Map<String, dynamic> args;
}

/// R16: splits `<intent> # <plan>` into the intent and the planner's plan
/// note ('' when absent).
({String intent, String plan}) splitPlanNote(String raw) {
  final text = raw.trim();
  final mark = RegExp(r'\s*[#＃]\s*').firstMatch(text);
  if (mark == null) return (intent: text, plan: '');
  final note = text.substring(mark.end).replaceAll(RegExp(r'\s+'), ' ').trim();
  return (
    intent: text.substring(0, mark.start).trim(),
    plan: note.length > 80 ? '${note.substring(0, 80)}…' : note,
  );
}

/// Parses one intent line (or a JSON-ish object) into an [IntentRecord].
///
/// Returns null when the line is not a valid intent — including a line that
/// contains more than one intent (multi-intent lines are rejected wholesale so
/// the model cannot silently drop actions; R11).
IntentRecord? parseIntent(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;
  final upper = trimmed.toUpperCase();

  if (upper == 'DONE') return const IntentRecord(action: 'DONE', args: {});

  for (final prefix in const [
    'READ',
    'SEARCH',
    'COVER',
    'FIND',
    'MAP',
    'OUTLINE',
    'COLLECT',
    'SUMMARIZE',
    'ANSWER',
    'VERDICT',
    'RESELECT',
  ]) {
    if (upper == prefix || upper.startsWith('$prefix ')) {
      // Reject multi-intent lines: after the matched prefix the rest must be
      // a single line with no other intent keyword.
      final rest = trimmed.substring(prefix.length).trim();
      if (RegExp(
        r'^(READ|SEARCH|COVER|FIND|MAP|OUTLINE|COLLECT|SUMMARIZE|ANSWER|VERDICT|RESELECT|DONE)\b',
        multiLine: true,
      ).hasMatch(rest)) {
        return null;
      }
      final args = <String, dynamic>{};
      try {
        // Intent lines are strict space-separated, but tolerate a leading
        // JSON object for tools that need it (COLLECT/SEARCH).
        if (rest.startsWith('{')) {
          final jsonEnd = _findJsonEnd(rest);
          if (jsonEnd > 0) {
            final decoded = jsonDecode(rest.substring(0, jsonEnd));
            if (decoded is Map) {
              args.addAll(decoded.map((k, v) => MapEntry('$k', v)));
            }
          }
        }
        if (args.isEmpty) {
          switch (prefix) {
            case 'READ':
            case 'SUMMARIZE':
              final tokens = rest.split(RegExp(r'\s+'));
              if (tokens.isEmpty || tokens.first.isEmpty) return null;
              args['story_id'] = tokens.first;
              // R14: `READ id 30-90` (one range token) is as common as
              // `READ id 30 90`; it used to be dropped, restarting at line 0.
              final range = tokens.length >= 2
                  ? RegExp(r'^(\d+)\s*[-–~]\s*(\d+)$').firstMatch(tokens[1])
                  : null;
              if (range != null) {
                args['start_line'] = int.parse(range.group(1)!);
                args['end_line'] = int.parse(range.group(2)!);
              } else if (tokens.length >= 3) {
                args['start_line'] = int.tryParse(tokens[1]);
                args['end_line'] = int.tryParse(tokens[2]);
              } else if (tokens.length >= 2) {
                // READ id 200 — start line only
                args['start_line'] = int.tryParse(tokens[1]);
              }
            case 'MAP':
              final tokens = rest.split(RegExp(r'\s+'));
              if (tokens.isEmpty || tokens.first.isEmpty) return null;
              args['scope_id'] = tokens.first;
            case 'OUTLINE':
              // R14: `OUTLINE <故事集名|scope_id|story_id>` — a collection
              // name may contain spaces, so the whole rest is the target.
              final target = _unquote(
                rest
                    .replaceAll(RegExp(r'^[《「]'), '')
                    .replaceAll(RegExp(r'[》」]$'), ''),
              );
              if (target.isEmpty) return null;
              args['target'] = target;
            case 'COLLECT':
              final tokens = rest.split(RegExp(r'\s+'));
              if (tokens.isEmpty || tokens.first.isEmpty) return null;
              args['entity_id'] = tokens.first;
              if (tokens.length > 1) {
                // terms=[a,b] scope_ids=[c,d] (`claim_terms=` is the pre-R13
                // spelling of `terms=`)
                for (final token in tokens.skip(1)) {
                  final kv = RegExp(r'^([a-z_]+)=\[(.+)\]$')
                      .firstMatch(token.trim());
                  if (kv != null) {
                    final key = kv.group(1)!;
                    final values = kv
                        .group(2)!
                        .split(',')
                        .map((t) => t.trim())
                        .where((t) => t.isNotEmpty)
                        .toList();
                    if (key == 'terms' || key == 'claim_terms') {
                      args['terms'] = values;
                    } else if (key == 'scope_ids') {
                      args['scope_ids'] = values;
                    }
                  }
                }
                if (!args.containsKey('terms') &&
                    !args.containsKey('scope_ids')) {
                  args['terms'] = tokens
                      .skip(1)
                      .map((t) => t.replaceAll(',', ''))
                      .toList();
                }
              }
            case 'ANSWER':
            case 'VERDICT':
              // R13: `ANSWER [confidence]` only says "the evidence is enough";
              // the writer decides the answer. `VERDICT …` is the pre-R13
              // spelling: its first number-like token is kept as the
              // confidence, everything else is ignored.
              for (final t in rest.split(RegExp(r'\s+'))) {
                final value = double.tryParse(t);
                if (value != null && value >= 0 && value <= 1) {
                  args['confidence'] = t;
                  break;
                }
              }
              return IntentRecord(action: 'ANSWER', args: args);
            case 'RESELECT':
              final tokens = rest.split(RegExp(r'\s+'));
              if (tokens.isEmpty || tokens.first.isEmpty) return null;
              args['entity_id'] = tokens.first;
            case 'COVER':
              // R12: `COVER <name|entity_id> [scope=<scope_id>]` enumerates
              // story appearances (search_story_coverage).
              final tokens = rest.split(RegExp(r'\s+'));
              if (tokens.isEmpty || tokens.first.isEmpty) return null;
              final target = _unquote(tokens.first);
              if (target.contains(':')) {
                args['entity_id'] = target;
              } else {
                args['query'] = target;
              }
              for (final t in tokens.skip(1)) {
                if (t.startsWith('scope=')) {
                  args['scope_filter'] = t.substring(6).trim();
                }
              }
            case 'FIND':
              // R12: `FIND <phrase> [scope=<scope_id>] [top_k]` searches the
              // raw story lines (search_story_lines).
              final tokens = rest.split(RegExp(r'\s+'));
              if (tokens.isEmpty || tokens.first.isEmpty) return null;
              final queryParts = <String>[];
              for (final t in tokens) {
                if (t.startsWith('scope=')) {
                  args['scope_id'] = t.substring(6).trim();
                } else if (t.startsWith('@') && t.length > 1) {
                  // R14: `@activity:x` (the search-log spelling) is a scope,
                  // not a search term.
                  args['scope_id'] = t.substring(1).trim();
                } else if (t.startsWith('top_k=')) {
                  final k = int.tryParse(t.substring(6).trim());
                  if (k != null) args['top_k'] = k;
                } else if (queryParts.isNotEmpty &&
                    (int.tryParse(t) ?? 0) > 0 &&
                    int.parse(t) <= _maxBareTopK) {
                  // A small bare number is a result count; a larger one
                  // (a year, an id) is part of the query (R13: `FIND 罗德岛
                  // 庆典 2030` used to search with top_k=2030).
                  args['top_k'] = int.parse(t);
                } else {
                  queryParts.add(t);
                }
              }
              // Repeated terms add nothing; drop them so a
              // degenerate "FIND x x x" is the same (deduplicated) command as
              // "FIND x" (R12: seen live with reasoning off).
              final terms = <String>[];
              for (final t in _unquote(queryParts.join(' ')).split(RegExp(r'\s+'))) {
                if (t.isNotEmpty && !terms.contains(t)) terms.add(t);
              }
              if (terms.isEmpty) return null;
              args['query'] = terms.join(' ');
            case 'SEARCH':
              // R11.2: the query may be a multi-word phrase. Collect tokens as
              // the query until an explicit `id=` or a trailing bare number
              // (top_k), so `SEARCH 特蕾西娅 死亡 id=enemy:...` keeps the full
              // phrase instead of dropping everything after the first token.
              // A quoted phrase (`SEARCH "特蕾西娅 死亡"`) is kept verbatim.
              final rawTokens = rest.split(RegExp(r'\s+'));
              if (rawTokens.isEmpty || rawTokens.first.isEmpty) return null;

              // Extract a trailing `id=` argument (anywhere after the query).
              String? explicitId;
              int? topK;
              for (final t in rawTokens.skip(1)) {
                if (t.startsWith('id=')) {
                  final id = t.substring(3).trim();
                  if (id.isNotEmpty) explicitId = id;
                }
              }

              final first = rawTokens.first;
              if (first.startsWith('id=')) {
                final id = first.substring(3).trim();
                if (id.isEmpty) return null;
                args['entity_id'] = id;
                args['query'] = id;
                if (rawTokens.length > 1) {
                  topK = int.tryParse(rawTokens[1]);
                }
              } else if (first.startsWith('"') || first.startsWith("'")) {
                // Quoted phrase: preserve inner spaces verbatim.
                final quote = first[0];
                final parts = <String>[];
                var closed = false;
                if (first.length >= 2 && first.endsWith(quote)) {
                  parts.add(first.substring(1, first.length - 1));
                  closed = true;
                } else {
                  parts.add(first.substring(1));
                }
                for (final t in rawTokens.skip(1)) {
                  if (!closed) {
                    if (t.endsWith(quote)) {
                      parts.add(t.substring(0, t.length - 1));
                      closed = true;
                    } else {
                      parts.add(t);
                    }
                  } else if (t.startsWith('id=')) {
                    final id = t.substring(3).trim();
                    if (id.isNotEmpty) explicitId = id;
                  } else if (t.startsWith('top_k=')) {
                    topK = int.tryParse(t.substring(6).trim());
                  } else if (int.tryParse(t) != null) {
                    topK = int.tryParse(t);
                  }
                }
                args['query'] = parts.join(' ');
              } else {
                // Unquoted multi-word query: join tokens until the first that
                // is an `id=`, a `top_k=` argument, or a standalone number.
                final queryParts = <String>[first];
                for (final t in rawTokens.skip(1)) {
                  if (t.startsWith('id=')) continue;
                  if (t.startsWith('top_k=')) {
                    topK = int.tryParse(t.substring(6).trim());
                    break;
                  }
                  final num = int.tryParse(t);
                  if (num != null) {
                    topK = num;
                    break;
                  }
                  queryParts.add(t);
                }
                args['query'] = queryParts.join(' ');
              }
              if (explicitId != null) args['entity_id'] = explicitId;
              if (topK != null) args['top_k'] = topK;
              // Fall back to no top_k when absent (tool defaults to 5).
          }
          if (args.isEmpty) return null;
        }
        return IntentRecord(action: prefix, args: args);
      } catch (_) {
        return null;
      }
    }
  }
  return null;
}

/// Largest bare trailing number read as FIND's result count.
const int _maxBareTopK = 50;

/// Strips one pair of surrounding ASCII/CJK quotes.
String _unquote(String value) {
  final v = value.trim();
  if (v.length >= 2) {
    const pairs = {'"': '"', "'": "'", '“': '”', '「': '」'};
    final close = pairs[v[0]];
    if (close != null && v.endsWith(close)) {
      return v.substring(1, v.length - 1).trim();
    }
  }
  return v;
}

int _findJsonEnd(String s) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
      continue;
    }
    if (c == '"') {
      inString = true;
    } else if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) return i + 1;
    }
  }
  return -1;
}

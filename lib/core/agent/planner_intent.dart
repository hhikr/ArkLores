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
  final String action; // READ | SEARCH | MAP | COLLECT | SUMMARIZE | VERDICT | DONE
  final Map<String, dynamic> args;
}

/// Parses one intent line (or a JSON-ish object) into an [IntentRecord].
///
/// Returns null when the line is not a valid intent.
IntentRecord? parseIntent(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;
  final upper = trimmed.toUpperCase();

  if (upper == 'DONE') return const IntentRecord(action: 'DONE', args: {});

  for (final prefix in const [
    'READ',
    'SEARCH',
    'MAP',
    'COLLECT',
    'SUMMARIZE',
    'VERDICT',
  ]) {
    if (upper == prefix || upper.startsWith('$prefix ')) {
      final rest = trimmed.substring(prefix.length).trim();
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
              if (tokens.length >= 3) {
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
            case 'COLLECT':
              final tokens = rest.split(RegExp(r'\s+'));
              if (tokens.isEmpty || tokens.first.isEmpty) return null;
              args['entity_id'] = tokens.first;
              if (tokens.length > 1) {
                // claim_terms=[杀,特蕾西娅,血] scope_ids=[a,b]
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
                    if (key == 'claim_terms') {
                      args['claim_terms'] = values;
                    } else if (key == 'scope_ids') {
                      args['scope_ids'] = values;
                    }
                  }
                }
                if (!args.containsKey('claim_terms')) {
                  final claims = tokens
                      .skip(1)
                      .map((t) => t.replaceAll(',', ''));
                  args['claim_terms'] = claims.toList();
                }
              }
            case 'VERDICT':
              final tokens = rest.split(RegExp(r'\s+'));
              if (tokens.isEmpty || tokens.first.isEmpty) return null;
              args['culprit'] = tokens.first;
              if (tokens.length > 1) args['confidence'] = tokens[1];
              if (tokens.length > 2) args['basis'] = tokens[2];
            case 'SEARCH':
              final tokens = rest.split(RegExp(r'\s+'));
              if (tokens.isEmpty || tokens.first.isEmpty) return null;
              // Strip surrounding quotes the model may add around the query.
              var q = tokens.first;
              if (q.length >= 2 &&
                  ((q.startsWith('"') && q.endsWith('"')) ||
                      (q.startsWith("'") && q.endsWith("'")))) {
                q = q.substring(1, q.length - 1);
              }
              args['query'] = q;
              if (tokens.length > 1) args['top_k'] = int.tryParse(tokens[1]);
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
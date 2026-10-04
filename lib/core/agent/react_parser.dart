import 'dart:convert';

import 'tools/agent_tool.dart';

/// Tolerant parser for ReAct step text produced by real providers.
///
/// Providers frequently deviate from the strict format: they place keys right
/// after sentence punctuation, append metadata after the action name, keep
/// prose after the Action Input JSON, or emit loose key-value maps instead of
/// strict JSON. All parsing lives here so the loop stays a state machine and
/// the tolerance stays testable in isolation.

/// Parses a value for a specific key (e.g. "Thought:") from the response.
/// Handles markdown formatting like bolding, bullet points, and inline key
/// placement.
String parseReActKey(String text, String key) {
  // Providers sometimes place a ReAct key directly after sentence punctuation.
  final pattern = RegExp(
    '(?:^|[\\s。！？；.!?;])\\**$key\\**\\s*:\\s*(.*)',
    caseSensitive: false,
  );
  final match = pattern.firstMatch(text);
  if (match != null) {
    var value = match.group(1) ?? '';

    // Handle inline next key on the same line.
    final nextKeyInlinePattern = RegExp(
        r'\b(Thought|Action|Action Input|Observation|Final Answer)\s*:',
        caseSensitive: false,);
    final inlineMatch = nextKeyInlinePattern.firstMatch(value);
    if (inlineMatch != null) {
      value = value.substring(0, inlineMatch.start).trim();
      return cleanReActValue(value);
    }

    // Continue parsing subsequent lines until the next key or end of text
    final startIndex = text.indexOf(match.group(0)!);
    final remainingText =
        text.substring(startIndex + match.group(0)!.length);
    final nextKeyPattern = RegExp(
        r'^[-\\*\\s]*\**(Thought|Action|Action Input|Observation|Final Answer)\**\s*:',
        caseSensitive: false,
        multiLine: true,);
    final nextKeyMatch = nextKeyPattern.firstMatch(remainingText);
    if (nextKeyMatch != null) {
      final contentEnd = remainingText.indexOf(nextKeyMatch.group(0)!);
      return cleanReActValue(
          '${value.trim()}\n${remainingText.substring(0, contentEnd).trim()}',);
    }
    return cleanReActValue('${value.trim()}\n${remainingText.trim()}');
  }
  return '';
}

/// Cleans up trailing formatting symbols like markdown bolding **.
String cleanReActValue(String val) {
  var cleaned = val.trim();
  if (cleaned.endsWith('**')) {
    cleaned = cleaned.substring(0, cleaned.length - 2).trim();
  }
  if (cleaned.startsWith('**')) {
    cleaned = cleaned.substring(2).trim();
  }
  return cleaned;
}

/// Parses Action Input into a parameter map, tolerating strict JSON,
/// leading JSON objects with trailing prose, and loose key-value maps.
Map<String, dynamic> parseActionInput(String raw, AgentTool tool) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return {};
  final actionInput = extractLeadingJsonObject(trimmed) ?? trimmed;

  try {
    final decoded = jsonDecode(actionInput);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
  } catch (_) {
    // Fall through to the tolerant parser below.
  }

  final properties = tool.parameters['properties'];
  final knownKeys = properties is Map
      ? properties.keys.map((key) => '$key').toSet()
      : <String>{};

  final pairs = parseLooseKeyValuePairs(actionInput, knownKeys);
  if (pairs.isNotEmpty) return pairs;

  if (knownKeys.contains('query')) {
    return {'query': stripLooseQuotes(trimmed)};
  }
  if (knownKeys.contains('chunk_id')) {
    return {'chunk_id': stripLooseQuotes(trimmed)};
  }
  return {};
}

/// Extracts the first balanced JSON object from [raw], tolerating prose that
/// follows the object on the same response.
String? extractLeadingJsonObject(String raw) {
  final start = raw.indexOf('{');
  if (start < 0) return null;

  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < raw.length; i++) {
    final char = raw[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }

    if (char == '"') {
      inString = true;
    } else if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
      if (depth == 0) {
        return raw.substring(start, i + 1);
      }
    }
  }
  return null;
}

Map<String, dynamic> parseLooseKeyValuePairs(
  String raw,
  Set<String> knownKeys,
) {
  var text = raw.trim();
  if (text.startsWith('{') && text.endsWith('}')) {
    text = text.substring(1, text.length - 1).trim();
  }
  if (text.isEmpty) return {};

  final result = <String, dynamic>{};
  for (final part in splitLoosePairs(text)) {
    final separator = part.indexOf(':');
    if (separator <= 0) continue;

    final key = stripLooseQuotes(part.substring(0, separator).trim());
    if (!knownKeys.contains(key)) continue;

    final valueText = part.substring(separator + 1).trim();
    result[key] = coerceLooseValue(key, valueText);
  }
  return result;
}

List<String> splitLoosePairs(String text) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var inSingleQuote = false;
  var inDoubleQuote = false;

  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == "'" && !inDoubleQuote) {
      inSingleQuote = !inSingleQuote;
    } else if (char == '"' && !inSingleQuote) {
      inDoubleQuote = !inDoubleQuote;
    }

    if (char == ',' && !inSingleQuote && !inDoubleQuote) {
      parts.add(buffer.toString().trim());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }

  final last = buffer.toString().trim();
  if (last.isNotEmpty) parts.add(last);
  return parts;
}

dynamic coerceLooseValue(String key, String rawValue) {
  final value = stripLooseQuotes(rawValue);
  if (key == 'top_k') {
    return int.tryParse(value) ?? value;
  }
  if (value == 'true') return true;
  if (value == 'false') return false;
  return value;
}

String stripLooseQuotes(String value) {
  var cleaned = value.trim();
  if ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
      (cleaned.startsWith("'") && cleaned.endsWith("'"))) {
    cleaned = cleaned.substring(1, cleaned.length - 1).trim();
  }
  return cleaned;
}

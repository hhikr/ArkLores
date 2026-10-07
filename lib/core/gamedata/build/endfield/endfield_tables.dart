/// 0.12: the Endfield game tables, as decoded JSON (`<TableName>.json`, one
/// object keyed by row id), with their localized text.
///
/// Text fields are `{"id": <int64>, "text": ""}` objects whose string lives
/// in `I18nTextTable_CN.json` under the id; [text] resolves them. A plain
/// string field is already text.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class EndfieldTables {
  EndfieldTables(this.dir);

  /// A directory holding the table files (searched recursively once).
  final Directory dir;

  Map<String, File>? _files;
  Map<String, String>? _i18n;
  final Map<String, Map<String, dynamic>> _cache = {};

  Map<String, File> get _index => _files ??= {
        for (final f in dir.listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.json'))
            p.basenameWithoutExtension(f.path): f,
      };

  /// The path of [name] relative to [dir] (for `source_path`).
  String sourcePath(String name) {
    final file = _index[name];
    return file == null
        ? 'TableCfg/$name.json'
        : p.relative(file.path, from: dir.path).replaceAll(r'\', '/');
  }

  bool has(String name) => _index.containsKey(name);

  /// [name]'s rows (empty when the table is absent).
  Map<String, dynamic> table(String name) {
    final cached = _cache[name];
    if (cached != null) return cached;
    final file = _index[name];
    if (file == null) return _cache[name] = const {};
    final decoded = jsonDecode(file.readAsStringSync());
    return _cache[name] = decoded is Map<String, dynamic> ? decoded : const {};
  }

  Map<String, String> get _strings => _i18n ??= {
        for (final MapEntry(:key, :value) in table('I18nTextTable_CN').entries)
          key: '$value',
      };

  /// The text of a field: a localized `{id, text}` object, or a string.
  String text(Object? field) {
    if (field == null) return '';
    if (field is String) return field;
    if (field is Map) {
      final inline = '${field['text'] ?? ''}';
      if (inline.isNotEmpty) return inline;
      final id = field['id'];
      if (id == null || '$id' == '0') return '';
      return _strings['$id'] ?? '';
    }
    return '';
  }

  /// Drops the cached tables (memory) except the strings.
  void release(String name) => _cache.remove(name);
}

/// Reads [raw] as a list of maps (absent or another shape: empty).
List<Map<String, dynamic>> listOfMaps(Object? raw) => [
      if (raw is List)
        for (final item in raw)
          if (item is Map<String, dynamic>) item,
      if (raw is Map)
        for (final item in raw.values)
          if (item is Map<String, dynamic>) item,
    ];

/// Reads [raw] as a list of strings.
List<String> listOfStrings(Object? raw) => [
      if (raw is List)
        for (final item in raw)
          if (item is String && item.isNotEmpty) item,
    ];

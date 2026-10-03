/// R17: read-only SQL over the knowledge DB for the agent's `sql` tool.
///
/// The general agents that answered story questions well all started from
/// one aggregate query over the whole corpus (lines per story for a name,
/// joined with the catalog). This gives the in-app agent the same reach.
///
/// Safety: the statement is checked to be ONE `SELECT`/`WITH` query without
/// write or attach keywords, the connection is opened read-only, and each
/// query runs in its own isolate (FFI SQLite, separate from the app's sqflite
/// handle) that is killed when it outlives its timeout, so a runaway query
/// never blocks the other tools.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Result of [runReadOnlySql].
class SqlQueryResult {
  const SqlQueryResult({
    this.columns = const [],
    this.rows = const [],
    this.truncated = false,
    this.error,
  });

  final List<String> columns;
  final List<List<Object?>> rows;

  /// More rows matched than were returned.
  final bool truncated;

  /// Rejection, SQL error or timeout, in words the model can act on.
  final String? error;
}

/// Keywords that never belong in a read-only query (matched as whole words
/// outside string literals). `replace` is left out: it is also a function.
const Set<String> _forbiddenKeywords = {
  'insert',
  'update',
  'delete',
  'create',
  'drop',
  'alter',
  'attach',
  'detach',
  'pragma',
  'vacuum',
  'reindex',
  'analyze',
  'savepoint',
  'release',
  'begin',
  'commit',
  'rollback',
  'load_extension',
};

/// Returns [sql] ready to run (comments and a trailing `;` removed), or
/// throws a [FormatException] whose message explains the rejection.
String validateReadOnlySql(String sql) {
  var text = sql
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ' ')
      .replaceAll(RegExp(r'--[^\n]*'), ' ')
      .trim();
  while (text.endsWith(';')) {
    text = text.substring(0, text.length - 1).trimRight();
  }
  if (text.isEmpty) throw const FormatException('SQL 为空');
  // Literals and quoted identifiers are blanked before the keyword checks,
  // so `content LIKE '%delete%'` is fine.
  final bare = text
      .replaceAll(RegExp(r"'(?:[^']|'')*'"), "''")
      .replaceAll(RegExp(r'"(?:[^"]|"")*"'), '""');
  if (bare.contains(';')) {
    throw const FormatException('一次只能执行一条语句');
  }
  final first = RegExp(r'^\s*\(*\s*([A-Za-z]+)').firstMatch(bare)?.group(1);
  if (first == null ||
      !const {'select', 'with'}.contains(first.toLowerCase())) {
    throw const FormatException('只允许 SELECT 或 WITH 查询');
  }
  for (final word in RegExp(r'[A-Za-z_]+').allMatches(bare)) {
    final lower = word.group(0)!.toLowerCase();
    if (_forbiddenKeywords.contains(lower)) {
      throw FormatException('只读查询中不允许 ${word.group(0)}');
    }
  }
  return text;
}

/// Runs one validated read-only query against the DB at [dbPath], returning
/// at most [maxRows] rows. Never throws: problems come back as
/// [SqlQueryResult.error].
Future<SqlQueryResult> runReadOnlySql(
  String dbPath,
  String sql, {
  int maxRows = 200,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final String query;
  try {
    query = validateReadOnlySql(sql);
  } on FormatException catch (e) {
    return SqlQueryResult(error: '查询被拒绝：${e.message}');
  }
  final port = ReceivePort();
  Isolate? isolate;
  try {
    isolate = await Isolate.spawn(
      _sqlIsolateMain,
      [port.sendPort, dbPath, query, maxRows],
      // An uncaught isolate error arrives as `[error, stack]`.
      onError: port.sendPort,
    );
    final reply = await port.first.timeout(timeout);
    if (reply is! Map) {
      return SqlQueryResult(
        error: '查询失败：${reply is List && reply.isNotEmpty ? reply.first : reply}',
      );
    }
    if (reply['error'] != null) {
      return SqlQueryResult(error: 'SQL 错误：${reply['error']}');
    }
    final rows = [
      for (final row in reply['rows'] as List) List<Object?>.from(row as List),
    ];
    return SqlQueryResult(
      columns: List<String>.from(reply['columns'] as List),
      rows: rows,
      truncated: reply['truncated'] == true,
    );
  } on TimeoutException {
    return SqlQueryResult(
      error: '查询超过 ${timeout.inSeconds} 秒被中止：请缩小范围'
          '（加 story_id / collection 条件、先在 story_catalog 里选章节，或用 LIMIT）',
    );
  } catch (e) {
    return SqlQueryResult(error: '查询失败：$e');
  } finally {
    isolate?.kill(priority: Isolate.immediate);
    port.close();
  }
}

Future<void> _sqlIsolateMain(List<Object?> args) async {
  final reply = args[0]! as SendPort;
  final path = args[1]! as String;
  final query = args[2]! as String;
  final maxRows = args[3]! as int;
  sqfliteFfiInit();
  Database? db;
  try {
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    final rows = await db.rawQuery(
      'SELECT * FROM ($query) LIMIT ${maxRows + 1}',
    );
    final columns = rows.isEmpty ? <String>[] : rows.first.keys.toList();
    final kept = rows.length > maxRows ? rows.sublist(0, maxRows) : rows;
    reply.send({
      'columns': columns,
      'rows': [
        for (final row in kept)
          [for (final value in row.values) value is List<int> ? '<blob>' : value],
      ],
      'truncated': rows.length > maxRows,
    });
  } catch (e) {
    reply.send({'error': _sqlErrorText(e)});
  } finally {
    await db?.close();
  }
}

/// The SQLite message without the driver's wrapping.
String _sqlErrorText(Object error) {
  final text = '$error';
  final match = RegExp(r'SqliteException\(\d+\):\s*(.*?)(?:,\s*SQL logic error)?\s*(?:\(code \d+\))?\s*(?:Causing statement.*)?$',
          dotAll: true,)
      .firstMatch(text);
  return (match?.group(1) ?? text).trim();
}

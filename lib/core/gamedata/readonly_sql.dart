/// R17: read-only SQL over the knowledge DB for the agent's `sql` tool.
///
/// The general agents that answered story questions well all started from
/// one aggregate query over the whole corpus (lines per story for a name,
/// joined with the catalog). This gives the in-app agent the same reach.
///
/// Safety: the statement is checked to be ONE `SELECT`/`WITH` query without
/// write or attach keywords, the connection is opened read-only, and each
/// query runs in its own isolate (FFI SQLite, separate from the app's sqflite
/// handle). A query that outlives its timeout is stopped inside SQLite with
/// `sqlite3_interrupt`, so a runaway query never keeps scanning in the
/// background or blocks the other tools.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:sqflite_common_ffi/sqflite_ffi.dart' show sqfliteFfiInit;
import 'package:sqlite3/open.dart' show open;
import 'package:sqlite3/sqlite3.dart' as sqlite;

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
  final replies = StreamIterator<Object?>(port);
  Isolate? isolate;
  SendPort? worker;
  try {
    isolate = await Isolate.spawn(
      _sqlIsolateMain,
      [port.sendPort, dbPath, query, maxRows],
      // An uncaught isolate error arrives as `[error, stack]`.
      onError: port.sendPort,
    );
    // First message: the worker's command port and its connection handle,
    // valid until the worker is told to close (so an interrupt can never
    // hit a freed connection).
    if (!await replies.moveNext().timeout(timeout)) {
      return const SqlQueryResult(error: '查询失败');
    }
    final hello = replies.current;
    if (hello is! Map || hello['commands'] is! SendPort) {
      return SqlQueryResult(error: '查询失败：${_isolateError(hello)}');
    }
    worker = hello['commands'] as SendPort;
    final handle = hello['handle'] as int;
    Object? reply;
    try {
      reply = await replies.moveNext().timeout(timeout).then(
            (more) => more ? replies.current : null,
          );
    } on TimeoutException {
      // Stops the running statement inside SQLite (thread-safe), so the
      // worker returns instead of scanning on in the background.
      _interrupt(handle);
      return SqlQueryResult(
        error: '查询超过 ${timeout.inSeconds} 秒被中止：请缩小范围'
            '（加 story_id / collection 条件、先在 story_catalog 里选章节，或用 LIMIT）',
      );
    }
    if (reply is! Map) {
      return SqlQueryResult(error: '查询失败：${_isolateError(reply)}');
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
    return const SqlQueryResult(error: '查询失败：数据库没有及时打开');
  } catch (e) {
    return SqlQueryResult(error: '查询失败：$e');
  } finally {
    if (worker != null) {
      // The worker closes its connection and exits; the kill below is only
      // a backstop for a worker that never answers.
      worker.send('close');
      final closing = isolate;
      unawaited(
        Future<void>.delayed(const Duration(seconds: 5))
            .then((_) => closing?.kill(priority: Isolate.immediate)),
      );
    } else {
      isolate?.kill(priority: Isolate.immediate);
    }
    unawaited(replies.cancel());
    port.close();
  }
}

String _isolateError(Object? message) =>
    message is List && message.isNotEmpty ? '${message.first}' : '$message';

/// `sqlite3_interrupt` on the connection at [handle] (another isolate's).
void _interrupt(int handle) {
  try {
    sqfliteFfiInit(); // the platform's SQLite library, as the worker uses
    final interrupt = open
        .openSqlite()
        .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
          'sqlite3_interrupt',
        );
    interrupt(Pointer<Void>.fromAddress(handle));
  } catch (_) {
    // Without the symbol the worker finishes on its own; kill still follows.
  }
}

Future<void> _sqlIsolateMain(List<Object?> args) async {
  final reply = args[0]! as SendPort;
  final path = args[1]! as String;
  final query = args[2]! as String;
  final maxRows = args[3]! as int;
  sqfliteFfiInit(); // loads the bundled SQLite on Windows
  final commands = ReceivePort();
  sqlite.Database? db;
  try {
    db = sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readOnly);
    reply.send({'commands': commands.sendPort, 'handle': db.handle.address});
    final result = db.select('SELECT * FROM ($query) LIMIT ${maxRows + 1}');
    final rows = result.rows;
    final kept = rows.length > maxRows ? rows.sublist(0, maxRows) : rows;
    reply.send({
      'columns': result.columnNames,
      'rows': [
        for (final row in kept)
          [for (final value in row) value is List<int> ? '<blob>' : value],
      ],
      'truncated': rows.length > maxRows,
    });
  } catch (e) {
    if (db == null) {
      reply.send('$e');
    } else {
      reply.send({'error': _sqlErrorText(e)});
    }
  }
  if (db != null) await commands.first; // 'close'
  commands.close();
  db?.dispose();
}

/// The SQLite message without the driver's wrapping.
String _sqlErrorText(Object error) {
  if (error is sqlite.SqliteException) {
    return error.extendedResultCode == 9 || error.resultCode == 9
        ? '查询被中止'
        : error.message;
  }
  return '$error';
}

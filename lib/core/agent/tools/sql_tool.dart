part of '../lore_tools.dart';

/// `sql`: one read-only query over the whole knowledge DB.
class SqlTool extends AgentTool {
  SqlTool(this.store, this.seen, {this.manual});

  final GameDataRetrieval store;
  final SeenLines seen;

  /// The manual of the tables (null: none is kept, as in a test of this
  /// tool alone). A question's first query brings it along when it was not
  /// looked at: whoever writes SQL needs it, whether they asked or not.
  final LibraryManual? manual;

  static const int maxRows = 200;

  @override
  String get name => 'sql';

  @override
  String get description => '对一个游戏的知识库执行一条只读 SQL（SQLite 语法，只能是 SELECT/WITH）。'
      '适合做全局统计和定位，例如按 story_id 统计某个名字出现的行数并关联 story_catalog 排序，'
      '或在 entities / entity_aliases / story_lines.speaker 里模糊查名字。'
      '两个游戏的库表结构相同、各是一个文件，一条 SQL 只查其中一个（game 参数）。'
      '最多返回 $maxRows 行；超过时请加条件、聚合或 LIMIT。'
      '表：story_lines、story_catalog、entries、entry_links、collections、normalized_records、entity_documents；'
      '列和用法见 guide（第一次 sql 会附上）。'
      '先看手册再写查询；没看过时，一次问答里第一条查询的结果后面会附上它。';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': '一条 SELECT 或 WITH 语句'},
          'game': _gameParameter('查哪个游戏的库，默认 arknights'),
        },
        'required': ['query'],
      };

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final out = await _query(arguments);
    final manual = this.manual;
    if (manual == null || manual.shown) return out;
    return '$out\n\n（这次问答第一次用 sql：$libraryManualMark，之后的查询照它的表和列写。）\n'
        '${await manual.show()}';
  }

  Future<String> _query(Map<String, dynamic> arguments) async {
    final query = '${arguments['query'] ?? ''}'.trim();
    if (query.isEmpty) return '错误：query 为空';
    // 0.14 live: a query naming an Endfield id (`'ef/…'`) without `game`
    // went to the Arknights database and found nothing; ids name their game.
    final game = Game.parse(arguments['game']) ??
        (RegExp("'(?:record:)?$endfieldIdPrefix").hasMatch(query)
            ? Game.endfield
            : null);
    final result = await store.readOnlySql(query, maxRows: maxRows, game: game);
    if (result.error != null) {
      return '${result.error!}${await _columnsHint(query, result.error!, game)}';
    }
    final overRecords = _recordTables.hasMatch(query);
    if (result.rows.isEmpty) {
      // 0.14 phone: a record's id was looked up in the table that does not
      // hold it (an operator's file is in entity_documents), a dozen times.
      if (overRecords) {
        for (final m in _idEquals.allMatches(query)) {
          final id = m.group(1)!.replaceFirst(_recordPrefix, '');
          if (await store.readRecord(id) != null) {
            return '0 行。这条记录在库里：用 read_record 读它的全文'
                '（id 写 $id，不带 record: 前缀）。';
          }
        }
      }
      final terms = [
        for (final m in _comparedName.allMatches(query)) m.group(1)!,
      ];
      final hint = await _nearNamesHint(narrowTo(store, game), terms);
      final retrieval = store;
      final other = game == null &&
              retrieval is MultiGameRetrieval &&
              (await retrieval.installedGames()).contains(Game.endfield)
          ? '\n（这条 SQL 查的是明日方舟的库；终末地的内容要加 game=endfield。）'
          : '';
      return '0 行。${hint.isEmpty ? '' : '\n$hint'}$other';
    }
    final columns = result.columns;
    final storyCol = columns.indexOf('story_id');
    final lineCol = columns.indexOf('line_index');
    final idCol = columns.indexOf('id');
    // 0.14: a line or a record counts as shown only with its text (a
    // column of, or cut from, `content`), and an id is a record's only in
    // a query over the tables that hold records.
    // 0.14 phone: the text is often selected under another name
    // (`substr(content, 1, 500) c`), and a record read by `WHERE id = '…'`
    // without its id column; neither was counted as shown.
    final list = (_selectList.firstMatch(query)?.group(1) ?? '')
        // Its length or a count shows none of the text.
        .replaceAll(_measured, '');
    final showsContent = _contentOrAll.hasMatch(list);
    final contentCol = showsContent ? 0 : -1;
    final sourceKinds = <(String, int), String?>{};
    if (storyCol >= 0 && lineCol >= 0 && showsContent) {
      final byStory = <String, Set<int>>{};
      for (final row in result.rows) {
        final line = _int(row[lineCol]);
        if (line != null) {
          byStory.putIfAbsent('${row[storyCol]}', () => {}).add(line);
        }
      }
      if (byStory.isNotEmpty) {
        final where = byStory.entries
            .map(
              (e) =>
                  "(story_id = '${e.key.replaceAll("'", "''")}' AND line_index IN (${e.value.join(',')}))",
            )
            .join(' OR ');
        // Validate against source rows even when SQL omits or aliases kind.
        var sources = await store.readOnlySql(
          'SELECT story_id, line_index, kind FROM story_lines WHERE $where',
          maxRows: result.rows.length,
          game: game,
        );
        if (sources.error?.contains('no such column: kind') ?? false) {
          sources = await store.readOnlySql(
            'SELECT story_id, line_index FROM story_lines WHERE $where',
            maxRows: result.rows.length,
            game: game,
          );
        }
        for (final row in sources.rows) {
          sourceKinds[('${row[0]}', _int(row[1])!)] =
              row.length > 2 ? row[2] as String? : null;
        }
      }
    }
    final wholeContent = columns.contains('content');
    final onlyId = idCol < 0 && result.rows.length == 1
        ? _idEquals.firstMatch(query)?.group(1)?.replaceFirst(_recordPrefix, '')
        : null;
    // One row is what was asked for: its cells are not cut short (the
    // result as a whole still is). A cut cell was read 400 characters a
    // call.
    final cell = result.rows.length == 1
        ? (maxToolResultChars - 400) ~/ columns.length
        : 400;
    final buffer = StringBuffer()..writeln(columns.join(' | '));
    var shown = 0;
    for (final row in result.rows) {
      final text = row.map((v) => _clip('${v ?? ''}', cell)).join(' | ');
      if (buffer.length + text.length > maxToolResultChars) break;
      buffer.writeln(text);
      shown++;
      if (storyCol >= 0 && lineCol >= 0 && contentCol >= 0) {
        final line = _int(row[lineCol]);
        final key = ('${row[storyCol]}', line);
        if (line != null &&
            sourceKinds.containsKey(key) &&
            isStoryEvidence(sourceKinds[key])) {
          seen.add('${row[storyCol]}', line);
        }
      }
      // A record shown with its id can be cited as `record:<id>`.
      final id = idCol >= 0 ? row[idCol] : onlyId;
      if (overRecords && contentCol >= 0 && id != null) {
        seen.addRecord(
          '$id',
          partial: !wholeContent ||
              '${row[columns.indexOf('content')] ?? ''}'.length > cell,
        );
      }
    }
    if (shown < result.rows.length || result.truncated) {
      buffer.writeln(
        '（只显示前 $shown 行${result.truncated ? '，结果超过 $maxRows 行' : ''}；'
        '需要更多请加条件、聚合或分页）',
      );
    } else {
      buffer.writeln('（共 $shown 行）');
    }
    return buffer.toString().trimRight();
  }

  /// 0.14: after a wrong column or table, the real columns of the tables
  /// the query names, so the next try does not guess again.
  Future<String> _columnsHint(String query, String error, Game? game) async {
    if (!error.contains('no such column') && !error.contains('no such table')) {
      return '';
    }
    final tables = <String>{
      for (final m in RegExp(
        r'\b(?:FROM|JOIN)\s+([A-Za-z_][A-Za-z0-9_]*)',
        caseSensitive: false,
      ).allMatches(query))
        m.group(1)!,
    };
    final lines = <String>[];
    for (final table in tables.take(4)) {
      final columns = await store.readOnlySql(
        "SELECT name FROM pragma_table_info('$table')",
        maxRows: 60,
        game: game,
      );
      if (columns.error != null) continue;
      lines.add(
        columns.rows.isEmpty
            ? '没有表 $table'
            : '$table 的列：${columns.rows.map((r) => r.first).join(', ')}',
      );
    }
    if (error.contains('no such table') || lines.isEmpty) {
      final all = await store.readOnlySql(
        "SELECT name FROM sqlite_master WHERE type IN ('table', 'view') "
        "AND name NOT LIKE '%fts%' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        maxRows: 80,
        game: game,
      );
      if (all.error == null) {
        lines.add('可用的表：${all.rows.map((r) => r.first).join(', ')}');
      }
    }
    return lines.isEmpty ? '' : '\n${lines.join('\n')}';
  }
}

/// Said when a collection is not found and no name is close (0.14 live: a
/// main-story chapter asked for by a made-up name; an event newer than the
/// library).
const String collectionNotFoundHint =
    '主线的某一章写 main_<章号>；也可能是库里还没有收录的新故事。可以用 sql 查 story_catalog 的 collection_name / collection_id。';

/// 0.14: lookups of one tool that may find nothing in one question before
/// the tool is not run again. A question the library cannot answer (the
/// rows are not there) used to go on for two dozen queries, each a little
/// different, none repeated.
const int maxFailedLookups = 6;

/// How a result that is the limit's refusal starts.
const String lookupLimitPrefix = '没有执行：';

/// What to do at the limit.
const String lookupLimitAdvice =
    '库里很可能没有这样的数据：不要再换条件重试，用已经读到的内容作答，没查到的在答案里说明；确实还要找时换别的工具。';

/// The result of a call to [tool] past the limit.
String lookupLimitNote(String tool) =>
    '$lookupLimitPrefix$tool 在这次问答里已有 $maxFailedLookups 次没有结果。$lookupLimitAdvice';

/// Whether a tool's result says it found nothing or could not run (every
/// tool starts such a result in one of these ways).
bool lookupFoundNothing(String result) {
  final text = result.trimLeft();
  return const ['0 行', 'SQL 错误', '错误', '没有', '缺少参数'].any(text.startsWith);
}

/// In a result that carries the manual ([SqlTool]).
const String libraryManualMark = '下面是知识库手册';

/// 0.14: the knowledge base's manual for one question — the tables, their
/// columns and bindings, the library's shelves ([loreLibraryManual]) — and
/// whether the model has it yet. It used to be over half of the system
/// prompt, sent with every call of every question; only `sql` needs it.
class LibraryManual {
  LibraryManual(this.store);

  final GameDataRetrieval store;

  /// Whether this question's conversation holds the manual already.
  bool shown = false;

  /// The manual for the installed games; marks it shown.
  Future<String> show() async {
    shown = true;
    final store = this.store;
    return loreLibraryManual(
      store is MultiGameRetrieval
          ? await store.installedGames()
          : const [Game.arknights],
    );
  }
}

/// `guide`: the manual, when the model asks for it.
class GuideTool extends AgentTool {
  GuideTool(this.manual);

  final LibraryManual manual;

  @override
  String get name => 'guide';

  @override
  String get description =>
      '查看知识库手册：各表的列和含义、条目之间绑定的种类、资料页的书架和条目种类（装了两个游戏时还有两个库的不同之处）。'
      '写 sql 之前，或遇到不认识的类别、绑定时看；一次问答看一次就够。没有参数。';

  @override
  Map<String, dynamic> get parameters =>
      {'type': 'object', 'properties': <String, dynamic>{}};

  @override
  Future<String> execute(Map<String, dynamic> arguments) async =>
      manual.shown ? '手册在这次问答里已经给过（见前面的结果），照它写查询。' : manual.show();
}

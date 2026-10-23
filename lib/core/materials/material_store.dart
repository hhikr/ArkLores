import 'dart:convert';
import 'dart:typed_data';
import 'package:sqflite_common/sqlite_api.dart';
import '../gamedata/story_vectors.dart';
import '../llm/embedding_client.dart';
import '../userdata/user_data_store.dart';
import 'material_document.dart';

class MaterialVector {
  factory MaterialVector.fromJson(Map<String, dynamic> j) => MaterialVector(
        j['hash'] as String,
        j['model'] as String,
        j['dims'] as int,
        (j['scale'] as num).toDouble(),
        base64Decode(j['vec'] as String),
      );
  const MaterialVector(
    this.hash,
    this.model,
    this.dims,
    this.scale,
    this.bytes,
  );
  final String hash, model;
  final int dims;
  final double scale;
  final Uint8List bytes;
  List<double> get values {
    final signed = bytes.buffer.asInt8List(bytes.offsetInBytes, dims);
    return List.generate(dims, (i) => signed[i] * scale);
  }

  Map<String, Object?> toJson() => {
        'hash': hash,
        'model': model,
        'dims': dims,
        'scale': scale,
        'vec': base64Encode(bytes),
      };
}

/// Immutable versions and reusable content-addressed vectors have separate lifetimes.
class MaterialStore {
  MaterialStore(this.db);
  final Database db;

  Future<void> synchronizePersonal(List<UserMaterial> notes) async {
    final existingSources = {for (final s in await sources()) s.id: s};
    final existingDocuments = {for (final d in await documents()) d.id: d};
    for (final note in notes) {
      final id = 'personal/${note.id}';
      final source = existingSources[id];
      if (source == null) {
        await saveSource(MaterialSource(id: id, title: note.title));
      }
      final document = parseMaterial(
          id: id, sourceId: id, title: note.title, body: note.body,);
      if (existingDocuments[id]?.version != document.version) {
        await saveDocument(document);
      }
    }
    final ids = notes.map((n) => 'personal/${n.id}').toSet();
    for (final source in existingSources.values
        .where((s) => !s.builtin && !ids.contains(s.id))) {
      await deletePersonal(source.id);
    }
  }

  static Future<MaterialStore> open(
    DatabaseFactory factory,
    String path,
  ) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE sources (id TEXT PRIMARY KEY, data TEXT NOT NULL, state TEXT NOT NULL DEFAULT \'pending\', error TEXT)',
          );
          await db.execute(
            'CREATE TABLE documents (id TEXT PRIMARY KEY, source TEXT NOT NULL, version TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE versions (id TEXT NOT NULL, version TEXT NOT NULL, data TEXT NOT NULL, PRIMARY KEY(id,version))',
          );
          await db.execute(
            'CREATE TABLE vectors (hash TEXT NOT NULL, model TEXT NOT NULL, dims INTEGER NOT NULL, scale REAL NOT NULL, vec BLOB NOT NULL, PRIMARY KEY(hash,model,dims))',
          );
          await db.execute(
            'CREATE TABLE policies (source TEXT NOT NULL, version TEXT NOT NULL, data TEXT NOT NULL, PRIMARY KEY(source,version))',
          );
        },
      ),
    );
    return MaterialStore(db);
  }

  Future<void> saveSource(MaterialSource s) async {
    await db.transaction((t) async {
      final old = await t.query('sources', where: 'id=?', whereArgs: [s.id]);
      await t.insert(
        'sources',
        {
          'id': s.id,
          'data': jsonEncode(s.toJson()),
          'state': old.isEmpty ? 'pending' : old.first['state'],
          'error': old.isEmpty ? null : old.first['error'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await t.insert(
        'policies',
        {
          'source': s.id,
          'version': s.policyVersion,
          'data': jsonEncode(s.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    });
  }

  Future<List<MaterialSource>> sources() async => [
        for (final r in await db.query('sources'))
          MaterialSource.fromJson(
            jsonDecode(r['data'] as String) as Map<String, dynamic>,
          ),
      ];
  Future<void> saveDocument(MaterialDocument d) async {
    await db.transaction((t) async {
      await t.insert(
        'versions',
        {'id': d.id, 'version': d.version, 'data': jsonEncode(d.toJson())},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await t.insert(
        'documents',
        {'id': d.id, 'source': d.sourceId, 'version': d.version},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await t.update(
        'sources',
        {'state': 'pending', 'error': null},
        where: 'id=?',
        whereArgs: [d.sourceId],
      );
    });
  }

  Future<List<MaterialDocument>> documents({String? sourceId}) async {
    final rows = await db.rawQuery(
      'SELECT v.data FROM documents d JOIN versions v ON v.id=d.id AND v.version=d.version ${sourceId == null ? '' : 'WHERE d.source=?'}',
      sourceId == null ? null : [sourceId],
    );
    return [
      for (final r in rows)
        MaterialDocument.fromJson(
          jsonDecode(r['data'] as String) as Map<String, dynamic>,
        ),
    ]..sort((a, b) => a.order.compareTo(b.order));
  }

  Future<MaterialDocument?> version(String pageId) async {
    final m = RegExp(r'^material:([\w/-]+)@([a-f0-9]+)$').firstMatch(pageId);
    if (m == null) return null;
    final rows = await db.query(
      'versions',
      where: 'id=? AND version=?',
      whereArgs: [m[1], m[2]],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : MaterialDocument.fromJson(
            jsonDecode(rows.first['data'] as String) as Map<String, dynamic>,
          );
  }

  Future<void> deletePersonal(String id) async {
    await db.transaction((t) async {
      await t.delete('documents', where: 'source=?', whereArgs: [id]);
      await t.delete('sources', where: 'id=?', whereArgs: [id]);
    });
  }

  Future<void> saveVector(MaterialVector v) async {
    if (v.bytes.length != v.dims || !v.scale.isFinite) {
      throw const FormatException('向量维度或编码无效');
    }
    await db.insert(
      'vectors',
      {
        'hash': v.hash,
        'model': v.model,
        'dims': v.dims,
        'scale': v.scale,
        'vec': v.bytes,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<MaterialVector>> vectors() async => [
        for (final r in await db.query('vectors'))
          MaterialVector(
            r['hash'] as String,
            r['model'] as String,
            r['dims'] as int,
            (r['scale'] as num).toDouble(),
            r['vec'] as Uint8List,
          ),
      ];
  Future<({String state, String? error})> status(String source) async {
    final r = await db.query(
      'sources',
      columns: ['state', 'error'],
      where: 'id=?',
      whereArgs: [source],
      limit: 1,
    );
    return (
      state: r.isEmpty ? 'pending' : r.first['state'] as String,
      error: r.isEmpty ? null : r.first['error'] as String?
    );
  }

  Future<void> setState(String id, String state, [String? error]) => db.update(
        'sources',
        {'state': state, 'error': error},
        where: 'id=?',
        whereArgs: [id],
      );
  Future<List<MaterialChunk>> chunks(String source) async {
    final s = (await sources()).where((s) => s.id == source).firstOrNull;
    if (s == null) return [];
    return [
      for (final d in await documents(sourceId: source))
        ...materialChunks(d, s.title),
    ];
  }

  Future<int> pending(String source, EmbeddingClient client) async {
    final have = {
      for (final v in await vectors())
        if (v.model == client.model && v.dims == client.dimensions) v.hash,
    };
    return (await chunks(source))
        .where((c) => !have.contains(c.hash))
        .map((c) => c.hash)
        .toSet()
        .length;
  }

  Future<void> updateVectors(
    String source,
    EmbeddingClient client, {
    bool Function()? cancelled,
    void Function()? onProgress,
  }) async {
    final all = await chunks(source);
    final have = {
      for (final v in await vectors())
        if (v.model == client.model && v.dims == client.dimensions) v.hash,
    };
    final unique = {
      for (final c in all)
        if (!have.contains(c.hash)) c.hash: c,
    };
    final todo = unique.values.toList();
    await setState(source, 'indexing');
    onProgress?.call();
    try {
      for (var i = 0; i < todo.length; i += 20) {
        if (cancelled?.call() == true) {
          await setState(source, 'pending');
          return;
        }
        final batch = todo.sublist(i, (i + 20).clamp(0, todo.length));
        final values = await client.embed(batch.map((c) => c.text).toList());
        if (values.length != batch.length) {
          throw const FormatException('向量服务返回数量不符');
        }
        for (var j = 0; j < batch.length; j++) {
          if (values[j].length != client.dimensions ||
              values[j].any((v) => !v.isFinite)) {
            throw const FormatException('向量服务返回维度不符');
          }
          final q = quantize(values[j]);
          await saveVector(
            MaterialVector(
              batch[j].hash,
              client.model,
              client.dimensions,
              q.scale,
              Uint8List.view(q.values.buffer),
            ),
          );
        }
        onProgress?.call();
      }
      await setState(
        source,
        await pending(source, client) == 0 ? 'ready' : 'pending',
      );
      onProgress?.call();
    } catch (e) {
      await setState(source, 'failed', '向量建立失败，请检查服务配置后重试。');
      onProgress?.call();
      rethrow;
    }
  }

  Future<void> installPackage(Map<String, dynamic> package) async {
    if (package['format'] != 1) throw const FormatException('不支持的资料包版本');
    final s = MaterialSource.fromJson(
      Map<String, dynamic>.from(package['source'] as Map),
    );
    await db.execute(
        'CREATE TABLE IF NOT EXISTS packages (source TEXT PRIMARY KEY, hash TEXT NOT NULL)',);
    final hash = materialHash(jsonEncode(package));
    final installed = await db.query('packages',
        where: 'source=? AND hash=?', whereArgs: [s.id, hash], limit: 1,);
    if (installed.isNotEmpty) return;
    final exists = (await sources()).any((x) => x.id == s.id);
    if (!exists) await saveSource(s);
    final docs = (package['documents'] as List)
        .map(
          (x) => MaterialDocument.fromJson(Map<String, dynamic>.from(x as Map)),
        )
        .toList();
    final existing = {
      for (final d in await documents(sourceId: s.id)) d.id: d.version,
    };
    final ids = docs.map((d) => d.id).toSet();
    final incoming = [
      for (final v in package['vectors'] as List)
        MaterialVector.fromJson(Map<String, dynamic>.from(v as Map)),
    ];
    if (incoming.any((v) => v.bytes.length != v.dims || !v.scale.isFinite)) {
      throw const FormatException('资料包向量损坏');
    }
    await db.transaction((t) async {
      for (final d in docs) {
        await t.insert('versions',
            {'id': d.id, 'version': d.version, 'data': jsonEncode(d.toJson())},
            conflictAlgorithm: ConflictAlgorithm.ignore,);
        await t.insert('documents',
            {'id': d.id, 'source': d.sourceId, 'version': d.version},
            conflictAlgorithm: ConflictAlgorithm.replace,);
      }
      for (final id in existing.keys.where((id) => !ids.contains(id))) {
        await t.delete('documents', where: 'id=?', whereArgs: [id]);
      }
      for (final v in incoming) {
        await t.insert(
            'vectors',
            {
              'hash': v.hash,
              'model': v.model,
              'dims': v.dims,
              'scale': v.scale,
              'vec': v.bytes,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,);
      }
      await t.insert('packages', {'source': s.id, 'hash': hash},
          conflictAlgorithm: ConflictAlgorithm.replace,);
    });
  }
}

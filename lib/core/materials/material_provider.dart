import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import '../background/background_work.dart';
import '../llm/llm_provider.dart';
import '../userdata/user_data_provider.dart';
import '../userdata/user_data_store.dart';
import 'material_document.dart';
import 'material_snapshot.dart';
import 'material_store.dart';

final materialStoreProvider = FutureProvider<MaterialStore>((ref) async {
  final docs = await getApplicationDocumentsDirectory();
  final directory = Directory(p.join(docs.path, 'materials'));
  await directory.create(recursive: true);
  final store = await MaterialStore.open(
    sqflite.databaseFactory,
    p.join(directory.path, 'materials.db'),
  );
  ref.onDispose(() => unawaited(store.db.close()));
  final data = await rootBundle.load('assets/materials/terra.json.gz');
  final package = jsonDecode(
    utf8.decode(
      gzip.decode(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      ),
    ),
  ) as Map<String, dynamic>;
  await store.installPackage(package);
  final user = await ref.watch(userDataStoreProvider.future);
  final notes = await user.materials();
  await store.synchronizePersonal(notes);
  return store;
});

class MaterialLibraryState {
  const MaterialLibraryState({
    this.sources = const [],
    this.documents = const [],
    this.status = const {},
    this.error,
    this.loading = false,
  });
  final bool loading;
  final List<MaterialSource> sources;
  final List<MaterialDocument> documents;
  final Map<String, ({String state, String? error})> status;
  final String? error;
}

final materialLibraryProvider =
    StateNotifierProvider<MaterialLibraryController, MaterialLibraryState>(
  (ref) => MaterialLibraryController(ref),
);

class MaterialLibraryController extends StateNotifier<MaterialLibraryState> {
  MaterialLibraryController(this.ref, {bool load = true})
      : super(const MaterialLibraryState(loading: true)) {
    if (load) unawaited(refresh(resume: true));
    ref.listen(embeddingClientProvider, (previous, next) {
      if (next != null) unawaited(refresh(resume: true));
    });
  }
  final Ref ref;
  final Map<String, int> _generation = {};
  final Set<String> _running = {};
  final Set<String> _paused = {};
  Future<void> refresh({bool resume = false}) async {
    try {
      final store = await ref.read(materialStoreProvider.future);
      final sources = await store.sources();
      final statuses = <String, ({String state, String? error})>{};
      final client = ref.read(embeddingClientProvider);
      for (final s in sources) {
        var status = await store.status(s.id);
        if (!s.enabled) {
          status = (state: 'disabled', error: null);
        } else if (client == null) {
          status = (state: 'pending', error: '未配置向量服务，当前仅可按关键词检索。');
        } else if (!_running.contains(s.id) &&
            await store.pending(s.id, client) == 0) {
          status = (state: 'ready', error: null);
        } else if (status.state == 'ready') {
          status = (state: 'pending', error: '向量待更新或模型不匹配。');
        }
        statuses[s.id] = status;
      }
      if (!mounted) return;
      state = MaterialLibraryState(
        sources: sources,
        documents: await store.documents(),
        status: statuses,
      );
      if (resume) {
        for (final s in sources.where((s) => s.enabled && !s.builtin)) {
          unawaited(index(s.id));
        }
      }
    } catch (e) {
      if (mounted) state = MaterialLibraryState(error: '资料库暂时无法打开，请稍后重试。');
    }
  }

  Future<void> select(MaterialSource source, bool enabled) async {
    _paused.remove(source.id);
    final store = await ref.read(materialStoreProvider.future);
    _generation[source.id] = (_generation[source.id] ?? 0) + 1;
    await store.saveSource(source.copyWith(enabled: enabled));
    await refresh();
    if (enabled) unawaited(index(source.id));
  }

  Future<void> saveNote(UserMaterial note) async {
    final store = await ref.read(materialStoreProvider.future);
    final id = 'personal/${note.id}';
    final source = (await store.sources()).where((s) => s.id == id).firstOrNull;
    await store.saveSource(
      MaterialSource(
        id: id,
        title: note.title,
        enabled: source?.enabled ?? false,
        kind: source?.kind ?? '用户提供资料',
        policy: source?.policy ?? '用户提供资料，用于讨论与查证，不等同于游戏原文。',
      ),
    );
    await store.saveDocument(
      parseMaterial(
        id: id,
        sourceId: id,
        title: note.title,
        body: note.body,
      ),
    );
    _generation[id] = (_generation[id] ?? 0) + 1;
    await refresh();
    if (source?.enabled == true) unawaited(index(id));
  }

  Future<void> remove(String id) async {
    final source = 'personal/$id';
    _generation[source] = (_generation[source] ?? 0) + 1;
    final store = await ref.read(materialStoreProvider.future);
    await store.deletePersonal(source);
    await refresh();
  }

  Future<void> policy(MaterialSource s, String kind, String policy) async {
    final store = await ref.read(materialStoreProvider.future);
    await store
        .saveSource(s.copyWith(kind: kind.trim(), policy: policy.trim()));
    await refresh();
  }

  void cancel(String source) {
    _paused.add(source);
    _generation[source] = (_generation[source] ?? 0) + 1;
  }

  Future<void> index(String source) async {
    if (_running.contains(source)) return;
    _paused.remove(source);
    final client = ref.read(embeddingClientProvider);
    if (client == null) {
      await refresh();
      return;
    }
    _running.add(source);
    final generation = _generation[source] ?? 0;
    final store = await ref.read(materialStoreProvider.future);
    try {
      await BackgroundWork.instance.run(
        BackgroundWork.text('正在建立资料向量', 'Indexing reference materials'),
        () => store.updateVectors(
          source,
          client,
          cancelled: () => !mounted || (_generation[source] ?? 0) != generation,
          onProgress: () => unawaited(refresh()),
        ),
      );
    } catch (_) {/* The store retains the failure state for retry. */} finally {
      _running.remove(source);
      if (mounted) {
        await refresh();
        if ((_generation[source] ?? 0) != generation &&
            !_paused.contains(source)) {
          final s =
              (await store.sources()).where((s) => s.id == source).firstOrNull;
          if (s?.enabled == true) unawaited(index(source));
        }
      }
    }
  }
}

Future<MaterialSnapshot> snapshotMaterials(MaterialStore store) async {
  // A single SQLite transaction prevents selection/version changes between reads.
  return store.db.transaction((t) async {
    final sources = [
      for (final r in await t.query('sources'))
        MaterialSource.fromJson(
          jsonDecode(r['data'] as String) as Map<String, dynamic>,
        ),
    ];
    final docs = [
      for (final r in await t.rawQuery(
        'SELECT v.data FROM documents d JOIN versions v ON d.id=v.id AND d.version=v.version',
      ))
        MaterialDocument.fromJson(
          jsonDecode(r['data'] as String) as Map<String, dynamic>,
        ),
    ];
    final vectors = await t.query('vectors');
    return MaterialSnapshot(sources, docs, [
      for (final r in vectors)
        MaterialVector(
          r['hash'] as String,
          r['model'] as String,
          r['dims'] as int,
          (r['scale'] as num).toDouble(),
          r['vec'] as Uint8List,
        ),
    ]);
  });
}

final citedMaterialProvider = FutureProvider.family<MaterialDocument?, String>(
  (ref, pageId) async =>
      (await ref.watch(materialStoreProvider.future)).version(pageId),
);

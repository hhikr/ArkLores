import 'package:arklores/core/materials/material_document.dart';
import 'package:arklores/core/materials/material_provider.dart';
import 'package:arklores/core/userdata/user_data_store.dart';
import 'memory_user_store.dart';

class MemoryMaterialLibrary extends MaterialLibraryController {
  MemoryMaterialLibrary(super.ref, this.user) : super(load: false) {
    refresh();
  }
  final MemoryUserStore user;
  final Map<String, MaterialSource> _sources = {};
  @override
  Future<void> refresh({bool resume = false}) async {
    state = MaterialLibraryState(sources: [
      for (final n in user.items.values)
        _sources['personal/${n.id}'] ??
            MaterialSource(id: 'personal/${n.id}', title: n.title),
    ], documents: [
      for (final n in user.items.values)
        parseMaterial(
            id: 'personal/${n.id}',
            sourceId: 'personal/${n.id}',
            title: n.title,
            body: n.body,),
    ],);
  }

  @override
  Future<void> saveNote(UserMaterial note) async {
    await refresh();
  }

  @override
  Future<void> remove(String id) async {
    _sources.remove('personal/$id');
    await refresh();
  }

  @override
  Future<void> select(MaterialSource source, bool enabled) async {
    _sources[source.id] = source.copyWith(enabled: enabled);
    await refresh();
  }

  @override
  Future<void> index(String source) async {}
}

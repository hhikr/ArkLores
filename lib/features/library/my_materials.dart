import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library_provider.dart';
import '../../core/materials/material_provider.dart';
import '../../core/userdata/user_data_provider.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/page_frame.dart';
import '../../shared/widgets/smooth_page_route.dart';
import 'library_widgets.dart';
import 'material_pages.dart';
import 'reading_text.dart';

void _open(BuildContext context, WidgetBuilder builder) => Navigator.of(context)
    .push(smoothPageRoute<void>(frosted: true, builder: builder));

/// Opens the editor for a new material, optionally with a starting text.
void newMaterial(BuildContext context, {String? body}) =>
    _open(context, (_) => MaterialEditorPage(initialBody: body));

/// A material's time as the app writes dates (2026.10.22 14:05).
String materialDate(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}.${two(t.month)}.${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// The "My texts" tab: the user's own materials.
class MyMaterialsView extends StatelessWidget {
  const MyMaterialsView({super.key});
  @override
  Widget build(BuildContext context) => const SupplementalMaterialsView();
}

/// One material, read.
class MyMaterialPage extends ConsumerWidget {
  const MyMaterialPage({super.key, required this.id});

  final String id;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirmAction(
      context,
      title: context.t.materialsDeleteConfirm,
      confirm: context.t.materialsDelete,
      danger: true,
      confirmKey: const ValueKey('material-delete-confirm'),
    );
    if (!ok || !context.mounted) return;
    final store = await ref.read(userDataStoreProvider.future);
    await ref.read(materialLibraryProvider.notifier).remove(id);
    await store.deleteMaterial(id);
    ref
      ..invalidate(materialsProvider)
      ..invalidate(materialProvider(id));
    invalidateReading(ref);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final material = ref.watch(materialProvider(id));
    final m = material.valueOrNull;
    return LibraryScaffold(
      title: m?.title ?? '',
      scrollUnder: true,
      actions: [
        if (m != null) ...[
          SquareIconButton(
            key: const ValueKey('material-edit'),
            tooltip: context.t.materialsEdit,
            icon: Icons.edit_sharp,
            onPressed: () =>
                _open(context, (_) => MaterialEditorPage(materialId: id)),
          ),
          SquareIconButton(
            key: const ValueKey('material-delete'),
            tooltip: context.t.materialsDelete,
            icon: Icons.delete_outline_sharp,
            color: theme.danger,
            onPressed: () => _delete(context, ref),
          ),
        ],
      ],
      body: m == null
          ? (material.isLoading
              ? const LoadingView()
              : LibraryMessage(
                  icon: Icons.folder_off_sharp,
                  title: context.t.libraryEmpty,
                ))
          : ListView(
              padding: pagePadding(
                context,
                const EdgeInsets.fromLTRB(16, 16, 16, 40),
              ),
              children: [
                Text(m.title, style: theme.heading(24)),
                const SizedBox(height: 10),
                const TriStrip(),
                const SizedBox(height: 10),
                FactsRow([
                  materialDate(m.updatedAt),
                  context.t.materialsChars(m.body.length),
                ]),
                const SizedBox(height: 18),
                // Read like the other texts: the reading font, no frame.
                ReadingText(m.body),
                const SizedBox(height: 16),
              ],
            ),
    );
  }
}

/// Create or edit a material.
class MaterialEditorPage extends ConsumerStatefulWidget {
  const MaterialEditorPage({
    super.key,
    this.materialId,
    this.initialBody,
    this.initialTitle,
  });

  /// The material to edit; null creates a new one.
  final String? materialId;
  final String? initialBody;
  final String? initialTitle;

  @override
  ConsumerState<MaterialEditorPage> createState() => _MaterialEditorPageState();
}

class _MaterialEditorPageState extends ConsumerState<MaterialEditorPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _savedTitle = '';
  String _savedBody = '';
  bool _loaded = false;
  bool _saving = false;
  String? _savedId;
  String? _error;

  @override
  void initState() {
    super.initState();
    final id = widget.materialId;
    if (id == null) {
      _body.text = widget.initialBody ?? '';
      _title.text = widget.initialTitle ?? '';
      _loaded = true;
    } else {
      _load(id);
    }
  }

  Future<void> _load(String id) async {
    final store = await ref.read(userDataStoreProvider.future);
    final m = await store.material(id);
    if (!mounted) return;
    setState(() {
      _title.text = m?.title ?? '';
      _body.text = m?.body ?? '';
      _savedTitle = _title.text;
      _savedBody = _body.text;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _title.text != _savedTitle ||
      (_body.text != _savedBody && _body.text.trim().isNotEmpty);

  bool get _canSave => _body.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    setState(() => _saving = true);
    try {
      final store = await ref.read(userDataStoreProvider.future);
      final note = await store.saveMaterial(
        id: _savedId ?? widget.materialId,
        title: _title.text,
        body: _body.text,
      );
      _savedId = note.id;
      await ref.read(materialLibraryProvider.notifier).saveNote(note);
      ref.invalidate(materialsProvider);
      ref.invalidate(materialProvider(note.id));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '暂时无法完成保存，请重试。';
        });
      }
    }
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showAppDialog<bool>(
      context,
      (ctx) => AppDialog(
        title: ctx.t.materialsDiscard,
        actions: [
          AppButton(
            ctx.t.materialsCancel,
            small: true,
            kind: ButtonKind.quiet,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          AppButton(
            ctx.t.materialsDiscardAction,
            key: const ValueKey('material-discard-confirm'),
            small: true,
            kind: ButtonKind.danger,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: LibraryScaffold(
        title: widget.materialId == null
            ? context.t.materialsNew
            : context.t.materialsEdit,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: AppButton(
              context.t.materialsSave,
              key: const ValueKey('material-save'),
              small: true,
              kind: ButtonKind.go,
              busy: _saving,
              onPressed: _canSave ? _save : null,
            ),
          ),
        ],
        body: !_loaded
            ? const LoadingView()
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  children: [
                    if (_error != null) ...[
                      NoticeBox(_error!),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      key: const ValueKey('material-title'),
                      controller: _title,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.next,
                      style: theme.heading(18),
                      decoration: InputDecoration(
                        labelText: context.t.materialsTitleHint,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('material-body'),
                        controller: _body,
                        onChanged: (_) => setState(() {}),
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        style: theme.text(16, height: 1.7),
                        decoration: InputDecoration(
                          labelText: context.t.materialsBodyHint,
                          alignLabelWithHint: true,
                          helperText:
                              context.t.materialsChars(_body.text.length),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

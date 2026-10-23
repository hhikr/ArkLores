import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library_provider.dart';
import '../../core/userdata/user_data_provider.dart';
import '../../core/userdata/user_data_store.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/handoff_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/page_frame.dart';
import '../../shared/widgets/smooth_page_route.dart';
import '../../shared/widgets/theme_aware_card.dart';
import 'library_widgets.dart';

/// Longest piece of a material put in the question box by "ask about it".
const int askDraftLimit = 1500;

/// The question-box draft for [material]: the text (cut when long), then an
/// empty line for the question. The text is the user's own, not evidence.
String askDraftFor(UserMaterial material) {
  final body = material.body.trim();
  final text = body.length <= askDraftLimit
      ? body
      : '${body.substring(0, askDraftLimit)}…';
  return '「$text」\n\n';
}

void _open(BuildContext context, WidgetBuilder builder) =>
    Navigator.of(context).push(smoothPageRoute<void>(builder: builder));

/// Opens the editor for a new material, optionally with a starting text.
void newMaterial(BuildContext context, {String? body}) =>
    _open(context, (_) => MaterialEditorPage(initialBody: body));

/// A material's time as the app writes dates (2026.10.22 14:05).
String materialDate(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}.${two(t.month)}.${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// The "My texts" tab: the user's own materials.
class MyMaterialsView extends ConsumerWidget {
  const MyMaterialsView({super.key});

  Future<void> _paste(BuildContext context) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!context.mounted) return;
    if (text.isEmpty) {
      showToast(context, context.t.materialsClipboardEmpty);
      return;
    }
    newMaterial(context, body: text);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final materials = ref.watch(materialsProvider);
    return materials.when(
      loading: () => const LoadingView(),
      error: (_, __) => LibraryMessage(
        icon: Icons.sd_storage_sharp,
        title: context.t.libraryEmpty,
      ),
      data: (list) => ListView(
        // Under the library tab's top bar.
        padding:
            pagePadding(context, const EdgeInsets.fromLTRB(16, 16, 16, 32)),
        children: [
          Row(
            children: [
              Expanded(
                child: AppButton(
                  context.t.materialsNew,
                  key: const ValueKey('materials-new'),
                  kind: ButtonKind.go,
                  icon: Icons.add_sharp,
                  expand: true,
                  onPressed: () => newMaterial(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppButton(
                  context.t.materialsPaste,
                  key: const ValueKey('materials-paste'),
                  icon: Icons.content_paste_sharp,
                  expand: true,
                  onPressed: () => _paste(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: EmptyState(
                title: context.t.materialsEmptyTitle,
                text: context.t.materialsEmptyDesc,
              ),
            )
          else ...[
            SectionTitle(
              title: context.t.libraryTabMine,
              code: 'my texts',
              trailing: Text('${list.length}', style: theme.field()),
            ),
            for (final m in list) ...[
              rowDivider(theme),
              LibraryRow(
                key: ValueKey('material-${m.id}'),
                title: m.title.isEmpty ? '—' : m.title,
                subtitle: m.body.trim().replaceAll(RegExp(r'\s+'), ' '),
                trailing: Text(
                  context.t.materialsChars(m.body.length),
                  style: theme.field(),
                ),
                onTap: () => _open(context, (_) => MyMaterialPage(id: m.id)),
              ),
            ],
            rowDivider(theme),
          ],
        ],
      ),
    );
  }
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
    await store.deleteMaterial(id);
    ref
      ..invalidate(materialsProvider)
      ..invalidate(materialProvider(id));
    invalidateReading(ref);
    if (context.mounted) Navigator.of(context).pop();
  }

  void _ask(BuildContext context, WidgetRef ref, UserMaterial m) {
    ref.read(askDraftProvider.notifier).state = askDraftFor(m);
    ref.read(mainTabRequestProvider.notifier).state = 1;
    Navigator.of(context).popUntil((r) => r.isFirst);
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
                const SizedBox(height: 16),
                ThemeAwareCard(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                  child: SelectableText(
                    m.body,
                    style: theme.text(16, height: 1.8),
                  ),
                ),
                const SizedBox(height: 16),
                // The one main action of the page.
                AppButton(
                  context.t.materialsAskAbout,
                  key: const ValueKey('material-ask'),
                  kind: ButtonKind.go,
                  icon: Icons.psychology_alt_sharp,
                  expand: true,
                  onPressed: () => _ask(context, ref, m),
                ),
              ],
            ),
    );
  }
}

/// Create or edit a material.
class MaterialEditorPage extends ConsumerStatefulWidget {
  const MaterialEditorPage({super.key, this.materialId, this.initialBody});

  /// The material to edit; null creates a new one.
  final String? materialId;
  final String? initialBody;

  @override
  ConsumerState<MaterialEditorPage> createState() =>
      _MaterialEditorPageState();
}

class _MaterialEditorPageState extends ConsumerState<MaterialEditorPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _savedTitle = '';
  String _savedBody = '';
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final id = widget.materialId;
    if (id == null) {
      _body.text = widget.initialBody ?? '';
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
    final store = await ref.read(userDataStoreProvider.future);
    await store.saveMaterial(
      id: widget.materialId,
      title: _title.text,
      body: _body.text,
    );
    ref.invalidate(materialsProvider);
    if (widget.materialId != null) {
      ref.invalidate(materialProvider(widget.materialId!));
    }
    if (mounted) Navigator.of(context).pop();
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
                          helperText: context.t.materialsChars(_body.text.length),
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

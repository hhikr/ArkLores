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

/// The "My texts" tab: the user's own materials.
class MyMaterialsView extends ConsumerWidget {
  const MyMaterialsView({super.key});

  Future<void> _paste(BuildContext context) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!context.mounted) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.materialsClipboardEmpty)),
      );
      return;
    }
    newMaterial(context, body: text);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final materials = ref.watch(materialsProvider);
    return materials.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => LibraryMessage(
        icon: Icons.sd_storage_rounded,
        title: context.t.libraryEmpty,
      ),
      data: (list) => ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('materials-new'),
                    onPressed: () => newMaterial(context),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: Text(
                      context.t.materialsNew,
                      style: theme.titleFont.copyWith(fontSize: 13),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.accentPrimary,
                      foregroundColor: theme.onAccent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('materials-paste'),
                    onPressed: () => _paste(context),
                    icon: const Icon(Icons.content_paste_rounded, size: 18),
                    label: Text(
                      context.t.materialsPaste,
                      style: theme.titleFont.copyWith(fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.accentText,
                      side: BorderSide(color: theme.cardBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (list.isEmpty)
            SizedBox(
              height: 320,
              child: LibraryMessage(
                icon: Icons.edit_note_rounded,
                title: context.t.materialsEmptyTitle,
                description: context.t.materialsEmptyDesc,
              ),
            )
          else
            for (final m in list) ...[
              LibraryRow(
                key: ValueKey('material-${m.id}'),
                leading: Icon(Icons.notes_rounded, color: theme.accentText),
                title: m.title.isEmpty ? '—' : m.title,
                subtitle: m.body.trim().replaceAll(RegExp(r'\s+'), ' '),
                trailing: AccentPill(
                  context.t.materialsChars(m.body.length),
                  muted: true,
                ),
                onTap: () => _open(context, (_) => MyMaterialPage(id: m.id)),
              ),
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(ctx.t.materialsDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.t.materialsCancel),
          ),
          TextButton(
            key: const ValueKey('material-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.t.materialsDelete),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
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
      actions: [
        if (m != null) ...[
          IconButton(
            key: const ValueKey('material-ask'),
            tooltip: context.t.materialsAskAbout,
            icon: Icon(Icons.psychology_alt_rounded, color: theme.accentText),
            onPressed: () => _ask(context, ref, m),
          ),
          IconButton(
            key: const ValueKey('material-edit'),
            tooltip: context.t.materialsEdit,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () =>
                _open(context, (_) => MaterialEditorPage(materialId: id)),
          ),
          IconButton(
            key: const ValueKey('material-delete'),
            tooltip: context.t.materialsDelete,
            icon: Icon(Icons.delete_outline_rounded, color: theme.danger),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ],
      body: m == null
          ? (material.isLoading
              ? const Center(child: CircularProgressIndicator())
              : LibraryMessage(
                  icon: Icons.folder_off_rounded,
                  title: context.t.libraryEmpty,
                ))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                Text(
                  m.title,
                  style: theme.titleFont.copyWith(fontSize: 22, height: 1.25),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    AccentPill(context.t.materialsChars(m.body.length)),
                    AccentPill(_date(m.updatedAt), muted: true),
                  ],
                ),
                const SizedBox(height: 16),
                ThemeAwareCard(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    m.body,
                    style: theme.bodyFont.copyWith(
                      color: theme.textPrimary,
                      fontSize: 15,
                      height: 1.75,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  static String _date(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(ctx.t.materialsDiscard),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.t.materialsCancel),
          ),
          TextButton(
            key: const ValueKey('material-discard-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.t.materialsDiscardAction),
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
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              key: const ValueKey('material-save'),
              onPressed: _canSave && !_saving ? _save : null,
              child: Text(
                context.t.materialsSave,
                style: TextStyle(
                  color: _canSave ? theme.accentText : theme.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  children: [
                    TextField(
                      key: const ValueKey('material-title'),
                      controller: _title,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.next,
                      style: theme.titleFont.copyWith(fontSize: 18),
                      decoration: _decoration(theme, context.t.materialsTitleHint),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('material-body'),
                        controller: _body,
                        onChanged: (_) => setState(() {}),
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        style: theme.bodyFont.copyWith(fontSize: 15, height: 1.6),
                        decoration: _decoration(theme, context.t.materialsBodyHint),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  InputDecoration _decoration(AppThemeTokens theme, String hint) {
    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: theme.bodyFont.copyWith(color: theme.textMuted),
      filled: true,
      fillColor: theme.cardSurface,
      border: border(theme.cardBorder),
      enabledBorder: border(theme.cardBorder),
      focusedBorder: border(theme.accentText),
    );
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/materials/material_document.dart';
import '../../core/materials/material_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/page_frame.dart';
import '../../shared/widgets/smooth_page_route.dart';
import 'library_widgets.dart';
import 'my_materials.dart';
import 'reading_text.dart';

void openMaterialPage(BuildContext context, Widget page) =>
    Navigator.of(context)
        .push(smoothPageRoute<void>(frosted: true, builder: (_) => page));

class SupplementalMaterialsView extends ConsumerStatefulWidget {
  const SupplementalMaterialsView({super.key});
  @override
  ConsumerState<SupplementalMaterialsView> createState() =>
      _SupplementalMaterialsViewState();
}

class _SupplementalMaterialsViewState
    extends ConsumerState<SupplementalMaterialsView> {
  String? _error;
  Future<void> _import() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'txt'],
        withData: true,
      );
      if (result == null) return;
      final file = result.files.single;
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final text = utf8.decode(bytes);
      if (!mounted) return;
      if (text.trim().isEmpty) {
        setState(() => _error = '文件内容为空，请选择包含正文的文件。');
        return;
      }
      openMaterialPage(
        context,
        MaterialEditorPage(
          initialBody: text,
          initialTitle: file.name.replaceFirst(
            RegExp(r'\.(md|txt)$', caseSensitive: false),
            '',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = '无法读取文件，请选择 UTF-8 编码的 Markdown 或文本。');
      }
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      setState(() => _error = '剪贴板没有可导入的文字。');
      return;
    }
    newMaterial(context, body: text);
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(materialLibraryProvider);
    final theme = ref.watch(themeProvider);
    final personal = library.sources.where((s) => !s.builtin).toList();
    // The tab is already named; the page opens on what it is for and the
    // two ways to bring a text in (a new one is the top bar's +).
    return ListView(
      padding: pagePadding(context, const EdgeInsets.fromLTRB(16, 12, 16, 32)),
      children: [
        Text(
          '选择问答可以参考的资料，与游戏原文和 Wiki 一起检索。',
          style: theme.text(14, color: theme.textSecondary, height: 1.6),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            AppButton(
              '导入文件',
              small: true,
              icon: Icons.file_open_sharp,
              onPressed: _import,
            ),
            AppButton(
              '粘贴文字',
              key: const ValueKey('materials-paste'),
              small: true,
              icon: Icons.content_paste_sharp,
              onPressed: _paste,
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: NoticeBox(_error!),
          ),
        if (library.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: NoticeBox(
              library.error!,
              action: AppButton(
                '重试',
                small: true,
                onPressed: () => ref
                    .read(materialLibraryProvider.notifier)
                    .refresh(resume: true),
              ),
            ),
          ),
        const SectionTitle(title: '预置资料', code: 'included'),
        if (library.loading && library.error == null) const LoadingView(),
        for (final s in library.sources.where((s) => s.builtin))
          _row(s, library),
        const SectionTitle(title: '个人资料', code: 'personal'),
        for (final s in personal) _row(s, library),
        if (personal.isEmpty)
          EmptyState(
            text: '保存笔记或导入文本后，可选择参与问答。',
            action: AppButton(
              '新建资料',
              key: const ValueKey('materials-new'),
              small: true,
              kind: ButtonKind.go,
              icon: Icons.add_sharp,
              onPressed: () => newMaterial(context),
            ),
          ),
        const SizedBox(height: 24),
        const NoticeBox(
          '个人资料开启后，正文会发送给已配置的向量服务建立索引。修改已启用资料会自动更新；选择从下一问生效。',
        ),
      ],
    );
  }

  /// One source: its name and facts (what it is, whether Ask reads it, how
  /// its index stands) open it; the switch beside them chooses it for Ask;
  /// the small actions under them are what else can be done with it.
  Widget _row(MaterialSource s, MaterialLibraryState library) {
    final theme = ref.watch(themeProvider),
        controller = ref.read(materialLibraryProvider.notifier);
    final status = library.status[s.id];
    final state = s.enabled
        ? switch (status?.state) {
            'ready' => '已就绪',
            'indexing' => '索引中',
            'failed' => '索引失败',
            _ => '待更新',
          }
        : null;
    void read() => openMaterialPage(
          context,
          s.builtin
              ? MaterialContentsPage(source: s)
              : MyMaterialPage(id: s.id.substring('personal/'.length)),
        );
    final actions = <Widget>[
      AppButton(
        '来源说明',
        small: true,
        kind: ButtonKind.quiet,
        onPressed: () =>
            openMaterialPage(context, MaterialPolicyPage(source: s)),
      ),
      if (!s.builtin)
        AppButton(
          '编辑',
          small: true,
          kind: ButtonKind.quiet,
          onPressed: () => openMaterialPage(
            context,
            MaterialEditorPage(materialId: s.id.substring('personal/'.length)),
          ),
        ),
      if (s.enabled && status?.state != 'ready' && status?.state != 'indexing')
        AppButton(
          '重试索引',
          small: true,
          onPressed: () => controller.index(s.id),
        ),
      if (status?.state == 'indexing')
        AppButton(
          '取消索引',
          small: true,
          onPressed: () => controller.cancel(s.id),
        ),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: PressRow(
                  key: ValueKey(
                    s.builtin
                        ? 'source-${s.id}'
                        : 'material-${s.id.substring('personal/'.length)}',
                  ),
                  onTap: read,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 8, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.title.isEmpty ? '未命名资料' : s.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.heading(16),
                        ),
                        const SizedBox(height: 4),
                        FactsRow([
                          s.kind,
                          s.enabled ? '参与问答' : '不参与问答',
                          if (state != null) state,
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
              SquareSwitch(
                value: s.enabled,
                onChanged: (v) => controller.select(s, v),
                semanticLabel: '${s.title}参与问答',
              ),
            ],
          ),
          if (status?.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 0, 4),
              child: NoticeBox(status!.error!),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: Wrap(spacing: 2, children: actions),
          ),
        ],
      ),
    );
  }
}

class MaterialContentsPage extends ConsumerWidget {
  const MaterialContentsPage({super.key, required this.source});
  final MaterialSource source;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(materialLibraryProvider);
    final theme = ref.watch(themeProvider);
    final docs = library.documents.where((d) => d.sourceId == source.id);
    // What the source is, in plain text (it explains, it is not a warning),
    // then its pages as rows.
    return LibraryScaffold(
      title: source.title,
      scrollUnder: true,
      body: ListView(
        padding:
            pagePadding(context, const EdgeInsets.fromLTRB(16, 16, 16, 32)),
        children: [
          FactsRow([source.kind, '${docs.length} 篇']),
          if (source.policy.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              source.policy,
              style: theme.text(14, color: theme.textSecondary, height: 1.65),
            ),
          ],
          const SizedBox(height: 14),
          Divider(height: 1, color: theme.divider),
          for (final d in docs) ...[
            LibraryRow(
              title: d.title,
              subtitle: '${d.blocks.length} 段',
              subtitleLines: 1,
              trailing: Icon(Icons.chevron_right_sharp, color: theme.textMuted),
              onTap: () => openMaterialPage(
                context,
                MaterialReaderPage(pageId: d.pageId),
              ),
            ),
            rowDivider(theme),
          ],
        ],
      ),
    );
  }
}

class MaterialReaderPage extends ConsumerWidget {
  const MaterialReaderPage({
    super.key,
    required this.pageId,
    this.start = 0,
    this.end,
  });
  final String pageId;
  final int start;
  final int? end;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = ref.watch(citedMaterialProvider(pageId));
    return LibraryScaffold(
      title: doc.valueOrNull?.title ?? '资料原文',
      scrollUnder: true,
      body: doc.when(
        loading: () => const LoadingView(),
        error: (_, __) => const NoticeBox('暂时无法读取资料原文。'),
        data: (d) {
          if (d == null) return const NoticeBox('找不到对应版本的资料原文。');
          final target = start.clamp(0, d.blocks.length);
          final center = ValueKey('$pageId:$target');
          Widget block(int i) {
            final b = d.blocks[i], theme = ref.watch(themeProvider);
            final cited = start > 0 && i >= start && i <= (end ?? start);
            // The gap between paragraphs is inside the marked box, so the
            // rail of a cited run is one unbroken line.
            return Padding(
              key: ValueKey('material-P$i'),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  cited ? 10 - traceRailWidth : 10,
                  20,
                  10,
                  20,
                ),
                decoration: BoxDecoration(
                  border: cited
                      ? Border(
                          left: BorderSide(
                            color: theme.trace,
                            width: traceRailWidth,
                          ),
                        )
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'P${i + 1} / ${b.kind}${b.author.isEmpty ? '' : ' / ${b.author}'}',
                      style: theme.field(),
                    ),
                    const SizedBox(height: 8),
                    MarkdownBody(
                      data: b.text,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: readingStyle(theme),
                        h1: theme.heading(26),
                        h2: theme.heading(22),
                        h3: theme.heading(19),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // The paragraph asked for starts just under the top bar, not
          // behind it.
          return LayoutBuilder(
            builder: (context, box) => CustomScrollView(
              center: center,
              anchor: box.maxHeight <= 0
                  ? 0
                  : (pagePadding(context, EdgeInsets.zero).top / box.maxHeight)
                      .clamp(0.0, 0.5),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.only(
                    top: pagePadding(context, EdgeInsets.zero).top,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => block(target - i - 1),
                      childCount: target,
                    ),
                  ),
                ),
                SliverList(
                  key: center,
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => block(target + i),
                    childCount: d.blocks.length - target,
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: pagePadding(context, EdgeInsets.zero).bottom + 24,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class MaterialPolicyPage extends ConsumerStatefulWidget {
  const MaterialPolicyPage({super.key, required this.source});
  final MaterialSource source;
  @override
  ConsumerState<MaterialPolicyPage> createState() => _MaterialPolicyPageState();
}

class _MaterialPolicyPageState extends ConsumerState<MaterialPolicyPage> {
  late final _kind = TextEditingController(text: widget.source.kind);
  late final _policy = TextEditingController(text: widget.source.policy);
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _kind.dispose();
    _policy.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final data = await rootBundle.load('assets/materials/terra.json.gz');
      final package = jsonDecode(
        utf8.decode(
          gzip.decode(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          ),
        ),
      ) as Map<String, dynamic>;
      final s = MaterialSource.fromJson(
        Map<String, dynamic>.from(package['source'] as Map),
      );
      _kind.text = s.kind;
      _policy.text = s.policy;
    } catch (_) {
      if (mounted) setState(() => _error = '预设说明暂时无法读取。');
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(materialLibraryProvider.notifier)
          .policy(widget.source, _kind.text, _policy.text);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '保存失败，请重试。';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => LibraryScaffold(
        title: '来源说明',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: AppButton(
              '保存',
              small: true,
              kind: ButtonKind.go,
              busy: _saving,
              onPressed: _saving ? null : _save,
            ),
          ),
        ],
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              widget.source.title,
              style: ref.watch(themeProvider).heading(22),
            ),
            const SizedBox(height: 6),
            // What the notes are for: a plain sentence, not a warning.
            Text(
              '这些说明用于解释资料，不会自动证明正文正确，也不会替代相关性检索。',
              style: ref.watch(themeProvider).text(
                    14,
                    color: ref.watch(themeProvider).textSecondary,
                    height: 1.6,
                  ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              NoticeBox(_error!),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _kind,
              decoration: const InputDecoration(labelText: '内容种类'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _policy,
              minLines: 9,
              maxLines: null,
              decoration: const InputDecoration(labelText: '来源、作者认知、适用范围与局限'),
            ),
            if (widget.source.builtin)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    '恢复预设说明',
                    small: true,
                    icon: Icons.restart_alt_sharp,
                    onPressed: _restore,
                  ),
                ),
              ),
          ],
        ),
      );
}

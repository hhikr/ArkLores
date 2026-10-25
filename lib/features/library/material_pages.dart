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
    Navigator.of(context).push(smoothPageRoute<void>(frosted: true, builder: (_) => page));

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
    return ListView(
      padding: pagePadding(context, const EdgeInsets.fromLTRB(16, 16, 16, 32)),
      children: [
        Text('补充资料', style: theme.heading(26)),
        const SizedBox(height: 8),
        Text('选择 Ask 可以参考的资料，与游戏原文和 Wiki 一起检索。', style: theme.text(15)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AppButton(
              '新建资料',
              key: const ValueKey('materials-new'),
              kind: ButtonKind.go,
              icon: Icons.add_sharp,
              onPressed: () => newMaterial(context),
            ),
            AppButton('导入文件', icon: Icons.file_open_sharp, onPressed: _import),
            AppButton(
              '粘贴文字',
              key: const ValueKey('materials-paste'),
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
                onPressed: () => ref
                    .read(materialLibraryProvider.notifier)
                    .refresh(resume: true),
              ),
            ),
          ),
        const SizedBox(height: 20),
        const SectionTitle(title: '预置资料', code: 'included references'),
        if (library.loading && library.error == null) const LoadingView(),
        for (final s in library.sources.where((s) => s.builtin))
          _row(s, library),
        const SizedBox(height: 20),
        const SectionTitle(title: '个人资料', code: 'personal references'),
        for (final s in library.sources.where((s) => !s.builtin))
          _row(s, library),
        if (!library.sources.any((s) => !s.builtin))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('保存笔记或导入文本后，可选择参与问答。', style: theme.text(15)),
          ),
        const SizedBox(height: 20),
        const NoticeBox('个人资料开启后，正文会发送给已配置的向量服务建立索引。修改已启用资料会自动更新；选择从下一问生效。'),
      ],
    );
  }

  Widget _row(MaterialSource s, MaterialLibraryState library) {
    final theme = ref.watch(themeProvider),
        controller = ref.read(materialLibraryProvider.notifier);
    final status = library.status[s.id];
    final state = s.enabled
        ? switch (status?.state) {
            'ready' => '已就绪',
            'indexing' => '索引中',
            'failed' => '失败',
            _ => '待更新'
          }
        : '未启用';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: theme.divider, height: 1),
          const SizedBox(height: 12),
          LibraryRow(
              key: ValueKey(s.builtin
                  ? 'source-${s.id}'
                  : 'material-${s.id.substring('personal/'.length)}',),
              title: s.title.isEmpty ? '未命名资料' : s.title,
              onTap: () => openMaterialPage(
                  context,
                  s.builtin
                      ? MaterialContentsPage(source: s)
                      : MyMaterialPage(
                          id: s.id.substring('personal/'.length),),),),
          Row(
            children: [
              Expanded(child: Text('参与问答', style: theme.text(15))),
              SquareSwitch(
                value: s.enabled,
                onChanged: (v) => controller.select(s, v),
                semanticLabel: '${s.title}参与问答',
              ),
            ],
          ),
          Text('${s.kind} / $state', style: theme.field()),
          if (status?.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: NoticeBox(status!.error!),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppButton(
                s.builtin ? '阅读目录' : '阅读',
                onPressed: () => openMaterialPage(
                  context,
                  s.builtin
                      ? MaterialContentsPage(source: s)
                      : MyMaterialPage(
                          id: s.id.substring('personal/'.length),
                        ),
                ),
              ),
              AppButton(
                '来源说明',
                onPressed: () =>
                    openMaterialPage(context, MaterialPolicyPage(source: s)),
              ),
              if (!s.builtin)
                AppButton(
                  '编辑',
                  onPressed: () => openMaterialPage(
                    context,
                    MaterialEditorPage(
                      materialId: s.id.substring('personal/'.length),
                    ),
                  ),
                ),
              if (s.enabled &&
                  status?.state != 'ready' &&
                  status?.state != 'indexing')
                AppButton('重试索引', onPressed: () => controller.index(s.id)),
              if (status?.state == 'indexing')
                AppButton('取消索引', onPressed: () => controller.cancel(s.id)),
            ],
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
    return LibraryScaffold(
      title: source.title,
      scrollUnder: true,
      body: ListView(
        padding: pagePadding(context, const EdgeInsets.all(16)),
        children: [
          NoticeBox(source.policy),
          const SizedBox(height: 16),
          for (final d
              in library.documents.where((d) => d.sourceId == source.id))
            LibraryRow(
              title: d.title,
              subtitle: '${d.blocks.length} 段',
              onTap: () => openMaterialPage(
                context,
                MaterialReaderPage(pageId: d.pageId),
              ),
            ),
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
            return Padding(
              key: ValueKey('material-P$i'),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: start > 0 && i >= start && i <= (end ?? start)
                      ? Border(
                          left: BorderSide(
                            color: theme.trace,
                            width: 3,
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

          return CustomScrollView(
            center: center,
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
          AppButton('保存',
              kind: ButtonKind.go, onPressed: _saving ? null : _save,),
        ],
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(widget.source.title,
                style: ref.watch(themeProvider).heading(22),),
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
            const SizedBox(height: 16),
            const NoticeBox('这些说明用于解释资料，不会自动证明正文正确，也不会替代相关性检索。'),
            if (_error != null) NoticeBox(_error!),
            if (widget.source.builtin)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: AppButton('恢复预设说明', onPressed: _restore),
              ),
          ],
        ),
      );
}

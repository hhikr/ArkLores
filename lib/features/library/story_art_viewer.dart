import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/story_art_pack.dart' as pack;
import '../../core/gamedata/story_art_pack_provider.dart';
import '../../core/library/story_art.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/motion.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/story_art_image.dart';

Future<void> openStoryArtViewer(BuildContext context,
    {required String storyId,
    required List<StoryArtShot> shots,
    required int initial,
    required void Function(int) onJump,}) {
  if (shots.isEmpty) return Future.value();
  return Navigator.of(context).push(PageRouteBuilder<void>(
    transitionDuration: Motion.of(context, Motion.row),
    reverseTransitionDuration: Motion.of(context, Motion.row),
    pageBuilder: (_, __, ___) => ProviderScope(
        overrides: [
          themeProvider.overrideWith((ref) => ThemeNotifier.of(AppTheme.ark)),
        ],
        child: StoryArtViewer(
            storyId: storyId, shots: shots, initial: initial, onJump: onJump,),),
    transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Motion.snap),
        child: child,),
  ),);
}

final _artMetadata = FutureProvider.autoDispose
    .family<(pack.StoryArtInfo?, pack.StoryArtTitle?), (String, String)>(
        (ref, key) async {
  final p = await ref.watch(storyArtPackProvider.future);
  return (
    (await p.artInfo([key]))[key],
    key.$2 == 'cg' ? await p.artTitle(key.$1) : null
  );
});

class StoryArtViewer extends ConsumerStatefulWidget {
  const StoryArtViewer(
      {super.key,
      required this.storyId,
      required this.shots,
      required this.initial,
      required this.onJump,});
  final String storyId;
  final List<StoryArtShot> shots;
  final int initial;
  final void Function(int) onJump;
  @override
  ConsumerState<StoryArtViewer> createState() => _StoryArtViewerState();
}

class _StoryArtViewerState extends ConsumerState<StoryArtViewer> {
  late final PageController pages;
  late int index;
  bool away = false, zoomed = false;
  @override
  void initState() {
    super.initState();
    index = widget.initial.clamp(0, widget.shots.length - 1);
    pages = PageController(initialPage: index);
  }

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final shot = widget.shots[index];
    final metadata =
        ref.watch(_artMetadata((shot.image, shot.kind))).valueOrNull;
    final title = metadata?.$2;
    final label = switch (shot.kind) {
      'scene' =>
        '${context.t.storyArtScene} ${shot.number.toString().padLeft(2, '0')} / ${shot.total.toString().padLeft(2, '0')}',
      'cg' =>
        'CG ${shot.number.toString().padLeft(2, '0')} / ${shot.total.toString().padLeft(2, '0')}',
      _ => context.t.storyArtItem,
    };
    return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: theme.bgPrimary,
          body: Stack(children: [
            PageView.builder(
                controller: pages,
                physics: zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                itemCount: widget.shots.length,
                onPageChanged: (value) => setState(() {
                      index = value;
                      zoomed = false;
                    }),
                itemBuilder: (context, i) => _ArtPage(
                    shot: widget.shots[i],
                    onTap: () => setState(() => away = !away),
                    onZoom: (value) {
                      if (index == i && zoomed != value) {
                        setState(() => zoomed = value);
                      }
                    },),),
            Align(
                alignment: Alignment.topCenter,
                child: AnimatedSlide(
                    offset: away ? const Offset(0, -1) : Offset.zero,
                    duration: Motion.of(context, Motion.row),
                    curve: Motion.snap,
                    child: ColoredBox(
                        color: theme.bgPrimary.withValues(alpha: .9),
                        child: SafeArea(
                            bottom: false,
                            child: Row(children: [
                              SquareIconButton(
                                  icon: Icons.close_sharp,
                                  tooltip: context.t.storyArtClose,
                                  onPressed: () => Navigator.pop(context),),
                              const SizedBox(width: 12),
                              Text(label,
                                  style:
                                      theme.field(size: 14, color: theme.textPrimary),),
                            ],),),),),),
            Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedSlide(
                    offset: away ? const Offset(0, 1) : Offset.zero,
                    duration: Motion.of(context, Motion.row),
                    curve: Motion.snap,
                    child: Container(
                        width: double.infinity,
                        color: theme.bgPrimary.withValues(alpha: .9),
                        child: SafeArea(
                            top: false,
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (title?.title?.isNotEmpty == true)
                                        Text(title!.title!,
                                            style: theme.heading(17),),
                                      if (title?.description?.isNotEmpty ==
                                          true)
                                        ConstrainedBox(
                                            constraints: const BoxConstraints(
                                                maxHeight: 80,),
                                            child: SingleChildScrollView(
                                                child: Text(title!.description!,
                                                    style: theme.text(13,
                                                        color: theme
                                                            .textSecondary,),),),),
                                      const SizedBox(height: 12),
                                      AppButton(context.t.storyArtJump,
                                          kind: ButtonKind.go, onPressed: () {
                                        Navigator.pop(context);
                                        widget.onJump(shot.at);
                                      },),
                                      const SizedBox(height: 10),
                                      Text(context.t.storyArtCredit,
                                          style: theme.text(12,
                                              color: theme.textMuted,),),
                                    ],),),),),),),
          ],),
        ),);
  }
}

class _ArtPage extends ConsumerStatefulWidget {
  const _ArtPage(
      {required this.shot, required this.onTap, required this.onZoom,});
  final StoryArtShot shot;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoom;
  @override
  ConsumerState<_ArtPage> createState() => _ArtPageState();
}

class _ArtPageState extends ConsumerState<_ArtPage> {
  final transform = TransformationController();
  @override
  void initState() {
    super.initState();
    transform.addListener(_changed);
  }

  void _changed() => widget.onZoom(transform.value.getMaxScaleOnAxis() > 1.001);
  @override
  void dispose() {
    transform.removeListener(_changed);
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shot = widget.shot;
    final metadata =
        ref.watch(_artMetadata((shot.image, shot.kind))).valueOrNull;
    final art = metadata?.$1;
    final tall = art != null && art.height > art.width * 1.3;
    final label = switch (shot.kind) {
      'scene' =>
        context.t.storyArtSceneSemantic(shot.number ?? 0, shot.total ?? 0),
      'cg' => context.t.storyArtCgSemantic(
          shot.number ?? 0, shot.total ?? 0, metadata?.$2?.title ?? '',),
      _ => context.t.storyArtItem,
    };
    final picture = StoryArtImage(
        imageId: shot.image,
        kind: shot.kind,
        placeholder: context.t.storyArtMissing,);
    return Semantics(
        label: label,
        child: GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: InteractiveViewer(
                transformationController: transform,
                minScale: 1,
                maxScale: 4,
                child: tall
                    ? SingleChildScrollView(
                        child: SizedBox(
                            width: MediaQuery.sizeOf(context).width,
                            height: MediaQuery.sizeOf(context).width *
                                art.height /
                                art.width,
                            child: picture,),)
                    : SizedBox.expand(child: picture),),),);
  }
}

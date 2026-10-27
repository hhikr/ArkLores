import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/build/portrait_names.dart';
import '../../core/gamedata/story_art_pack.dart' as pack;
import '../../core/gamedata/story_art_pack_provider.dart';
import '../../core/library/story_art.dart';
import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/motion.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/portrait_image.dart';
import '../../shared/widgets/press_feedback.dart';
import '../../shared/widgets/story_art_composite.dart';
import 'library_widgets.dart';

class ArtViewerPage {
  const ArtViewerPage.story({
    required this.storyId,
    required this.shot,
    this.storyTitle,
    this.onJump,
  })  : sprite = null,
        speaker = null;
  const ArtViewerPage.portrait({required this.sprite, this.speaker})
      : storyId = null,
        shot = null,
        storyTitle = null,
        onJump = null;
  final String? storyId, storyTitle, sprite, speaker;
  final StoryArtShot? shot;
  final ValueChanged<int>? onJump;
}

Future<void> openArtViewer(
  BuildContext context, {
  required List<ArtViewerPage> pages,
  required int initial,
  ValueChanged<int>? onPageChanged,
}) {
  if (pages.isEmpty) return Future.value();
  final origin = context;
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: Motion.of(context, Motion.row),
      reverseTransitionDuration: Motion.of(context, Motion.row),
      pageBuilder: (_, __, ___) => ProviderScope(
        overrides: [
          themeProvider.overrideWith((ref) => ThemeNotifier.of(AppTheme.ark)),
        ],
        child: StoryArtViewer(
          pages: pages,
          initial: initial,
          onPageChanged: onPageChanged,
          onOpenStory: (id, at) => openStoryAt(origin, id, at, at),
        ),
      ),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Motion.snap),
        child: child,
      ),
    ),
  );
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
  const StoryArtViewer({
    super.key,
    required this.pages,
    required this.initial,
    this.onPageChanged,
    required this.onOpenStory,
  });
  final List<ArtViewerPage> pages;
  final int initial;
  final ValueChanged<int>? onPageChanged;
  final void Function(String, int) onOpenStory;
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
    index = widget.initial.clamp(0, widget.pages.length - 1);
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
    final page = widget.pages[index];
    final shot = page.shot;
    final portrait =
        page.sprite == null ? null : SpriteName.parse(page.sprite!);
    final metadata = shot == null
        ? null
        : ref.watch(_artMetadata((shot.image, shot.kind))).valueOrNull;
    final title = metadata?.$2;
    final label = switch (shot?.kind) {
      'scene' =>
        '${context.t.storyArtScene} ${shot?.number.toString().padLeft(2, '0')} / ${shot?.total.toString().padLeft(2, '0')}',
      'cg' =>
        'CG ${shot?.number.toString().padLeft(2, '0')} / ${shot?.total.toString().padLeft(2, '0')}',
      _ =>
        '${context.t.portraitTitle} ${(index + 1).toString().padLeft(2, '0')} / ${widget.pages.length.toString().padLeft(2, '0')}',
    };
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: theme.bgPrimary,
        body: Stack(
          children: [
            PageView.builder(
              controller: pages,
              physics: zoomed
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              itemCount: widget.pages.length,
              onPageChanged: (value) => setState(() {
                index = value;
                widget.onPageChanged?.call(value);
                zoomed = false;
              }),
              itemBuilder: (context, i) => _ArtPage(
                page: widget.pages[i],
                onTap: () => setState(() => away = !away),
                onZoom: (value) {
                  if (index == i && zoomed != value) {
                    setState(() => zoomed = value);
                  }
                },
              ),
            ),
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
                    child: Row(
                      children: [
                        SquareIconButton(
                          icon: Icons.close_sharp,
                          tooltip: context.t.storyArtClose,
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          label,
                          style:
                              theme.field(size: 14, color: theme.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (page.storyTitle != null)
                            Text(page.storyTitle!, style: theme.field()),
                          if (page.speaker != null)
                            Text(page.speaker!, style: theme.heading(17)),
                          if (portrait != null)
                            Text(
                              context.t.portraitFaceBody(
                                portrait.face,
                                portrait.body,
                              ),
                              style: theme.field(),
                            ),
                          if (title?.title?.isNotEmpty == true)
                            Text(
                              title!.title!,
                              style: theme.heading(17),
                            ),
                          if (title?.description?.isNotEmpty == true)
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxHeight: 80,
                              ),
                              child: SingleChildScrollView(
                                child: Text(
                                  title!.description!,
                                  style: theme.text(
                                    13,
                                    color: theme.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          if (shot != null)
                            AppButton(
                              context.t.storyArtJump,
                              kind: ButtonKind.go,
                              onPressed: () {
                                Navigator.pop(context);
                                if (page.onJump != null) {
                                  page.onJump!(shot.at);
                                } else {
                                  widget.onOpenStory(page.storyId!, shot.at);
                                }
                              },
                            ),
                          const SizedBox(height: 10),
                          Text(
                            context.t.storyArtCredit,
                            style: theme.text(
                              12,
                              color: theme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtPage extends ConsumerStatefulWidget {
  const _ArtPage({
    required this.page,
    required this.onTap,
    required this.onZoom,
  });
  final ArtViewerPage page;
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
    final shot = widget.page.shot;
    if (shot == null) {
      return GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: InteractiveViewer(
          transformationController: transform,
          minScale: 1,
          maxScale: 4,
          // The figure as large as it fits between the two bars: drawn to
          // the bottom of the screen, its feet went under the lower bar.
          child: SizedBox.expand(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 72, 16, 112),
                child: PortraitImage(
                  sprite: widget.page.sprite!,
                  transparent: true,
                ),
              ),
            ),
          ),
        ),
      );
    }
    final metadata =
        ref.watch(_artMetadata((shot.image, shot.kind))).valueOrNull;
    final art = metadata?.$1;
    final tall =
        shot.layers.isEmpty && art != null && art.height > art.width * 1.3;
    final label = switch (shot.kind) {
      'scene' =>
        context.t.storyArtSceneSemantic(shot.number ?? 0, shot.total ?? 0),
      'cg' => context.t.storyArtCgSemantic(
          shot.number ?? 0,
          shot.total ?? 0,
          metadata?.$2?.title ?? '',
        ),
      _ => '',
    };
    final picture = StoryArtComposite(
      shot,
      placeholder: context.t.storyArtMissing,
    );
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
                    child: picture,
                  ),
                )
              : Center(
                  child: AspectRatio(
                    aspectRatio: shot.layers.isNotEmpty
                        ? 16 / 9
                        : (art == null ? 16 / 9 : art.width / art.height),
                    child: picture,
                  ),
                ),
        ),
      ),
    );
  }
}

class PortraitFullscreenTap extends ConsumerWidget {
  const PortraitFullscreenTap({
    super.key,
    required this.onTap,
    required this.child,
  });
  final VoidCallback onTap;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Semantics(
      button: true,
      label: context.t.portraitFullscreen,
      child: PressBuilder(
        builder: (context, down) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              if (down)
                ColoredBox(color: theme.textPrimary.withValues(alpha: .1)),
            ],
          ),
        ),
      ),
    );
  }
}

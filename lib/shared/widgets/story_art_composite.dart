import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/story_art_pack.dart' show StoryArtInfo;
import '../../core/gamedata/story_art_pack_provider.dart';
import '../../core/library/story_art.dart';
import 'story_art_image.dart';

// Close-ups are laid out on a 1280×720 stage: their pixels and the script's
// positions both scale by 1.5 onto the 1920×1080 stage drawn here (checked
// against layers whose edges must meet the picture's or the screen's).
const storyArtLayerPixelScale = 1.5;

final _layerInfo = FutureProvider.autoDispose
    .family<StoryArtInfo?, String>((ref, image) async {
  final pack = await ref.watch(storyArtPackProvider.future);
  return (await pack.artInfo([(image, 'item')]))[(image, 'item')];
});

class StoryArtComposite extends ConsumerWidget {
  const StoryArtComposite(
    this.shot, {
    super.key,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.placeholder,
  });
  final StoryArtShot shot;
  final BoxFit fit;
  final Alignment alignment;
  final String? placeholder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget base(BoxFit fit) => StoryArtImage(
          imageId: shot.image,
          kind: shot.kind,
          fit: fit,
          alignment: alignment,
          placeholder: placeholder,
        );
    if (shot.layers.isEmpty) return base(fit);
    final info = {
      for (final layer in shot.layers)
        layer.image: ref.watch(_layerInfo(layer.image)).valueOrNull,
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth / 1920;
        final vertical = constraints.maxHeight / 1080;
        final factor = fit == BoxFit.cover
            ? math.max(horizontal, vertical)
            : math.min(horizontal, vertical);
        final size = Size(1920 * factor, 1080 * factor);
        return ClipRect(
          child: OverflowBox(
            alignment: alignment,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: ClipRect(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // A cleared stage is black in the game.
                    Positioned.fill(
                      child: shot.image.isEmpty
                          ? const ColoredBox(color: Colors.black)
                          : base(BoxFit.cover),
                    ),
                    for (final layer in shot.layers)
                      if (info[layer.image] case final art?)
                        Positioned(
                          left: (960 +
                                  layer.x * storyArtLayerPixelScale -
                                  art.width *
                                      storyArtLayerPixelScale *
                                      layer.scale /
                                      2) *
                              factor,
                          top: (540 -
                                  layer.y * storyArtLayerPixelScale -
                                  art.height *
                                      storyArtLayerPixelScale *
                                      layer.scale /
                                      2) *
                              factor,
                          width: art.width *
                              storyArtLayerPixelScale *
                              layer.scale *
                              factor,
                          height: art.height *
                              storyArtLayerPixelScale *
                              layer.scale *
                              factor,
                          child: Opacity(
                            opacity: layer.alpha.clamp(0, 1),
                            child: StoryArtImage(
                              imageId: layer.image,
                              kind: 'item',
                              transparent: true,
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/story_art_pack_provider.dart';
import '../providers/theme_provider.dart';
import 'ef_widgets.dart';

class _ArtCache {
  final images = <(String, String, int), ui.Image>{};
  Future<void> tail = Future.value();
  bool disposed = false;

  Future<ui.Image> get((String, String, int) key, Uint8List bytes, int width) {
    final result = tail.then((_) async {
      if (disposed) throw StateError('Art cache disposed');
      var image = images.remove(key);
      if (image == null) {
        // Shrink to the layout, never enlarge past the stored picture.
        final codec = await ui.instantiateImageCodec(bytes,
            targetWidth: key.$3 < width ? key.$3 : null,);
        try {
          image = (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      }
      if (disposed) {
        image.dispose();
        throw StateError('Art cache disposed');
      }
      images[key] = image;
      while (images.length > 32) {
        images.remove(images.keys.first)!.dispose();
      }
      return image.clone();
    });
    tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  void dispose() {
    disposed = true;
    for (final image in images.values) {
      image.dispose();
    }
    images.clear();
  }
}

final _cache = Provider<_ArtCache>((ref) {
  ref.watch(storyArtPackProvider.future);
  final cache = _ArtCache();
  ref.onDispose(cache.dispose);
  return cache;
});

final _image = FutureProvider.autoDispose
    .family<ui.Image?, (String, String, int)>((ref, key) async {
  var disposed = false;
  ui.Image? owned;
  ref.onDispose(() {
    disposed = true;
    if (owned != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => owned!.dispose());
    }
  });
  final cache = ref.watch(_cache);
  final pack = await ref.watch(storyArtPackProvider.future);
  final art = await pack.artImage(key.$1, key.$2);
  if (art == null || disposed) return null;
  final image = await cache.get(key, art.webp, art.width);
  if (disposed) {
    image.dispose();
    return null;
  }
  owned = image;
  return image;
});

class StoryArtImage extends ConsumerStatefulWidget {
  const StoryArtImage(
      {super.key,
      required this.imageId,
      required this.kind,
      this.fit = BoxFit.contain,
      this.placeholder,});
  final String imageId, kind;
  final BoxFit fit;
  final String? placeholder;

  @override
  ConsumerState<StoryArtImage> createState() => _StoryArtImageState();
}

class _StoryArtImageState extends ConsumerState<StoryArtImage> {
  (String, String, int)? shown;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final theme = ref.watch(themeProvider);
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final key = (
          widget.imageId,
          widget.kind,
          (width * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(1, 4096)
        );
        var result = ref.watch(_image(key));
        if (result.isLoading && shown != null && shown != key) {
          final previous = ref.watch(_image(shown!));
          if (previous.hasValue) result = previous;
        } else if (!result.isLoading) {
          shown = key;
        }
        return ColoredBox(
            color: theme.cardSurface,
            child: result.when(
              loading: () => const SizedBox.expand(),
              error: (_, __) => _placeholder(),
              data: (image) => image == null
                  ? _placeholder()
                  : RawImage(
                      image: image,
                      fit: widget.fit,
                      filterQuality: FilterQuality.medium,),
            ),);
      },);

  Widget _placeholder() => Hatch(
      child: SizedBox.expand(
          child: widget.placeholder == null
              ? null
              : Center(
                  child:
                      Text(widget.placeholder!, textAlign: TextAlign.center),),),);
}

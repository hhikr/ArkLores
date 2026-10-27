import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gamedata/story_art_pack.dart';
import '../../core/gamedata/story_art_pack_provider.dart';
import '../l10n/l10n.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';
import 'ef_widgets.dart';

Future<ui.Image> _decode(List<int> bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
  );
  final codec = await ui.instantiateImageCodecFromBuffer(buffer);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

/// Replaces patch pixels, including transparent pixels, rather than blending.
Future<ui.Image> composePortrait(PortraitLayers layers) async {
  final base = await _decode(layers.base);
  ui.Image? patch;
  ui.Picture? picture;
  try {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(base, Offset.zero, Paint());
    if (layers.patch != null) {
      patch = await _decode(layers.patch!);
      canvas.drawImage(
        patch,
        Offset(layers.x.toDouble(), layers.y.toDouble()),
        Paint()..blendMode = BlendMode.src,
      );
    }
    picture = recorder.endRecording();
    return await picture.toImage(base.width, base.height);
  } finally {
    picture?.dispose();
    patch?.dispose();
    base.dispose();
  }
}

/// The part of [image] the figure covers. Most sprites are square canvases
/// with the figure standing in the middle third: fitted whole into a tall box
/// they leave a band of nothing over the head.
Future<Rect> figureBounds(ui.Image image) async {
  final full = Offset.zero &
      Size(image.width.toDouble(), image.height.toDouble());
  final bytes = await image.toByteData();
  if (bytes == null) return full;
  final data = bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  final w = image.width, h = image.height;
  var left = w, right = -1, top = h, bottom = -1;
  for (var y = 0; y < h; y++) {
    final row = y * w * 4;
    for (var x = 0; x < w; x++) {
      // Faint edges and encoder noise do not count as the figure.
      if (data[row + x * 4 + 3] > 24) {
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        bottom = y;
      }
    }
  }
  if (right < left) return full;
  return Rect.fromLTRB(left.toDouble(), top.toDouble(), right + 1.0,
      bottom + 1.0,);
}

class PortraitImageCache {
  final _images = <String, ui.Image>{};
  final _bounds = <String, Rect>{};
  Future<void> _tail = Future.value();
  bool _disposed = false;

  /// Where the figure is in [sprite]'s picture, once [image] has made it.
  Rect? boundsOf(String sprite) => _bounds[sprite];

  /// Callers own their clone, so eviction cannot invalidate a visible image.
  Future<ui.Image> image(String sprite, PortraitLayers layers) {
    final result = _tail.then((_) async {
      if (_disposed) throw StateError('Portrait cache disposed');
      final image = _images.remove(sprite) ?? await composePortrait(layers);
      if (!_bounds.containsKey(sprite) && !_disposed) {
        _bounds[sprite] = await figureBounds(image);
      }
      if (_disposed) {
        image.dispose();
        throw StateError('Portrait cache disposed');
      }
      _images[sprite] = image;
      while (_images.length > 24) {
        _images.remove(_images.keys.first)!.dispose();
      }
      return image.clone();
    });
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
  }
}

final _cacheProvider = Provider<PortraitImageCache>((ref) {
  ref.watch(storyArtPackProvider.future);
  final cache = PortraitImageCache();
  ref.onDispose(cache.dispose);
  return cache;
});

enum _State { missingPack, missingSprite, blank, image }

class _Result {
  const _Result(this.state, [this.image, this.bounds]);
  final _State state;
  final ui.Image? image;
  final Rect? bounds;
}

/// The [bounds] part of [image] as large as fits the box, bottom-centred.
class PortraitFigure extends StatelessWidget {
  const PortraitFigure({super.key, required this.image, required this.bounds});
  final ui.Image image;
  final Rect bounds;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
        child: CustomPaint(painter: _FigurePainter(image, bounds)),
      );
}

class _FigurePainter extends CustomPainter {
  const _FigurePainter(this.image, this.bounds);
  final ui.Image image;
  final Rect bounds;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = (size.width / bounds.width) < (size.height / bounds.height)
        ? size.width / bounds.width
        : size.height / bounds.height;
    final w = bounds.width * scale, h = bounds.height * scale;
    canvas.drawImageRect(
      image,
      bounds,
      Rect.fromLTWH((size.width - w) / 2, size.height - h, w, h),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_FigurePainter old) =>
      old.image != image || old.bounds != bounds;
}

final _imageProvider = FutureProvider.autoDispose
    .family<_Result, ({String sprite, String? fallback})>((ref, key) async {
  var disposed = false;
  ui.Image? owned;
  ref.onDispose(() {
    disposed = true;
    final image = owned;
    if (image != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
    }
  });
  final cache = ref.watch(_cacheProvider);
  final pack = await ref.watch(storyArtPackProvider.future);
  if (!await pack.installed) return const _Result(_State.missingPack);
  var sprite = key.sprite;
  var layers = await pack.layers(sprite);
  if (layers == null && key.fallback != null) {
    sprite = key.fallback!;
    layers = await pack.layers(sprite);
  }
  if (layers == null) return const _Result(_State.missingSprite);
  if (layers.blank) return const _Result(_State.blank);
  if (disposed) return const _Result(_State.missingSprite);
  final image = await cache.image(sprite, layers);
  if (disposed) {
    image.dispose();
    return const _Result(_State.missingSprite);
  }
  owned = image;
  return _Result(_State.image, image, cache.boundsOf(sprite));
});

/// Draws one sprite's figure fitted inside the box, bottom-centred. Given another
/// sprite, it keeps showing the last one until the new one is ready, so a
/// change of picture (another variant) does not blink through the empty
/// box.
class PortraitImage extends ConsumerStatefulWidget {
  const PortraitImage({
    super.key,
    required this.sprite,
    this.fallbackSprite,
    this.semanticLabel,
  });
  final String sprite;
  final String? fallbackSprite, semanticLabel;

  @override
  ConsumerState<PortraitImage> createState() => _PortraitImageState();
}

class _PortraitImageState extends ConsumerState<PortraitImage> {
  /// The picture on screen, while another is being made: still watched, so
  /// its image is not let go before the new one replaces it.
  ({String sprite, String? fallback})? _shown;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final key = (sprite: widget.sprite, fallback: widget.fallbackSprite);
    var result = ref.watch(_imageProvider(key));
    final last = _shown;
    if (result.isLoading && last != null && last != key) {
      final before = ref.watch(_imageProvider(last));
      if (before.hasValue) result = before;
    } else if (!result.isLoading) {
      _shown = key;
    }
    Widget placeholder(String text, {bool hatch = true}) {
      // A thumbnail is too small for the sentence: the hatching alone says
      // there is no picture (the sentence is still read out).
      final child = LayoutBuilder(
        builder: (context, box) => SizedBox.expand(
          child: box.maxWidth < 120
              ? Semantics(label: text)
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      text,
                      style: theme.text(14, color: theme.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
        ),
      );
      return hatch ? Hatch(child: child) : child;
    }

    return Semantics(
      label: widget.semanticLabel,
      child: ColoredBox(
        color: theme.cardSurface,
        child: result.when(
          loading: () => const SizedBox.expand(),
          error: (_, __) => placeholder(context.t.portraitNotInPack),
          data: (r) => switch (r.state) {
            _State.missingPack => placeholder(context.t.storyArtPackMissing),
            _State.missingSprite => placeholder(context.t.portraitNotInPack),
            _State.blank => placeholder(context.t.portraitBlank, hatch: false),
            _State.image => PortraitFigure(
                image: r.image!,
                bounds: r.bounds ??
                    Offset.zero &
                        Size(
                          r.image!.width.toDouble(),
                          r.image!.height.toDouble(),
                        ),
              ),
          },
        ),
      ),
    );
  }
}

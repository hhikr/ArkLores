import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/l10n.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/press_feedback.dart';

/// The hit region extends into the dialogue row without moving its text.
class PortraitSpeakerName extends ConsumerWidget {
  const PortraitSpeakerName({
    super.key,
    required this.name,
    required this.style,
    required this.onTap,
  });
  final String name;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return _SpeakerHitRegion(
      child: Semantics(
        button: true,
        label: context.t.portraitTapSpeaker(name),
        excludeSemantics: true,
        child: PressBuilder(
          builder: (context, down) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48),
              child: ColoredBox(
                color: down
                    ? pressTint(Colors.transparent, theme.textPrimary)
                    : Colors.transparent,
                child: Stack(
                  children: [
                    if (!theme.isDark)
                      Positioned.fill(
                        top: 12,
                        child: ColoredBox(color: theme.accentPrimary),
                      ),
                    Text(
                      name,
                      style: theme
                          .heading(
                            14,
                            color: theme.isDark
                                ? theme.accentText
                                : theme.textPrimary,
                          )
                          .copyWith(height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpeakerHitRegion extends SingleChildRenderObjectWidget {
  const _SpeakerHitRegion({required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) => _SpeakerHitBox();
}

class _SpeakerHitBox extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final height = size.height < 48 ? 48.0 : size.height;
    if (!(Offset.zero & Size(size.width, height)).contains(position)) {
      return false;
    }
    // Map the extra transparent area onto the same gesture target.
    return super.hitTest(
      result,
      position: Offset(position.dx, position.dy.clamp(0, size.height - 0.001)),
    );
  }
}

/// Test the expanded name target before the paragraph occupying its lower part.
class PortraitSpeakerTarget extends SingleChildRenderObjectWidget {
  const PortraitSpeakerTarget({
    super.key,
    required this.target,
    required super.child,
  });
  final GlobalKey target;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _SpeakerTargetBox(target);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _SpeakerTargetBox).target = target;
  }
}

class _SpeakerTargetBox extends RenderProxyBox {
  _SpeakerTargetBox(this.target);
  GlobalKey target;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final box = target.currentContext?.findRenderObject();
    if (box is RenderBox && box.attached) {
      final hit = result.addWithPaintOffset(
        offset: box.localToGlobal(Offset.zero, ancestor: this),
        position: position,
        hitTest: (result, local) => box.hitTest(result, position: local),
      );
      if (hit) return true;
    }
    return super.hitTestChildren(result, position: position);
  }
}

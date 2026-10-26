import 'package:arklores/features/wiki/wiki_browser_page.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/bars_provider.dart';
import 'package:arklores/shared/theme/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_webview.dart';
import '../../support/plain_theme.dart';

void main() {
  testWidgets('page sends dock updates once per state change', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    InAppWebViewPlatform.instance = FakeWebViewPlatform();
    final container = ProviderContainer(overrides: [plainThemeOverride()]);
    addTearDown(container.dispose);
    var reduced = false;
    Future<void> mount() async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: MediaQueryData(
                padding: const EdgeInsets.only(top: 32, bottom: 85),
                viewPadding: const EdgeInsets.only(top: 32, bottom: 24),
                disableAnimations: reduced,
              ),
              child: const WikiBrowserPage(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
    }

    await mount();
    final controllers = <_RecordingController>[];
    for (final widget
        in tester.widgetList<InAppWebView>(find.byType(InAppWebView))) {
      final controller = _RecordingController();
      controllers.add(controller);
      widget.platform.params.onWebViewCreated!(
        InAppWebViewController.fromPlatform(platform: controller),
      );
    }
    expect(controllers, isNotEmpty);
    container.read(barsHiddenProvider.notifier).state = true;
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    for (final controller in controllers) {
      expect(controller.scripts, hasLength(1));
      expect(
        controller.scripts.last,
        contains("'--arklores-dock-top', '32.0px'"),
      );
      expect(
        controller.scripts.last,
        contains("'--arklores-dock-bottom', '24.0px'"),
      );
    }
    container.read(barsHiddenProvider.notifier).state = false;
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    for (final controller in controllers) {
      expect(controller.scripts, hasLength(2));
      expect(
        controller.scripts.last,
        contains("'--arklores-dock-top', '88.0px'"),
      );
      expect(
        controller.scripts.last,
        contains("'--arklores-dock-bottom', '85.0px'"),
      );
    }
    // A tap on nothing on the page (the page script reports it): with the
    // bars away they come back; at the page's top they stay; scrolled on,
    // a second tap sends them away again.
    final tap = controllers.first.handlers[wikiBlankTapHandler]!;
    container.read(barsHiddenProvider.notifier).state = true;
    tap(const <dynamic>[]);
    expect(container.read(barsHiddenProvider), isFalse);
    tap(const <dynamic>[]);
    expect(container.read(barsHiddenProvider), isFalse);
    final web = tester.widgetList<InAppWebView>(find.byType(InAppWebView)).first;
    web.platform.params.onScrollChanged!(
      InAppWebViewController.fromPlatform(platform: controllers.first),
      0,
      400,
    );
    tap(const <dynamic>[]);
    expect(container.read(barsHiddenProvider), isTrue);
    tap(const <dynamic>[]);
    expect(container.read(barsHiddenProvider), isFalse);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    for (final controller in controllers) {
      controller.scripts.clear();
      controller.scripts.addAll(['', '']);
    }
    reduced = true;
    await mount();
    for (final controller in controllers) {
      expect(controller.scripts, hasLength(3));
      expect(controller.scripts.last, isNot(contains('transition')));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  });
  test('dock variables follow bars without changing page padding', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    String script() {
      final hidden = container.read(barsHiddenProvider);
      return wikiDockInsetsScript(
        top: 88,
        bottom: 85,
        visibleTop: hidden ? 32 : 88,
        visibleBottom: hidden ? 24 : 85,
        duration: hidden ? Motion.row : Motion.press * 2,
      );
    }

    expect(
      script(),
      contains("'--arklores-dock-top', '88.0px'"),
    );
    expect(
      script(),
      contains("'--arklores-dock-bottom', '85.0px'"),
    );
    container.read(barsHiddenProvider.notifier).state = true;
    final hidden = script();
    expect(
      hidden,
      contains("'--arklores-dock-top', '32.0px'"),
    );
    expect(
      hidden,
      contains("'--arklores-dock-bottom', '24.0px'"),
    );
    expect(hidden, contains('})(88.0, 85.0)'));
    expect(hidden, contains('transition:top 200ms cubic-bezier(0.7,0,0.2,1)'));
    expect(hidden, contains('transition:bottom 200ms'));
    expect(hidden, contains("'var(--arklores-dock-top)', 'important'"));
    expect(hidden, contains("'var(--arklores-dock-bottom)', 'important'"));
    expect(hidden, contains('window.setTimeout(shift, 600)'));
    expect(hidden, contains('window.setTimeout(shift, 1600)'));
    container.read(barsHiddenProvider.notifier).state = false;
    expect(
      script(),
      contains("'--arklores-dock-top', '88.0px'"),
    );
  });

  test('reduced motion generates no transition', () {
    final script = wikiDockInsetsScript(
      top: 88,
      bottom: 85,
      visibleTop: 32,
      visibleBottom: 24,
      duration: Duration.zero,
    );
    expect(script, isNot(contains('transition')));
  });
}

class _RecordingController extends PlatformInAppWebViewController {
  _RecordingController()
      : super.implementation(
          const PlatformInAppWebViewControllerCreationParams(id: 'test'),
        );
  final scripts = <String>[];
  final handlers = <String, JavaScriptHandlerCallback>{};
  @override
  void addJavaScriptHandler({
    required String handlerName,
    required JavaScriptHandlerCallback callback,
  }) =>
      handlers[handlerName] = callback;
  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    scripts.add(source);
    return null;
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
}

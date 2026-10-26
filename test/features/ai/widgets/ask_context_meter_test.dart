import 'dart:async';
import 'dart:io';

import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/agent/answer_options.dart';
import 'package:arklores/core/agent/react_event.dart';
import 'package:arklores/core/agent/story_qa_agent.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/features/ai/ai_chat_page.dart';
import 'package:arklores/features/ai/widgets/ask_context_meter.dart';
import 'package:arklores/main.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/settings_provider.dart';
import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:arklores/shared/widgets/ef_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_llm.dart';
import '../../../support/screenshot.dart';

class _Agent extends StoryQaAgent {
  _Agent() : super(llmClient: ScriptedLLM(['unused']));
  final events = StreamController<ReActEvent>();

  @override
  Stream<ReActEvent> run({
    required String query,
    List<Message> history = const [],
    LLMClient? client,
    AnswerOptions options = const AnswerOptions(),
    int? contextWarnTokens,
    LoreConversation? prior,
    void Function(LoreConversation)? onConversation,
    void Function(int, String)? onRawLlmResponse,
  }) =>
      events.stream;

  void size(int tokens, {bool estimated = false}) => events.add(
        ReActEvent(
          type: ReActEventType.contextSize,
          contextTokens: tokens,
          contextEstimated: estimated,
        ),
      );
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<ProviderContainer> mount(
    WidgetTester tester,
    _Agent agent, {
    AppTheme theme = AppTheme.endfield,
    bool composer = false,
  }) async {
    final container = ProviderContainer(
      overrides: [
        storyQaAgentProvider.overrideWithValue(agent),
        initialApiConfigProvider.overrideWithValue(const LLMConfig(chatApiKey: 'test-key')),
        initialThemeProvider.overrideWithValue(theme),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(container.read(themeProvider)).copyWith(
            textTheme: buildAppTheme(container.read(themeProvider)).textTheme.apply(fontFamily: 'Saira'),
          ),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Shot(
            child: Scaffold(
              backgroundColor: container.read(themeProvider).bgPrimary,
              body: composer ? const AiChatPage() : const Column(
                children: [Expanded(child: SizedBox()), AskContextMeter()],
              ),
            ),
          ),
        ),
      ),
    );
    return container;
  }

  Future<void> start(WidgetTester tester, ProviderContainer container) async {
    unawaited(
      container
          .read(askChatProvider(container.read(shownAskProvider)).notifier)
          .sendMessage('问题'),
    );
    await tester.pump();
  }

  testWidgets(
      'empty, normal, estimated, threshold display and one dialog per crossing',
      (tester) async {
    final agent = _Agent();
    final container = await mount(tester, agent);
    expect(find.byKey(const ValueKey('ask-context-meter')), findsNothing);
    await start(tester, container);
    agent.size(84000, estimated: true);
    await tester.pumpAndSettle();
    expect(find.text('上下文 ≈84.0k / 100k'), findsOneWidget);
    expect(find.byType(NoticeBox), findsNothing);
    final notifier = container
        .read(askChatProvider(container.read(shownAskProvider)).notifier);
    expect(notifier.latestContext?.contextTokens, 84000);
    agent.size(100000);
    await tester.pumpAndSettle();
    expect(find.byType(NoticeBox), findsOneWidget);
    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text('停止作答'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    agent.size(120000);
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsNothing);
    agent.size(90000);
    await tester.pumpAndSettle();
    agent.size(110000);
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsOneWidget);
    await tester.tap(find.text('停止作答'));
    await tester.pumpAndSettle();
    expect(notifier.isStreaming, false);
    unawaited(agent.events.close());
  });

  testWidgets(
      'background crossing stays pending until shown; changing threshold does not open a dialog',
      (tester) async {
    final agent = _Agent();
    final container = await mount(tester, agent);
    final key = container.read(shownAskProvider);
    await start(tester, container);
    agent.size(84000);
    await tester.pumpAndSettle();
    container.read(askSessionsProvider.notifier).startNew();
    await tester.pumpAndSettle();
    agent.size(100000);
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsNothing);
    expect(container.read(askChatProvider(key).notifier).contextWarningPending,
        true,);
    container.read(askSessionsProvider.notifier).show(key);
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await container.read(contextWarnTokensProvider.notifier).set(200000);
    await tester.pumpAndSettle();
    expect(find.byType(NoticeBox), findsNothing);
    await container.read(contextWarnTokensProvider.notifier).set(64000);
    await tester.pumpAndSettle();
    expect(find.byType(NoticeBox), findsOneWidget);
    expect(find.byType(AppDialog), findsNothing);
    container.read(askChatProvider(key).notifier).cancel();
    await tester.pumpAndSettle();
    unawaited(agent.events.close());
  });

  for (final theme in [AppTheme.endfield, AppTheme.ark]) {
    testWidgets('390px ${theme.name} context screenshots', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final family in ['Saira', 'NotoSansSC']) {
        final loader = FontLoader(family)
          ..addFont(rootBundle.load('assets/fonts/$family.ttf'));
        await loader.load();
      }
      final cipher = FontLoader('EndfieldCipher')..addFont(rootBundle.load('assets/fonts/EndfieldByButan.ttf'));
      await cipher.load();
      await tester.runAsync(() async {
        final bytes = await File('C:/src/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes();
        final icons = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(bytes)));
        await icons.load();
      });
      final agent = _Agent();
      final container =
          await mount(tester, agent, theme: theme, composer: true);
      await start(tester, container);
      agent.size(84000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await shoot(tester, '${theme.name}_normal');
      agent.size(120000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('知道了'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final meter = tester
          .widget<Container>(find.byKey(const ValueKey('ask-context-meter')));
      expect(meter.color, container.read(themeProvider).accentPrimary);
      expect(tester.takeException(), isNull);
      await shoot(tester, '${theme.name}_over');
      container
          .read(askChatProvider(container.read(shownAskProvider)).notifier)
          .cancel();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      unawaited(agent.events.close());
    });
  }
}

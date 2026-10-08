// R16: every role runs without thinking; only the "深度思考" switch gives the
// answer writer a low effort, for the next question only.
import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/core/llm/llm_provider.dart';
import 'package:arklores/core/llm/openai_client.dart';
import 'package:arklores/shared/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        initialApiConfigProvider.overrideWithValue(
          const LLMConfig(chatApiKey: 'test-key'),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('every role defaults to no thinking', () {
    final c = container();
    final off = c.read(llmClientProvider(ReasoningLevel.off));
    expect((off as OpenAICompatibleClient).reasoning, ReasoningLevel.off);
    expect(c.read(deepThinkingProvider), isFalse);
  });

  test('"深度思考" gives a low-effort client without rebuilding the chat',
      () {
    final c = container();
    final low = c.read(llmClientProvider(ReasoningLevel.low));
    expect((low as OpenAICompatibleClient).reasoning, ReasoningLevel.low);
    // A rebuild would drop the conversation.
    final notifier = c.read(askChatProvider.notifier);
    c.read(deepThinkingProvider.notifier).state = true;
    expect(identical(c.read(askChatProvider.notifier), notifier), isTrue);
  });
}

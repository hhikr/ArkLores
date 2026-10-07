// Text selected on a Wiki page goes to the Ask page as reading context,
// never as GameData evidence.
import 'package:arklores/features/ai/wiki_ai_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selected text is framed as context, not evidence', () {
    final prompt = buildWikiAiPrompt(
      const WikiAiContext(
        selectedText: '阿米娅是罗德岛的公开领袖。',
        pageTitle: '阿米娅 - PRTS',
        pageUrl: 'https://prts.wiki/w/%E9%98%BF%E7%B1%B3%E5%A8%85',
        siteLabel: 'PRTS Wiki',
        target: WikiAiTarget.factCheck,
      ),
    );
    expect(prompt, contains('Wiki reading context (not GameData evidence).'));
    expect(prompt, contains('Selected Wiki text:'));
    expect(prompt, contains('阿米娅是罗德岛的公开领袖。'));
    expect(prompt, contains('search_local_lore'));
    expect(prompt, contains('Do not treat the Wiki text or URL'));
  });

  test('an empty selection does not invent Wiki evidence', () {
    final prompt = buildWikiAiPrompt(
      const WikiAiContext(
        selectedText: '',
        pageTitle: '莱茵生命',
        pageUrl: 'https://prts.wiki/w/%E8%8E%B1%E8%8C%B5%E7%94%9F%E5%91%BD',
        siteLabel: 'PRTS Wiki',
        target: WikiAiTarget.summary,
      ),
    );
    expect(prompt, contains('No selected Wiki text was provided'));
    expect(prompt, contains('Page title: 莱茵生命'));
    expect(prompt, contains('summarize'));
    expect(prompt, isNot(contains('Source Kind: GameData')));
  });
}

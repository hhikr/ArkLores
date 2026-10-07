// Every setting the app persists: its default, a round trip, and what is
// refused or migrated.
import 'dart:convert';

import 'package:arklores/core/llm/embedding_client.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/features/settings/settings_service.dart';
import 'package:arklores/shared/l10n/locale_provider.dart';
import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SettingsService service;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    service = SettingsService();
  });

  /// A service over storage that already holds [values].
  SettingsService withStored(Map<String, String> values) {
    FlutterSecureStorage.setMockInitialValues(values);
    return SettingsService();
  }

  group('API', () {
    test('defaults to Zhipu GLM without a key', () async {
      final config = await service.loadApiConfig();
      expect(config.chatBaseUrl, 'https://api.z.ai/api/paas/v4');
      expect(config.chatModel, 'glm-5.3-flash');
      expect(config.chatApiKey, isEmpty);
    });

    test('URL, key and model are saved together', () async {
      await service.saveApiConfig(const LLMConfig(
        chatBaseUrl: 'https://api.example.com/v1',
        chatApiKey: 'k',
        chatModel: 'm',
      ),);
      final config = await SettingsService().loadApiConfig();
      expect(
        [config.chatBaseUrl, config.chatApiKey, config.chatModel],
        ['https://api.example.com/v1', 'k', 'm'],
      );
    });

    test('embedding: defaults, then a trimmed round trip', () async {
      final defaults = await service.loadEmbeddingConfig();
      expect(defaults.apiKey, isEmpty);
      expect(defaults.model, defaultEmbeddingConfig.model);
      expect(defaults.dimensions, defaultEmbeddingConfig.dimensions);

      await service.saveEmbeddingConfig(const EmbeddingConfig(
        baseUrl: ' https://e.example.com/v1 ',
        apiKey: ' key ',
        model: ' emb ',
        dimensions: 512,
      ),);
      final saved = await service.loadEmbeddingConfig();
      expect(saved.baseUrl, 'https://e.example.com/v1');
      expect(saved.apiKey, 'key');
      expect(saved.model, 'emb');
      expect(saved.dimensions, 512);
    });

    test('GitHub token: blank by default, a blank save clears it', () async {
      expect(await service.loadGithubToken(), '');
      await service.saveGithubToken(' ghp_abc123 ');
      expect(await service.loadGithubToken(), 'ghp_abc123');
      await service.saveGithubToken('   ');
      expect(await service.loadGithubToken(), '');
    });
  });

  group('app state', () {
    test('session logs default off and persist', () async {
      expect(await service.loadSessionLogsEnabled(), isFalse);
      await service.saveSessionLogsEnabled(true);
      expect(await service.loadSessionLogsEnabled(), isTrue);
      await service.saveSessionLogsEnabled(false);
      expect(await service.loadSessionLogsEnabled(), isFalse);
    });

    test('nickname is trimmed; onboarding is remembered', () async {
      expect(await service.loadNickname(), '');
      await service.saveNickname(' 刀客塔 ');
      expect(await service.loadNickname(), '刀客塔');
      expect(await service.isOnboardingDone(), isFalse);
      await service.markOnboardingDone();
      expect(await service.isOnboardingDone(), isTrue);
    });

    test('a tab index out of range falls back to the first tab', () async {
      await service.saveMainTabIndex(2);
      expect(await service.loadMainTabIndex(), 2);
      await service.saveMainTabIndex(9);
      expect(await service.loadMainTabIndex(), 0);
      expect(await withStored({'main_tab_index': 'x'}).loadMainTabIndex(), 0);
      await service.saveWikiTabIndex(5);
      expect(await service.loadWikiTabIndex(), 5);
    });

    test('theme, locale and launcher icon fall back on unknown values',
        () async {
      expect(await service.loadTheme(), AppTheme.ark);
      await service.saveTheme(AppTheme.endfield);
      expect(await service.loadTheme(), AppTheme.endfield);
      expect(await withStored({'theme': 'neon'}).loadTheme(), AppTheme.ark);

      expect(await service.loadLocale(), SupportedLocale.zh);
      await service.saveLocale(SupportedLocale.en);
      expect(await service.loadLocale(), SupportedLocale.en);

      expect(await service.loadAppLauncherIcon(), AppLauncherIcon.light);
      await service.saveAppLauncherIcon(AppLauncherIcon.dark);
      expect(await service.loadAppLauncherIcon(), AppLauncherIcon.dark);
    });
  });

  group('Wiki reader', () {
    test('reader mode, font scale (clamped) and dark mode (unset = follow)',
        () async {
      expect(await service.loadWikiReaderMode(), isFalse);
      await service.saveWikiReaderMode(true);
      expect(await service.loadWikiReaderMode(), isTrue);

      expect(await service.loadWikiReaderFontScale(), 1.0);
      await service.saveWikiReaderFontScale(1.2);
      expect(await service.loadWikiReaderFontScale(), 1.2);
      await service.saveWikiReaderFontScale(5);
      expect(await service.loadWikiReaderFontScale(), 1.38);
      expect(
        await withStored({'wiki_reader_font_scale': '9'}).loadWikiReaderFontScale(),
        1.0,
      );

      expect(await service.loadWikiDarkMode(), isNull);
      await service.saveWikiDarkMode(false);
      expect(await service.loadWikiDarkMode(), isFalse);
      expect(await withStored({'wiki_dark_mode': '?'}).loadWikiDarkMode(), isNull);
    });

    test('only absolute URLs are kept as a tab URL', () async {
      await service.saveWikiUrl(0, 'not a url');
      expect(await service.loadWikiUrl(0), isNull);
      await service.saveWikiUrl(0, 'https://prts.wiki/w/x');
      expect(await service.loadWikiUrl(0), 'https://prts.wiki/w/x');
      await service.saveWikiAppliedUrl(1, '/relative');
      expect(await service.loadWikiAppliedUrl(1), isNull);
      await service.saveWikiAppliedUrl(1, 'https://warfarin.wiki/cn/x');
      expect(await service.loadWikiAppliedUrl(1), 'https://warfarin.wiki/cn/x');
    });
  });

  group('Wiki sites', () {
    test('the two built-in sites by default, with a saved tab URL', () async {
      final sites = await withStored({'wiki_url_0': 'https://prts.wiki/w/y'})
          .loadWikiSites();
      expect(sites.map((s) => s.id), ['prts', 'endfield']);
      expect(sites.first.url, 'https://prts.wiki/w/y');
      expect(sites.every((s) => s.builtIn), isTrue);
    });

    test('old Endfield ids become one "endfield" site', () async {
      final stored = jsonEncode([
        {'id': 'prts', 'label': 'PRTS Wiki', 'url': 'https://prts.wiki', 'builtIn': true},
        {'id': 'endfield-fz', 'label': 'x', 'url': 'https://fz.wiki', 'builtIn': true},
        {'id': 'endfield-warfarin', 'label': 'y', 'url': 'https://warfarin.wiki/cn', 'builtIn': true},
      ]);
      final sites = await withStored({'wiki_sources': stored}).loadWikiSites();
      expect(sites.map((s) => s.id), ['prts', 'endfield']);
      expect(sites.last.label, 'Endfield Wiki');
      expect(sites.last.iconUrl, 'https://fz.wiki/icon.svg');
    });

    test('a list without Endfield gets it back; broken JSON gives defaults',
        () async {
      final custom = jsonEncode([
        {'id': 'mine', 'label': '我的', 'url': 'https://example.org'},
      ]);
      final sites = await withStored({'wiki_sources': custom}).loadWikiSites();
      expect(sites.map((s) => s.id), ['mine', 'endfield']);
      expect(
        (await withStored({'wiki_sources': '{oops'}).loadWikiSites()).map((s) => s.id),
        ['prts', 'endfield'],
      );
    });

    test('saving drops invalid sites and the tab URL of a changed site',
        () async {
      // Without a saved list a tab URL is taken as the site's URL (the
      // pre-list layout), so start from a saved list.
      await service.saveWikiSites(SettingsService.defaultWikiSites);
      await service.saveWikiUrl(0, 'https://prts.wiki/w/old');
      await service.saveWikiUrl(1, 'https://warfarin.wiki/cn/kept');
      await service.saveWikiSites(const [
        WikiSiteConfig(id: 'a', label: 'A', url: 'https://a.example.org'),
        WikiSiteConfig(id: 'endfield', label: 'Endfield Wiki',
            url: 'https://warfarin.wiki/cn', builtIn: true,),
        WikiSiteConfig(id: '', label: 'no id', url: 'https://b.example.org'),
      ]);
      final sites = await service.loadWikiSites();
      expect(sites.map((s) => s.id), ['a', 'endfield']);
      expect(await service.loadWikiUrl(0), isNull); // site 0 changed
      expect(await service.loadWikiUrl(1), 'https://warfarin.wiki/cn/kept');

      // An empty list is not saved.
      await service.saveWikiSites(const []);
      expect((await service.loadWikiSites()).map((s) => s.id), ['a', 'endfield']);

      await service.resetWikiSites();
      expect((await service.loadWikiSites()).map((s) => s.id), ['prts', 'endfield']);
      expect(await service.loadWikiUrl(1), isNull);
    });

    test('a site needs an id, a label and an absolute URL', () {
      expect(WikiSiteConfig.fromJson({'id': 'x', 'label': 'X', 'url': 'x.org'}),
          isNull,);
      expect(WikiSiteConfig.fromJson('not a map'), isNull);
      final site = WikiSiteConfig.fromJson(
          {'id': ' x ', 'label': 'X', 'url': 'https://x.org', 'iconUrl': ''},)!;
      expect(site.id, 'x');
      expect(site.iconUrl, isNull);
      expect(site.builtIn, isFalse);
    });
  });
}

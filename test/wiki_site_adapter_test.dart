import 'package:arklores/features/settings/settings_service.dart';
import 'package:arklores/features/wiki/wiki_site_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WikiSiteAdapter', () {
    test('keeps Endfield as one selectable built-in source', () {
      expect(SettingsService.defaultWikiSites, hasLength(2));
      expect(
        SettingsService.defaultWikiSites.map((site) => site.id),
        containsAll(<String>['prts', 'endfield']),
      );
    });

    test('recognizes built-in Wiki hosts', () {
      expect(
        WikiSiteAdapter.kindForUrl('https://prts.wiki/w/Test'),
        WikiSiteKind.prts,
      );
      expect(
        WikiSiteAdapter.kindForUrl('https://fz.wiki/wiki/干员'),
        WikiSiteKind.fz,
      );
      expect(
        WikiSiteAdapter.kindForUrl('https://warfarin.wiki/cn/operators'),
        WikiSiteKind.warfarin,
      );
      expect(
        WikiSiteAdapter.kindForUrl('https://example.com/wiki'),
        WikiSiteKind.generic,
      );
    });

    test("theme bootstrap uses each site's native contract", () {
      final script = WikiSiteAdapter.documentStartThemeScript(dark: true);
      expect(script, contains('data-theme'));
      expect(script, contains("root.classList.toggle('dark'"));
      expect(script, contains('data-arklores-fz-theme'));
      expect(script, contains('data-arklores-warfarin-theme'));
    });

    test('reader roots do not use MediaWiki selectors for Endfield sites', () {
      expect(
        WikiSiteAdapter.readerRootSelector(WikiSiteKind.fz),
        contains('main > div.grid > div:first-child'),
      );
      expect(
        WikiSiteAdapter.readerRootSelector(WikiSiteKind.warfarin),
        contains('main > div > div.flex-1'),
      );
      expect(
        WikiSiteAdapter.readerRootSelector(WikiSiteKind.prts),
        contains('#mw-content-text'),
      );
    });
  });
}

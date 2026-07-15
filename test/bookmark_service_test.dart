import 'package:flutter_test/flutter_test.dart';

import 'package:arklores/features/wiki/bookmark_service.dart';

void main() {
  group('Bookmark model', () {
    test('create generates unique id and timestamp', () {
      final b1 = Bookmark.create(
        title: 'Test Page',
        url: 'https://prts.wiki/test',
        site: 'prts',
      );
      final b2 = Bookmark.create(
        title: 'Another Page',
        url: 'https://warfarin.wiki/cn/another',
        site: 'endfield',
      );

      expect(b1.id, isNot(equals(b2.id)));
      expect(b1.createdAt, greaterThan(0));
      expect(b2.createdAt, greaterThan(0));
      expect(b1.title, equals('Test Page'));
      expect(b2.site, equals('endfield'));
    });

    test('toMap and fromMap round-trip', () {
      final original = Bookmark.create(
        title: 'Round Trip',
        url: 'https://prts.wiki/roundtrip',
        site: 'prts',
      );
      final map = original.toMap();
      final restored = Bookmark.fromMap(map);

      expect(restored.id, equals(original.id));
      expect(restored.title, equals(original.title));
      expect(restored.url, equals(original.url));
      expect(restored.site, equals(original.site));
      expect(restored.createdAt, equals(original.createdAt));
    });

    test('equality is based on id', () {
      final a = Bookmark(
        id: 'same-id',
        title: 'Alpha',
        url: 'https://prts.wiki/a',
        site: 'prts',
        createdAt: 1000,
      );
      final b = Bookmark(
        id: 'same-id',
        title: 'Beta', // different title
        url: 'https://prts.wiki/b', // different url
        site: 'prts',
        createdAt: 2000, // different time
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('siteLabel returns correct human-readable name', () {
      final prts = Bookmark.create(
        title: 'PRTS',
        url: 'https://prts.wiki/page',
        site: 'prts',
      );
      final endfield = Bookmark.create(
        title: 'Endfield',
        url: 'https://warfarin.wiki/cn/page',
        site: 'endfield',
      );

      expect(prts.siteLabel, equals('PRTS Wiki'));
      expect(endfield.siteLabel, equals('Endfield Wiki'));
    });
  });
}

import 'dart:convert';

import 'package:arklores/core/gamedata/gamedata_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy channel and incomplete portrait assets remain readable', () {
    expect(GameDataChannel.parse('{}')!.portraits, isNull);
    for (final fields in [
      {'url': 'https://example.test/pack'},
      {'sha256': 'hash'},
      {'url': ' ', 'sha256': 'hash'},
    ]) {
      expect(
          GameDataChannel.parse(jsonEncode({'arknights_portraits': fields}))!
              .portraits,
          isNull,);
    }
  });
  test('portrait fields parse; build compatibility ignores pack version', () {
    final asset = GameDataChannel.parse(jsonEncode({
      'arknights_portraits': {
        'url': 'https://example.test/pack',
        'sha256': 'hash',
        'size': 280000000,
        'kb_commit': 'commit',
        'pack_version': 9,
        'min_app_build': 43,
      },
    }),)!
        .portraits!;
    expect(asset.url, 'https://example.test/pack');
    expect(asset.sha256, 'hash');
    expect(asset.size, 280000000);
    expect(asset.kbCommit, 'commit');
    expect(asset.packVersion, 9);
    expect(asset.usableBy(42), isFalse);
    expect(asset.usableBy(43), isTrue);
    expect(asset.usableBy(null), isTrue);
  });
}

import 'dart:convert';

import 'package:arklores/core/gamedata/gamedata_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy channel and incomplete portrait assets remain readable', () {
    expect(GameDataChannel.parse('{}')!.storyArt, isNull);
    for (final fields in [
      {'url': 'https://example.test/pack'},
      {'sha256': 'hash'},
      {'url': ' ', 'sha256': 'hash'},
    ]) {
      expect(
          GameDataChannel.parse(jsonEncode({'arknights_story_art': fields}))!
              .storyArt,
          isNull,);
    }
  });
  StoryArtPackAsset parse(int version) => GameDataChannel.parse(jsonEncode({
        'arknights_story_art': {
          'url': 'https://example.test/pack',
          'sha256': 'hash',
          'size': 280000000,
          'kb_commit': 'commit',
          'pack_version': version,
          'min_app_build': 43,
        },
      }),)!
          .storyArt!;

  test('portrait fields parse; the build must reach min_app_build', () {
    final asset = parse(2);
    expect(asset.url, 'https://example.test/pack');
    expect(asset.sha256, 'hash');
    expect(asset.size, 280000000);
    expect(asset.kbCommit, 'commit');
    expect(asset.packVersion, 2);
    expect(asset.usableBy(42), isFalse);
    expect(asset.usableBy(43), isTrue);
    expect(asset.usableBy(null), isTrue);
  });

  test('a pack format this app does not read is never offered', () {
    final asset = parse(1);
    expect(asset.packVersion, 1);
    expect(asset.usableBy(99), isFalse);
    expect(asset.usableBy(null), isFalse);
  });
}

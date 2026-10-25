import 'dart:io';

import 'package:arklores/core/gamedata/build/story_script.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/story_script_before_portraits.dart' as before;

void main() {
  const a = r'char_002_amiya_1#5$1';
  const b = r'char_010_chen_1#2$1';
  const cases = <String, String?>{
    '[Character(name="char_002_amiya_1#5")]': a,
    '[Character(name="char_001_x_1",name2="char_010_chen_1#2",focus=2)]': b,
    '[Character(name="char_001_x_1",name2="char_010_chen_1#2")]': null,
    '[Character(name="char_002_amiya_1#5",focus=-1)]': null,
    '[Character(name="char_002_amiya_1#5")]\n[Character]': null,
    '[charslot(slot="l",name="char_002_amiya_1#5",focus="l")]': a,
    '[charslot(slot="l",name="char_002_amiya_1#5",focus="none")]': null,
    '[charslot(name="char_002_amiya_1#5")]\n[charslot]': null,
    '[charslot(slot="m",name="avg_npc_1_1#2\$1")]': r'avg_npc_1_1#2$1',
    '[charslot(slot="l",name="char_002_amiya_1#5")]\n[charslot(slot="l",focus="l")]':
        a,
    '[charslot(slot="l",name="char_002_amiya_1#5")]\n[charslot(slot="l",duration=0.3)]':
        null,
    '[CharSlot(SLOT="left",NAME=" Char_002_amiya_1 #5 ",FOCUS="left")]': a,
    '[Character(name="bg_bad")]': null,
    '[Character(name="char_002_amiya_1#5")] [charslot(slot="r",name="char_010_chen_1#2",focus="r")]':
        b,
    '[charslot(name="char_002_amiya_1#5",focus="all")]': null,
    '[charslot(name="char_002_amiya_1#5")]\n[charslot(name="")]': null,
  };
  for (final entry in cases.entries) {
    test(entry.key, () {
      final lines = parseStoryScript('${entry.key}\n[name="阿米娅"]台词');
      expect(lines.single.portrait, entry.value);
    });
  }
  test('focus persists between lines, resets between scripts', () {
    final lines = parseStoryScript('''
[charslot(slot="l",name="$a",focus="l")]
[name="甲"]一
[charslot(slot="r",name="$b",focus="r")]
[name="乙"]二
[name="乙"]三
旁白
[Subtitle(text="字幕")]
''');
    expect(lines.map((l) => l.portrait), [a, b, b, null, null]);
    expect(parseStoryScript('[name="乙"]四').single.portrait, isNull);
  });
  final root = Directory('notes/upstream/story');
  test(
    '30 upstream scripts preserve every kind, speaker and content',
    () {
      final files = root
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.txt'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      expect(files.length, greaterThanOrEqualTo(30));
      for (final file in files.take(30)) {
        final raw = file.readAsStringSync();
        expect(
          parseStoryScript(raw)
              .map((l) => (l.kind.value, l.speaker, l.content))
              .toList(),
          before
              .parseStoryScript(raw)
              .map((l) => (l.kind.value, l.speaker, l.content))
              .toList(),
          reason: file.path,
        );
      }
    },
    skip: !root.existsSync(),
  );
}

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
  test('a picture covers the stage until an Image without one', () {
    final lines = parseStoryScript('''
[Character(name="char_002_amiya_1#5")]
[name="甲"]一
[Image(image="avg_1_1", x=50, fadetime=0)]
[ImageTween(xTo=-50, duration=20, block=false)]
[name="乙"]二
[Character(name="char_010_chen_1#2")]
[name="乙"]三
[image]
[name="乙"]四
[Character(name="char_002_amiya_1#5")] [IMAGE(Image="avg_1_2")]
[name="甲"]五
[Image(fadetime=1)]
[name="甲"]六
[Image(image="")]
[name="甲"]七
[cgitem(image="cgitem_1", style="cg", layer=1)]
[Background(image="bg_1")]
[Blocker(a=1, fadetime=1)]
[name="甲"]八
[charslot(slot="l",name="char_010_chen_1#2",focus="l")]
[Image(image="avg_1_3")]
[charslot(slot="l",name="char_002_amiya_1#5",focus="l")]
[name="甲"]九
[Image(fadetime=1)]
[name="甲"]十
[Image(image="avg_1_4")]
''');
    expect(
      lines.map((l) => l.portrait),
      [a, null, null, b, null, a, a, a, null, a],
    );
    expect(
      parseStoryScript(
        '[Character(name="char_002_amiya_1#5")]\n[name="甲"]一',
      ).single.portrait,
      a,
      reason: 'a picture left at the end of a script does not carry over',
    );
  });
  test('Character and charslot change one stage', () {
    final lines = parseStoryScript('''
[Character(name="$a")]
[name="甲"]一
[charslot(slot="m", name="$b")]
[name="乙"]二
[Character(name="char_001_x_1", name2="$a", focus=2)]
[name="甲"]三
[charslot(slot="r", name="$b")]
[name="乙"]四
''');
    expect(lines.map((l) => l.portrait), [a, b, a, b]);
    expect(
      parseStoryScript(
        '[Character(name="$a", name2="npc_1_x", focus=2)]\n[name="乙"]一',
      ).single.portrait,
      isNull,
      reason: 'the focused place holds a name that is not a portrait',
    );
  });
  test('a cutin shows its speaker until a cutin without a name', () {
    final lines = parseStoryScript('''
[Character(name="$a")]
[name="甲"]一
[CharacterCutin(widgetID="1", name="char_010_chen_1#2", style="cutin")]
[name="乙"]二
[CharacterCutin(widgetID="1", fadetime=0.5)]
[name="甲"]三
''');
    expect(lines.map((l) => l.portrait), [a, b, a]);
  });
  test('a cutin answered from the stage gives the turn back', () {
    final lines = parseStoryScript('''
[CharacterCutin(widgetID="1", name="char_010_chen_1#2", style="cutin")]
[name="乙"]一
[Character(name="char_001_x_1", name2="$a", focus=2)]
[name="甲"]二
''');
    expect(lines.map((l) => l.portrait), [b, a]);
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

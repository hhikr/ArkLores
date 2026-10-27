import 'package:arklores/core/gamedata/build/story_script.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tracks ordered art changes and leaves text and portraits intact', () {
    const raw = '''[Background(image=" A ")][Background(image="a")][name="X"]One
[Background][largebg(imagegroup=" A / B ")][verticalbg(imagegroup="a/b")][gridbg(imagegroup="a/b")][gridbg(imagegroup="")]
[Image][IMAGE(IMAGE="23_I11")][image(image="23_i11")][Image(image="other")][Image][Image]
[cgitem(image=" X ")][cgitem(image="x")][hidecgitem][hidecgitem]
[Image(image="last")][name="X"]Two''';
    final parsed = parseStoryScriptWithArt(raw);
    expect(parsed.lines.map((l) => [l.kind, l.speaker, l.content, l.portrait]),
        parseStoryScript(raw).map((l) => [l.kind, l.speaker, l.content, l.portrait]),);
    expect(parsed.art.map((e) => [e.atLine, e.kind.value, e.image, e.layout]).toList(), [
      [0, 'background', 'a', null], [1, 'background', null, null],
      [1, 'background', 'a/b', 'row'], [1, 'background', 'a/b', 'column'],
      [1, 'background', 'a/b', 'grid2'], [1, 'background', null, null],
      [1, 'cg', '23_i11', null], [1, 'cg', 'other', null], [1, 'cg_off', null, null],
      [1, 'item', 'x', null], [1, 'item_off', null, null], [1, 'cg', 'last', null],
    ]);
  });
}

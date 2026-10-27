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
    expect(
      parsed.lines.map((l) => [l.kind, l.speaker, l.content, l.portrait]),
      parseStoryScript(raw)
          .map((l) => [l.kind, l.speaker, l.content, l.portrait]),
    );
    expect(
        parsed.art
            .map((e) => [e.atLine, e.kind.value, e.image, e.layout])
            .toList(),
        [
          [0, 'background', 'a', null],
          [1, 'background', null, null],
          [1, 'background', 'a/b', 'row'],
          [1, 'background', 'a/b', 'column'],
          [1, 'background', 'a/b', 'grid2'],
          [1, 'background', null, null],
          [1, 'cg', '23_i11', null],
          [1, 'cg', 'other', null],
          [1, 'cg_off', null, null],
          [1, 'cg', 'last', null],
        ]);
  });

  test(
      'composites named cggroup; several close-ups at once; clearing at the start is no event',
      () {
    const raw =
        '''[Background][largebg(cggroup="61_I12/61_i11", solidwidth="1600/1600")]
[cgitem(image="i_1")][cgitem(image="i_2")][hidecgitem(image="I_1", fadetime=1)][hidecgitem(image="i_1")]
[name="X"]One
[cgitem(image="i_3")][HidecgItem(fadetime=1.5)][hidecgitem]''';
    expect(
        parseStoryScriptWithArt(raw)
            .art
            .map((e) => [e.atLine, e.kind.value, e.image, e.layout])
            .toList(),
        [
          [0, 'background', '61_i12/61_i11', 'row'],
          [0, 'item', 'i_2', null],
          [1, 'item_off', 'i_2', null],
        ]);
  });
  test('layers settle at the next text and retain omitted state', () {
    final art = parseStoryScriptWithArt(
            '''[cgitem(image="a",pfrom="-90,20",sfrom=2,afrom=.5,layer=3)]
[cgitem(image="a",pto="50,-10",sto=1.4)]
One
[cgitem(image="a",pto="60,30")]
Two
[cgitem(image="a",ato=0)]
Three
[cgitem(image="a",ato=1)]
Four
[hidecgitem]
Five''')
        .art;
    expect(
      art.map((e) => (e.atLine, e.kind.value)),
      [(0, 'item'), (1, 'item'), (2, 'item_off'), (3, 'item'), (4, 'item_off')],
    );
    expect(
      (art[0].x, art[0].y, art[0].scale, art[0].alpha, art[0].layer),
      (50.0, -10.0, 1.4, .5, 3),
    );
    expect((art[1].x, art[1].scale, art[1].alpha), (60.0, 1.4, .5));
    expect(art[3].x, 60);
  });
  test('animations without a text boundary produce no layer event', () {
    final art = parseStoryScriptWithArt('''[cgitem(image="a")]
[cgitem(image="a",ato=.01)]
One
[cgitem(image="b")][hidecgitem]
Two''').art;
    expect(art, isEmpty);
  });
  test('layers still up when the story ends go with it', () {
    final art = parseStoryScriptWithArt('''[Image(image="x")][cgitem(image="a")]
One
[Image]''').art;
    expect(
      art.map((e) => (e.atLine, e.kind.value, e.image)),
      [(0, 'cg', 'x'), (0, 'item', 'a'), (1, 'cg_off', null), (1, 'item_off', 'a')],
    );
  });
}

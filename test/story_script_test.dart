import 'package:arklores/core/gamedata/build/story_script.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<(String?, String, StoryLineKind)> parse(String raw) => [
        for (final l in parseStoryScript(raw)) (l.speaker, l.content, l.kind),
      ];

  test('keeps what the earlier importer kept', () {
    final lines = parse('''
[name="甲"]  你好。
这是一行旁白。
[Background(image="bg_1")]
[name="乙"]<i>再见</i>
''');
    expect(lines, [
      ('甲', '你好。', StoryLineKind.dialogue),
      (null, '这是一行旁白。', StoryLineKind.narration),
      ('乙', '再见', StoryLineKind.dialogue),
    ]);
  });

  test('reads dialogue written with other commands', () {
    final lines = parse('''
[name="", avatarId="x", isAvatarRight="FALSE"]   晴 \\ 能见度 14公里
[name="丙", avatarId="npc_1", isAvatarRight="FALSE"] 带属性的对白。
[multiline(name="丁")] 多行对白的一行
[dialog(head="npc_691_1",delay=1,style="other")]没有名字的对话框。
[narration(delay=1)]旁白。
[VoiceWithin(head="npc_693_1",delay=1)]内心的声音。
[Title]一个标题
[HEADER(key="t", is_skippable=true)] 第一关（前）
[Dialog]
''');
    expect(lines, [
      (null, '晴 \\ 能见度 14公里', StoryLineKind.narration),
      ('丙', '带属性的对白。', StoryLineKind.dialogue),
      ('丁', '多行对白的一行', StoryLineKind.dialogue),
      (null, '没有名字的对话框。', StoryLineKind.dialogue),
      (null, '旁白。', StoryLineKind.narration),
      (null, '内心的声音。', StoryLineKind.narration),
      (null, '一个标题', StoryLineKind.title),
      (null, '第一关（前）', StoryLineKind.title),
    ]);
  });

  test('reads captions, documents and the options of a choice', () {
    final lines = parse('''
[Subtitle(text="夜幕降临。", x=300, y=370, alignment="center", size=24)]
[Sticker(id="st1", text="<i>亲爱的K先生：</i>", x=200,y=170, width=700)]
[Sticker(id="st1")]
[Decision(options="早就该交给我了！;……;简单。", values="1;2;3")]
[Predicate(references="1;2;3")]
''');
    expect(lines, [
      (null, '夜幕降临。', StoryLineKind.subtitle),
      (null, '亲爱的K先生：', StoryLineKind.document),
      (null, '早就该交给我了！ ／ …… ／ 简单。', StoryLineKind.choice),
    ]);
  });

  test('marks tutorial text as system and ignores stage commands', () {
    final lines = parse('''
[HEADER(is_skippable=false, is_tutorial=true)] 引导
[PopupDialog(dialogHead="\$avatar_sys")] 点击进入终端界面。
[Tutorial(target="btn", animStyle="Highlight")] 选择一个委托。
[summonenemy(enemyId="enemy_1", x="5")]
[delay(time="2")]
[charslot]: 2652 次
''');
    expect(lines, [
      (null, '引导', StoryLineKind.title),
      (null, '点击进入终端界面。', StoryLineKind.system),
      (null, '选择一个委托。', StoryLineKind.system),
    ]);
  });

  test('a command spread over several lines is one command with its text',
      () {
    final lines = parse('''
[PopupDialog(dialogHead="\$avatar_a", dialogX="\$f_x")] \\
第一句。

[Tutorial(focusX=0, focusY=-85, anchor="Top",\\
          animStyle="Highlight", focusStyle="HighlightRect", \\
          protectTime=0.5, dialogHead="\$avatar_a")] \\
第二句，<@tu.kw>重点</>。
[Tutorial(startX=84, startY=10, endX=74, endY=206)] \\
[name="甲"]后面还有命令。
''');
    expect(lines.map((l) => l.$2), ['第一句。', '第二句，重点。', '后面还有命令。']);
    expect(lines.take(2).every((l) => l.$3 == StoryLineKind.system), isTrue);
    expect(lines.last.$1, '甲');
    // No attribute of a command ends up as text.
    for (final l in lines) {
      expect(l.$2, isNot(contains('=')));
      expect(l.$2, isNot(contains('\\')));
    }
  });
  test('a bracket inside a quoted value does not end the command', () {
    final lines = parse('[Subtitle(text="他说：[出发]", x=1)]');
    expect(lines.single.$2, '他说：[出发]');
  });

  test('unbalanced and empty lines are skipped', () {
    expect(parse('[name="甲" 缺括号\n\n   \n'), isEmpty);
  });

  test('legacy kinds are dialogue and narration only', () {
    expect(StoryLineKind.legacy, {
      StoryLineKind.dialogue,
      StoryLineKind.narration,
    });
    expect(StoryLineKind.fromValue('subtitle'), StoryLineKind.subtitle);
    expect(StoryLineKind.fromValue('x'), StoryLineKind.dialogue);
  });
}

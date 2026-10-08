// 0.12: a conversation read from its dialog tree (the shape of the client's
// `Beyond.Gameplay.DialogTree` TextAssets; ids made up).
import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/gamedata/build/endfield/endfield_dialog_tree.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> trunk(String id, String row) => {
      r'$id': id,
      r'$type': 'Beyond.Gameplay.DialogTreeTrunkNode',
      '_actorNodeData': {
        'mfTrunkActionData': {'_trunkId': row},
      },
    };

Map<String, dynamic> option(String id, List<String> options) => {
      r'$id': id,
      r'$type': 'Beyond.Gameplay.DialogTreeOptionNode',
      '_normalOptions': [
        for (final o in options) {'_optionId': o},
      ],
    };

Map<String, dynamic> node(String id, String type) =>
    {r'$id': id, r'$type': 'Beyond.Gameplay.DialogTree$type'};

Map<String, dynamic> tree(List<Map<String, dynamic>> nodes, List<(String, String)> links) => {
      'type': 'Beyond.Gameplay.DialogTree',
      'nodes': nodes,
      'connections': [
        for (final (a, b) in links)
          {
            '_sourceNode': {r'$ref': a},
            '_targetNode': {r'$ref': b},
          },
      ],
    };

void main() {
  test('choices with their own replies read option by option, then on from where they meet', () {
    // 1 → 2 → choice (a: 20 21 | b: 7 | c: 12 → choice (x: 17 | y: 15) → 19)
    //   → 9 → choice that does not branch (p/q) → 11 → end; a summary aside.
    final t = tree(
      [
        trunk('0', 'd_1'),
        trunk('1', 'd_2'),
        option('2', ['o_1_1', 'o_1_2', 'o_1_3']),
        trunk('3', 'd_20'),
        trunk('4', 'd_21'),
        trunk('5', 'd_7'),
        trunk('6', 'd_12'),
        option('7', ['o_3_1', 'o_3_2']),
        trunk('8', 'd_17'),
        trunk('9', 'd_15'),
        trunk('10', 'd_19'),
        trunk('11', 'd_9'),
        option('12', ['o_2_1', 'o_2_2']),
        trunk('13', 'd_11'),
        node('14', 'FinishNode'),
        node('15', 'ExSummaryNode'),
        node('16', 'ExActorNode'),
      ],
      [
        // Settings nodes hang off a step, the first way out among them.
        ('0', '16'), ('0', '1'), ('0', '15'), ('1', '2'),
        ('2', '3'), ('2', '5'), ('2', '6'),
        ('3', '4'), ('4', '11'),
        ('5', '11'),
        ('6', '7'), ('7', '8'), ('7', '9'), ('8', '10'), ('9', '10'), ('10', '11'),
        ('11', '12'), ('12', '13'), ('12', '13'), ('13', '14'),
      ],
    );
    expect(readDialogTree(t).map((s) => '$s'), [
      'd_1', 'd_2',
      '[o_1_1]', 'd_20', 'd_21',
      '[o_1_2]', 'd_7',
      '[o_1_3]', 'd_12', '[o_3_1]', 'd_17', '[o_3_2]', 'd_15', 'd_19',
      'd_9', '[o_2_1/o_2_2]', 'd_11',
    ]);
  });

  test('a cutscene node is a step; its lines come from the clips by start time', () async {
    final t = tree(
      [
        trunk('0', 'd_x_1'),
        {
          r'$id': '1',
          r'$type': 'Beyond.Gameplay.DialogTreeCinematicNode',
          '_actionData': {'name': 'dlgtl_x_sub_1'},
        },
        node('2', 'FinishNode'),
      ],
      [('0', '1'), ('1', '2')],
    );
    expect(readDialogTree(t).map((s) => '$s'), ['d_x_1', '<dlgtl_x_sub_1>']);

    final dir = Directory.systemTemp.createTempSync('arklores_clips');
    addTearDown(() => dir.deleteSync(recursive: true));
    var n = 0;
    void clip(Map<String, Object?> json) =>
        File('${dir.path}/${n++}.json').writeAsStringSync(jsonEncode(json));
    Map<String, Object?> meta(int pathId, {List<Object?> refs = const []}) => {
          'pathId': pathId,
          'sourceFile': 'CAB-a',
          'pptrReferences': refs,
        };
    // Numbered 5 but shown last; the option is offered after line 16.
    clip({r'$animestudio': meta(1), '_trunkId': 'dlg_x_1_005', 'startTime': 30.0});
    clip({
      r'$animestudio': meta(
        2,
        refs: [
          {'path': r'$.bindingOptionAssets._valueData[0]', 'pathId': 9, 'expectedTargetSourceFile': 'CAB-a'},
        ],
      ),
      '_trunkId': 'dlg_x_1_016',
      'startTime': 2.5,
    });
    clip({r'$animestudio': meta(3), '_trunkId': 'dlg_x_1_017', 'startTime': 10.0});
    // A choice's options in one asset (a single option is a map instead).
    clip({
      r'$animestudio': meta(9),
      'options': [
        {'_optionId': 'option_dlg_x_1_1_001'},
        {'_optionId': 'option_dlg_x_1_1_002'},
      ],
    });
    final lines = loadTimelineLines([dir])['dlg_x_1']!;
    expect(lines.map((l) => l.rowId), ['dlg_x_1_016', 'dlg_x_1_017', 'dlg_x_1_005']);
    expect(lines.first.options, ['option_dlg_x_1_1_001', 'option_dlg_x_1_1_002']);
  });

  test('a tree that only starts a cutscene has no steps; a loop ends', () {
    final cutscene = tree([node('0', 'CinematicNode'), node('1', 'FinishNode')], [('0', '1')]);
    expect(readDialogTree(cutscene), isEmpty);
    final loop = tree(
      [trunk('0', 'd_1'), option('1', ['o_1_1', 'o_1_2']), trunk('2', 'd_2'), node('3', 'FinishNode')],
      // Asking again leads back to the first line; leaving ends it.
      [('0', '1'), ('1', '0'), ('1', '2'), ('2', '3')],
    );
    final steps = readDialogTree(loop).map((s) => '$s').toList();
    expect(steps.first, 'd_1');
    expect(steps, contains('d_2'));
  });
}

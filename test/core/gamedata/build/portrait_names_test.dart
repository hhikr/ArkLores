import 'package:arklores/core/gamedata/build/portrait_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cases = {
    'char_002_amiya_1#5': r'char_002_amiya_1#5$1',
    r'avg_4137_udflow_1#4$1': r'avg_4137_udflow_1#4$1',
    'avg_npc_003': r'avg_npc_003#1$1',
    r'avg_npc_1793_1#10 $1': r'avg_npc_1793_1#10$1',
    'Char_102_Texas_1#1': r'char_102_texas_1#1$1',
    'char_002_amiya_1+': r'char_002_amiya_1+#1$1',
    'bg_cher_1': null,
    '': null,
    'char_x#-1': null,
    r'char_x$2#1': null,
    'char_x#2junk': null,
    r'char_x$2': r'char_x#1$2',
  };
  for (final entry in cases.entries) {
    test('canonicalSprite ${entry.key}', () {
      expect(canonicalSprite(entry.key), entry.value);
      if (entry.value != null) {
        expect(SpriteName.parse(entry.value!)!.canonical, entry.value);
      }
    });
  }
  test('parse rejects noncanonical names', () {
    for (final value in [
      'char_x',
      'CHAR_x#1\$1',
      'char_x#01\$1',
      'bg_x#1\$1',
    ]) {
      expect(SpriteName.parse(value), isNull);
    }
  });
}

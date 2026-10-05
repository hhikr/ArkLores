import 'package:arklores/core/library/placeholders.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Doctor placeholder is the reader\'s form of address', () {
    expect(
      withPlaceholders('Dr.{@nickname}，早。{@Nickname}。', '阿某'),
      'Dr.阿某，早。阿某。',
    );
    // Nothing entered: the default; the texts themselves are not touched.
    expect(withPlaceholders('{@nickname}好', '  '), '博士好');
    expect(withPlaceholders('{@nickname}好', '', fallback: 'Doctor'), 'Doctor好');
    expect(withPlaceholders('没有占位符', '阿某'), '没有占位符');
    expect(withPlaceholders('甲{@nbs}乙', ''), '甲\u00a0乙');
  });
}

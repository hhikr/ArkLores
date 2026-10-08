import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guard for the app's look: both games draw square panels, mark a chosen
/// tab with a bar and move panels in straight, short motions. Rounded
/// corners, circles, stadium shapes, the rounded icon set and springy
/// curves crept in once (0.11) and were taken out in 0.12; they must not
/// come back. Cut corners (`ThemeAwareCard`) and thin bars are the way to
/// set a panel off.
void main() {
  test('lib/ draws no rounded shapes and no springy motion', () {
    final pattern = RegExp(
      r'BorderRadius\.circular|Radius\.circular|Radius\.elliptical|'
      r'CircleBorder|StadiumBorder|BoxShape\.circle|ClipOval|'
      r'Icons\.\w+_rounded\b|Curves\.(easeOutBack|easeInBack|easeInOutBack|'
      r'elastic\w*|bounce\w*)',
    );
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (pattern.hasMatch(lines[i])) {
          hits.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}

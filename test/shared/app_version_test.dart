import 'dart:io';

import 'package:arklores/shared/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the version shown in Settings is the one in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version =
        RegExp(r'^version:\s*([^+\s]+)', multiLine: true).firstMatch(pubspec)!;
    expect(appVersion, version.group(1));
  });
}

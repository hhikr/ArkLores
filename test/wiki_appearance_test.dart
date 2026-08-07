import 'package:arklores/features/wiki/wiki_appearance_palette.dart';
import 'package:arklores/features/wiki/wiki_appearance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wiki appearance uses semantic colors instead of page inversion', () {
    final css = WikiAppearance.cssForTesting();

    expect(css, isNot(contains('filter: invert')));
    expect(css, contains('--arklores-page-bg'));
    expect(css, contains('color-scheme: dark'));
    expect(css, contains('color-scheme: light'));
    expect(css, contains('arklores-prts-site'));
    expect(css, contains('arklores-generic-site'));
    expect(css, isNot(contains('html[data-arklores-appearance] body {')));
  });

  test('rendered media and simulators are protected from appearance changes',
      () {
    final css = WikiAppearance.cssForTesting();

    for (final selector in [
      'img',
      'video',
      'canvas',
      'svg',
      'iframe',
      '#sys_fullscreen',
      '#sys_playback_all',
      '#spine-root',
      '#voice-table-root',
    ]) {
      expect(css, contains(selector));
    }
    expect(css, contains('filter: none !important'));
  });

  test('reader palettes keep light and dark surfaces distinct', () {
    expect(
      WikiAppearancePalette.dark.pageBackground,
      isNot(WikiAppearancePalette.light.pageBackground),
    );
    expect(
      WikiAppearancePalette.dark.text,
      isNot(WikiAppearancePalette.light.text),
    );
    expect(WikiAppearancePalette.dark.selection, contains('rgba'));
    expect(WikiAppearancePalette.light.selection, contains('rgba'));
  });
}

import 'package:arklores/features/wiki/wiki_appearance.dart';
import 'package:arklores/features/wiki/wiki_appearance_palette.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wiki appearance uses semantic colors instead of page inversion', () {
    final css = WikiAppearance.cssForTesting();

    expect(css, isNot(contains('filter: invert')));
    expect(css, contains('--arklores-page-bg'));
    expect(css, contains('color-scheme: dark'));
    expect(css, contains('color-scheme: light'));
    // PRTS has its own night theme: none of these rules is for it.
    expect(css, isNot(contains('arklores-prts-site')));
    expect(css, contains('arklores-generic-site'));
    expect(css, isNot(contains('html[data-arklores-appearance] body {')));
  });

  test('rendered media are protected from appearance changes', () {
    final css = WikiAppearance.cssForTesting();

    for (final selector in ['img', 'video', 'canvas', 'svg', 'iframe']) {
      expect(css, contains(selector));
    }
    expect(css, contains('filter: none !important'));
    // PRTS's own widgets are never restyled: it gets no CSS at all.
    expect(css, isNot(contains('prts-widget')));
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
  });
}

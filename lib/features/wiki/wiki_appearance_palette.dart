/// The colours [WikiAppearance] gives a wiki without a dark theme of its own
/// (PRTS, fz.wiki and Warfarin switch their own).
class WikiAppearancePalette {
  const WikiAppearancePalette({
    required this.pageBackground,
    required this.surface,
    required this.surfaceElevated,
    required this.border,
    required this.text,
    required this.muted,
    required this.link,
    required this.controlSurface,
    required this.controlText,
  });

  final String pageBackground;
  final String surface;
  final String surfaceElevated;
  final String border;
  final String text;
  final String muted;
  final String link;
  final String controlSurface;
  final String controlText;

  static const dark = WikiAppearancePalette(
    pageBackground: '#0B0F14',
    surface: '#121A23',
    surfaceElevated: '#172230',
    border: '#2B3A4B',
    text: '#E8EDF2',
    muted: '#A7B1BA',
    link: '#7AC7DD',
    controlSurface: '#172230',
    controlText: '#DCE8F0',
  );

  static const light = WikiAppearancePalette(
    pageBackground: '#F6F3EA',
    surface: '#FFFDF7',
    surfaceElevated: '#EFE8DA',
    border: '#DED6C8',
    text: '#24211C',
    muted: '#686157',
    link: '#236A80',
    controlSurface: '#ECE5D8',
    controlText: '#17202A',
  );
}

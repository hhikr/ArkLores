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
    required this.tableHeader,
    required this.selection,
    required this.storySurface,
    required this.storyHeader,
    required this.componentSurface,
    required this.componentHeader,
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
  final String tableHeader;
  final String selection;
  final String storySurface;
  final String storyHeader;
  final String componentSurface;
  final String componentHeader;

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
    tableHeader: '#151E29',
    selection: 'rgba(122, 199, 221, 0.28)',
    storySurface: '#111A24',
    storyHeader: '#172230',
    componentSurface: 'rgba(23, 38, 56, 0.84)',
    componentHeader: 'rgba(34, 57, 80, 0.78)',
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
    tableHeader: '#EFE8DA',
    selection: 'rgba(35, 106, 128, 0.18)',
    storySurface: '#FFFDF7',
    storyHeader: '#EFE8DA',
    componentSurface: 'rgba(231, 239, 239, 0.86)',
    componentHeader: 'rgba(213, 227, 228, 0.9)',
  );
}

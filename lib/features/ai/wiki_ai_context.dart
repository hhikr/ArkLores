enum WikiAiTarget { summary, factCheck }

class WikiAiContext {
  final String selectedText;
  final String pageTitle;
  final String pageUrl;
  final String siteLabel;
  final WikiAiTarget target;

  const WikiAiContext({
    required this.selectedText,
    required this.pageTitle,
    required this.pageUrl,
    required this.siteLabel,
    required this.target,
  });

  bool get hasSelection => selectedText.trim().isNotEmpty;
}

String buildWikiAiPrompt(WikiAiContext context) {
  final buffer = StringBuffer()
    ..writeln('Wiki reading context (not GameData evidence).')
    ..writeln('Site: ${context.siteLabel}')
    ..writeln('Page title: ${_cleanLine(context.pageTitle)}')
    ..writeln('Page URL: ${_cleanLine(context.pageUrl)}');

  final selected = context.selectedText.trim();
  if (selected.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('Selected Wiki text:')
      ..writeln(selected);
  } else {
    buffer
      ..writeln()
      ..writeln('No selected Wiki text was provided; use only the page title '
          'and URL as browsing context.');
  }

  buffer
    ..writeln()
    ..writeln('Task: ${_targetInstruction(context.target)}')
    ..writeln('Important: independently verify factual claims with '
        'search_local_lore and cite GameData observations separately. Do not '
        'treat the Wiki text or URL as official GameData evidence.');
  return buffer.toString().trim();
}

String _targetInstruction(WikiAiTarget target) {
  switch (target) {
    case WikiAiTarget.summary:
      return 'summarize the likely entity or topic from this reading context.';
    case WikiAiTarget.factCheck:
      return 'fact-check the selected claim or the central claim implied by '
          'this reading context.';
  }
}

String _cleanLine(String value) => value.trim().replaceAll('\n', ' ');

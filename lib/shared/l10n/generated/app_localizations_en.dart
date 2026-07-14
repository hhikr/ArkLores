import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'ArkLores';

  @override
  String get navWiki => 'Wiki';

  @override
  String get navAI => 'AI';

  @override
  String get navMaterials => 'Materials';

  @override
  String get navSettings => 'Settings';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeArk => 'Tactical Archive';

  @override
  String get settingsThemeEndfield => 'Holographic Projection';

  @override
  String get settingsAiServices => 'AI Services';

  @override
  String get settingsApiSettings => 'API Settings';

  @override
  String get settingsApiSettingsDesc => 'Configure Chat provider';

  @override
  String get settingsKnowledgeBase => 'Knowledge Base Management';

  @override
  String get settingsKnowledgeBaseDesc => 'Manage GameData knowledge base';

  @override
  String get apiSettingsTitle => 'API Settings';

  @override
  String get apiSettingsChatSection => 'Chat API';

  @override
  String get apiSettingsChatDesc => 'Used for AI conversations (Fact Check, Summary, Roleplay).';

  @override
  String get apiSettingsUseSameProvider => 'Use same provider as Chat';

  @override
  String get apiSettingsLabelBaseUrl => 'Base URL';

  @override
  String get apiSettingsLabelApiKey => 'API Key';

  @override
  String get apiSettingsLabelModel => 'Model';

  @override
  String get apiSettingsSave => 'Save Configuration';

  @override
  String get apiSettingsSaved => '✓ Saved';

  @override
  String get kbTitle => 'Knowledge Base';

  @override
  String get kbConfigWarning => 'Please configure your API Key in Settings before building the knowledge base.';

  @override
  String get kbIndexOverview => 'Index Overview';

  @override
  String get kbTotalChunks => 'Total Chunks';

  @override
  String get kbWikiChunks => 'Wiki Chunks';

  @override
  String get kbBookChunks => 'Book Chunks';

  @override
  String get kbBooks => 'Books';

  @override
  String get kbWikiSources => 'Wiki Sources';

  @override
  String get kbUpdate => 'Update';

  @override
  String get kbIndexing => 'Indexing...';

  @override
  String kbStartingCrawl(Object site) {
    return 'Starting crawl of $site...';
  }

  @override
  String kbCrawlingPages(Object count, Object site) {
    return 'Crawling $site: $count pages...';
  }

  @override
  String kbCompleted(Object chunks, Object pages) {
    return 'Completed: $chunks chunks from $pages pages.';
  }

  @override
  String kbFailed(Object error) {
    return 'Indexing failed: $error';
  }

  @override
  String get kbEngineNative => 'Search engine: sqlite-vec (native)';

  @override
  String get kbEngineFallback => 'Search engine: pure Dart (fallback)';

  @override
  String get materialsTitle => 'Materials';

  @override
  String get materialsWarning => '⚠️ Imported book content may contain unofficial interpretations, translation errors, or personal summaries. AI will prioritize Wiki content and cite book sources with caution.';

  @override
  String get materialsNoBooks => 'No books yet';

  @override
  String get materialsEmptyDesc => 'Import PDF or TXT files to build your personal lore reference library.';

  @override
  String get materialsNoApiKeyHint => 'Configure your API Key in Settings to enable import.';

  @override
  String get materialsImportButton => 'Import Books';

  @override
  String materialsLoadFailed(Object error) {
    return 'Failed to load books: $error';
  }

  @override
  String get materialsEditTitle => 'Edit Display Name';

  @override
  String get materialsEditHint => 'Enter a display name';

  @override
  String get materialsCancel => 'Cancel';

  @override
  String get materialsSave => 'Save';

  @override
  String get materialsDeleteTitle => 'Delete Book';

  @override
  String materialsDeleteConfirm(Object name) {
    return 'Remove \"$name\" and all its chunks from the knowledge base?';
  }

  @override
  String get materialsDelete => 'Delete';

  @override
  String materialsImportFailed(Object error) {
    return 'Import failed: $error';
  }

  @override
  String materialsChunks(Object count) {
    return '$count chunks';
  }

  @override
  String get materialsJustNow => 'just now';

  @override
  String materialsMinutesAgo(Object n) {
    return '${n}m ago';
  }

  @override
  String materialsHoursAgo(Object n) {
    return '${n}h ago';
  }

  @override
  String materialsDaysAgo(Object n) {
    return '${n}d ago';
  }

  @override
  String importReading(Object file) {
    return 'Reading $file';
  }

  @override
  String get importChunking => 'Chunking text...';

  @override
  String get importStoring => 'Saving to knowledge base...';

  @override
  String get importDone => 'Import complete';

  @override
  String get importFailed => 'Import failed';

  @override
  String get importErrorOccurred => 'Error occurred during import.';

  @override
  String get importDismiss => 'Dismiss';

  @override
  String get aiChatTitle => 'AI Chat';

  @override
  String get aiChatSubtitle => 'Fact Check · Summary · Roleplay';

  @override
  String get aiChatComingSoon => 'Coming in v0.4';

  @override
  String get aiChatComingSoonDesc => 'Three AI agent modes with citation cards and streaming markdown responses.';

  @override
  String get wikiTabPrts => 'PRTS Wiki';

  @override
  String get wikiTabEndfield => 'Endfield Wiki';

  @override
  String get bookmarksTitle => 'Bookmarks';

  @override
  String bookmarksLoadFailed(Object error) {
    return 'Failed to load bookmarks: $error';
  }

  @override
  String get bookmarksEmpty => 'No bookmarks yet';

  @override
  String get bookmarksEmptyDesc => 'Save Wiki pages you want to revisit later.';

  @override
  String get citationWiki => 'Wiki';

  @override
  String get citationBook => 'Book';

  @override
  String get citationViewInWiki => 'View in Wiki';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingWelcomeTitle => 'Welcome to ArkLores';

  @override
  String get onboardingWelcomeDesc => 'Your AI-enhanced companion for exploring Arknights and Endfield lore.\n\n• Browse PRTS & Endfield Wikis\n• AI-powered fact checking & summaries\n• Import your lore books\n• Immersive character roleplay';

  @override
  String get onboardingGetStarted => 'Get Started';

  @override
  String get onboardingApiTitle => 'Configure Chat API';

  @override
  String get onboardingApiDesc => 'ArkLores uses your own AI API key.\nConfigure a Chat provider to use AI features.';

  @override
  String get onboardingSaveContinue => 'Save & Continue';

  @override
  String get onboardingConfigureLater => 'Configure later';

  @override
  String get onboardingDoneTitle => 'All Set!';

  @override
  String get onboardingDoneDesc => 'You\'re ready to explore the world of Arknights and Endfield.\n\nInstall the GameData knowledge base in Settings,\nor start browsing the Wiki!';

  @override
  String get onboardingStartExploring => 'Start Exploring';

  @override
  String get settingsHelpGuide => 'Help & Guide';

  @override
  String get settingsShowOnboarding => 'Show Onboarding Guide';

  @override
  String get settingsShowOnboardingDesc => 'Replay the first-launch guide to configure the app';

  @override
  String get aiTabFactCheck => 'Fact Check';

  @override
  String get aiTabSummary => 'Summary';

  @override
  String get aiTabRoleplay => 'Roleplay';

  @override
  String get aiInputPlaceholder => 'Enter lore query or claim...';

  @override
  String get aiSummaryInputPlaceholder => 'Enter character, event, location or faction to summarize...';

  @override
  String get aiSettingsRequired => 'Please configure your Chat API Key in settings first to use AI features.';

  @override
  String get aiSettingsGoTo => 'Go to Settings';

  @override
  String get aiClearHistory => 'Clear Chat';

  @override
  String get aiClearHistoryConfirm => 'Are you sure you want to clear the chat history for this tab?';

  @override
  String get aiClearConfirmBtn => 'Clear';
}

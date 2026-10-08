// ignore: unused_import
import 'package:intl/intl.dart' as intl;
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
  String get settingsSystemCode => 'ARKLORES / SYSTEM';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsThemeArk => 'Night mode';

  @override
  String get settingsThemeEndfield => 'Day mode';

  @override
  String get settingsThemeArkShort => 'NIGHT';

  @override
  String get settingsThemeEndfieldShort => 'DAY';

  @override
  String get localeEnglishShort => 'EN';

  @override
  String get localeChineseShort => '中文';

  @override
  String get settingsProfile => 'Profile';

  @override
  String get settingsProfileDesc => 'How the stories address you.';

  @override
  String get settingsProfileSectionCode => 'PROFILE';

  @override
  String get profileNicknameLabel => 'Form of address';

  @override
  String get profileNicknameHelp =>
      'Stories write the Doctor\'s name as a placeholder; it is shown as what you enter here (left empty: \"Doctor\"). The knowledge base is not changed.';

  @override
  String get profileNicknameDefault => 'Doctor';

  @override
  String get settingsAiServices => 'AI Services';

  @override
  String get settingsAiSectionCode => 'AI SERVICE';

  @override
  String get settingsApiSettings => 'API Settings';

  @override
  String get settingsApiSettingsDesc => 'Configure the chat provider';

  @override
  String get settingsSessionLogs => 'Save AI conversations';

  @override
  String get settingsSessionLogsDesc =>
      'Fully record every AI conversation (mode selection, auto-routing decision, complete reasoning and retrieved text) to the chat_sessions folder in device storage, used by Chat History for viewing and restoring. Stored on-device only; deletable in-app or from the file manager.';

  @override
  String get settingsKnowledgeBase => 'Knowledge Base Management';

  @override
  String get settingsKnowledgeSectionCode => 'KNOWLEDGE BASE';

  @override
  String get settingsKnowledgeBaseDesc => 'Manage GameData knowledge base';

  @override
  String get apiSettingsTitle => 'API Settings';

  @override
  String get apiSettingsChatSection => 'Chat API';

  @override
  String get apiSettingsChatDesc => 'Used for Ask AI (story questions).';

  @override
  String get apiSettingsEmbeddingSection => 'Embedding API (optional)';

  @override
  String get apiSettingsEmbeddingDesc =>
      'Enables semantic story-line recall for investigations. Must use the same model as the installed knowledge base vectors (e.g. Alibaba Cloud Bailian qwen3.7-text-embedding). Leave the key empty to use keyword search only.';

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
  String get kbConfigWarning =>
      'Please configure your API Key in Settings before building the knowledge base.';

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
  String get kbUpToDate => 'Up to date';

  @override
  String get kbRedownload => 'Download again';

  @override
  String get kbRedownloadTitle => 'Download the knowledge base again?';

  @override
  String get kbRedownloadBody =>
      'You already have the latest version. Downloading again fetches about 185 MB and rebuilds the database (about 1 GB of free space needed). It is rarely necessary.';

  @override
  String get kbRedownloadConfirm => 'Download again';

  @override
  String get kbCancel => 'Cancel';

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
  String get materialsWarning =>
      '⚠️ Imported book content may contain unofficial interpretations, translation errors, or personal summaries. AI will prioritize Wiki content and cite book sources with caution.';

  @override
  String get materialsNoBooks => 'No books yet';

  @override
  String get materialsEmptyDesc =>
      'Keep texts here: lore excerpts, notes, research. They stay on this device and never enter the knowledge base.';

  @override
  String get materialsNoApiKeyHint =>
      'Configure your API Key in Settings to enable import.';

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
  String get materialsDeleteConfirm => 'Delete this text?';

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
  String get aiChatTitle => 'Lore Advisor';

  @override
  String get aiChatComingSoon => 'Coming in v0.4';

  @override
  String get aiChatComingSoonDesc =>
      'Three AI agent modes with citation cards and streaming markdown responses.';

  @override
  String get wikiTabPrts => 'PRTS Wiki';

  @override
  String get wikiTabEndfield => 'Endfield Wiki';

  @override
  String get wikiSendToAi => 'Send to AI';

  @override
  String get wikiSendToAiDesc =>
      'Selected Wiki text is reading context only; factual claims are verified separately with GameData.';

  @override
  String get wikiSendToSummaryDesc =>
      'Summarize from the page and selected text';

  @override
  String get wikiSendToFactCheckDesc =>
      'Use the selected text as the claim to check';

  @override
  String get wikiReaderMode => 'Reader mode';

  @override
  String get wikiReaderFontSmaller => 'Smaller text';

  @override
  String get wikiReaderFontLarger => 'Larger text';

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
  String get onboardingNotNow => 'Not now';

  @override
  String get onboardingWelcomeTitle => 'Welcome to ArkLores';

  @override
  String get onboardingWelcomeDesc =>
      'Your AI-enhanced companion for exploring Arknights and Endfield lore.\n\n• Browse PRTS & Endfield Wikis\n• Ask AI about the story, with sources from the original text\n• Read the stories and game records';

  @override
  String get onboardingGetStarted => 'Get Started';

  @override
  String get onboardingApiTitle => 'Configure Chat API';

  @override
  String get onboardingApiDesc =>
      'ArkLores uses your own AI API key.\nConfigure a Chat provider to use AI features.';

  @override
  String get onboardingSaveContinue => 'Save & Continue';

  @override
  String get onboardingConfigureLater => 'Configure later';

  @override
  String get onboardingDoneTitle => 'All Set!';

  @override
  String get onboardingDoneDesc =>
      'You\'re ready to explore the world of Arknights and Endfield.\n\nInstall the GameData knowledge base in Settings,\nor start browsing the Wiki!';

  @override
  String get onboardingStartExploring => 'Start Exploring';

  @override
  String get settingsHelpGuide => 'Help & Guide';

  @override
  String get settingsHelpSectionCode => 'HELP & GUIDE';

  @override
  String settingsVersionLabel(String version) {
    return 'ARKLORES / $version';
  }

  @override
  String get settingsShowOnboarding => 'Show Onboarding Guide';

  @override
  String get settingsShowOnboardingDesc =>
      'Replay the first-launch guide to configure the app';

  @override
  String get aiTabAsk => 'Ask AI';

  @override
  String get aiAskSource =>
      'Answers are grounded in installed GameData story text only';

  @override
  String get aiAskEmpty =>
      'Ask any lore question: what a character went through, how an event came about, whether a claim is true.';

  @override
  String get aiInputExpand => 'Expand the input';

  @override
  String get aiInputCollapse => 'Collapse the input';

  @override
  String get aiInputFullscreen => 'Full-screen input';

  @override
  String get aiInputExitFullscreen => 'Exit full screen';

  @override
  String get aiAskInputPlaceholder => 'Ask any lore question...';

  @override
  String get aiAskSuggestionAmiya => 'Who is Amiya?';

  @override
  String get aiAskSuggestionVerify =>
      'Is Amiya the public leader of Rhodes Island?';

  @override
  String get aiAskSuggestionInvestigate => 'How was Reunion founded?';

  @override
  String get aiAskError => 'Failed to answer. Please retry.';

  @override
  String get aiAskCanceled => 'Answer canceled.';

  @override
  String get aiTabFactCheck => 'Fact Check';

  @override
  String get aiTabSummary => 'Summary';

  @override
  String get aiAnswerStatus => 'Answer status';

  @override
  String get aiAnswerStatusAnswered => 'Answered';

  @override
  String get aiAnswerStatusPartial => 'Partial (limited evidence)';

  @override
  String get aiAnswerStatusNotCovered => 'Not covered by the knowledge base';

  @override
  String get aiInvestigationConfidence => 'Confidence';

  @override
  String aiCitationLine(int line) {
    return 'line $line';
  }

  @override
  String aiCitationLines(int start, int end) {
    return 'lines $start–$end';
  }

  @override
  String aiAnswerDetails(int count) {
    return 'Details · $count points';
  }

  @override
  String aiEvidenceSummary(int count, int stories) {
    return '$count citations · $stories stories';
  }

  @override
  String aiChapterCount(int count) {
    return '$count cited';
  }

  @override
  String get aiCitedRecord => 'Record';

  @override
  String aiCitedRecords(int count) {
    return '$count other records';
  }

  @override
  String get aiCitedLinesUnavailable =>
      'Original text unavailable (knowledge base missing or updated)';

  @override
  String get aiStoryReaderTitle => 'Original text';

  @override
  String aiCitationSources(int count) {
    return 'Sources $count';
  }

  @override
  String get aiStoryReaderJumpBack => 'Back to the cited lines';

  @override
  String aiStoryReaderCited(String range) {
    return 'Cited: $range';
  }

  @override
  String get aiStoryReaderEnd => 'End of chapter';

  @override
  String get libraryTabRead => 'Read';

  @override
  String get libraryTabMine => 'My texts';

  @override
  String get librarySearchTitle => 'Search';

  @override
  String get librarySearchHint => 'Search chapters, entries, stage codes';

  @override
  String get libraryContinue => 'Continue reading';

  @override
  String get libraryShelves => 'Shelves';

  @override
  String get libraryViewAll => 'All';

  @override
  String get shelfMain => 'Main story';

  @override
  String get shelfActivity => 'Other events';

  @override
  String get shelfSideStory => 'Side Story';

  @override
  String get shelfMiniStory => 'Story collections';

  @override
  String get shelfBranchline => 'Interludes';

  @override
  String get shelfMemory => 'Operators';

  @override
  String get shelfRoguelike => 'Integrated Strategies';

  @override
  String get shelfSandbox => 'Sandbox';

  @override
  String get shelfRetro => 'Re-runs';

  @override
  String get shelfCodex => 'Codex';

  @override
  String get shelfOther => 'Other';

  @override
  String get libraryOperatorRecords => 'Operator records';

  @override
  String get libraryOperatorProfile => 'Operator file';

  @override
  String get libraryAllEntries => 'All';

  @override
  String libraryCountCollections(int n) {
    return '$n sets';
  }

  @override
  String libraryCountStories(int n) {
    return '$n stories';
  }

  @override
  String libraryCountEntries(int n) {
    return '$n entries';
  }

  @override
  String get libraryNotInstalledTitle => 'No knowledge base yet';

  @override
  String get libraryNotInstalledDesc =>
      'Download or build it under Settings → Knowledge base; the stories and texts to read appear here.';

  @override
  String get libraryOldSchemaTitle => 'The knowledge base needs an update';

  @override
  String get libraryOldSchemaDesc =>
      'The installed knowledge base is an older version without the story-set index. Update it under Settings → Knowledge base to read here.';

  @override
  String get libraryEmpty => 'Nothing here yet';

  @override
  String get libraryStories => 'Stories';

  @override
  String get libraryOtherSections => 'Related texts';

  @override
  String get libraryParts => 'Unlocked stories';

  @override
  String get libraryLeftoverStories => 'Other stories';

  @override
  String get libraryFilterHint => 'Filter this list';

  @override
  String libraryProgress(int percent) {
    return '$percent% read';
  }

  @override
  String get libraryFinished => 'Finished';

  @override
  String get storyReaderBattleDialogue => 'In-battle dialogue';

  @override
  String libraryReadTimes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Read $count times',
      one: 'Read once',
    );
    return '$_temp0';
  }

  @override
  String libraryRelease(String month) {
    return 'Released $month';
  }

  @override
  String get libraryRelated => 'Related';

  @override
  String get libraryNoText => 'This entry has no text';

  @override
  String get libraryNoResults => 'Nothing found';

  @override
  String get librarySearchCollections => 'Story sets and topics';

  @override
  String get librarySearchEntries => 'Entries';

  @override
  String get storyReaderNext => 'Next chapter';

  @override
  String get storyReaderPrevious => 'Previous chapter';

  @override
  String storyReaderResumed(int line) {
    return 'Continue · line $line';
  }

  @override
  String get storyReaderSynopsis => 'Official synopsis';

  @override
  String get materialsEmptyTitle => 'No texts of your own yet';

  @override
  String get materialsNew => 'New';

  @override
  String get materialsPaste => 'Paste from clipboard';

  @override
  String get materialsTitleHint => 'Title (optional)';

  @override
  String get materialsBodyHint => 'Text';

  @override
  String get materialsEdit => 'Edit';

  @override
  String materialsChars(int n) {
    return '$n characters';
  }

  @override
  String get materialsClipboardEmpty => 'The clipboard has no text';

  @override
  String get materialsDiscard => 'Discard unsaved changes?';

  @override
  String get materialsDiscardAction => 'Discard';

  @override
  String get materialsAskAbout => 'Ask about it';

  @override
  String get readingHistoryTitle => 'Recently read';

  @override
  String get readingHistoryEmpty =>
      'Nothing read yet. Stories you open from an answer\'s evidence show up here.';

  @override
  String readingHistoryPage(Object page, Object pages) {
    return 'Page $page / $pages';
  }

  @override
  String get readingHistoryClear => 'Clear';

  @override
  String get readingHistoryJumpTitle => 'Go to page';

  @override
  String readingHistoryJumpHint(int pages) {
    return '1 – $pages';
  }

  @override
  String get readingHistoryJumpGo => 'Go';

  @override
  String get readingHistoryClearConfirm => 'Clear the whole reading history?';

  @override
  String get readingHistoryRemove => 'Remove from history';

  @override
  String readingHistoryLine(int line) {
    return 'line $line';
  }

  @override
  String get aiStoryReaderMoved =>
      'The text changed; showing the approximate place';

  @override
  String get aiMoreActions => 'More';

  @override
  String get aiThinkingProcess => 'Thinking';

  @override
  String get aiDeepThinking => 'Deep thinking';

  @override
  String get aiDeepThinkingTooltip =>
      'Think before writing the answer (slower, more tokens)';

  @override
  String get aiScrollToBottom => 'Scroll to bottom';

  @override
  String get aiInvestigationCoverage => 'Coverage';

  @override
  String get aiInvestigationRead => 'read';

  @override
  String get aiInvestigationMapped => 'mapped';

  @override
  String get aiInvestigationSkipped => 'skipped';

  @override
  String get aiVerdictSupported => 'Supported';

  @override
  String get aiVerdictRefuted => 'Refuted';

  @override
  String get aiVerdictUncertain => 'Uncertain';

  @override
  String get aiVerdictUnavailable => 'Cannot confirm';

  @override
  String aiVerdictSemantics(String verdict) {
    return 'Fact-check verdict: $verdict';
  }

  @override
  String aiEvidenceTitle(int count) {
    return 'GameData evidence ($count)';
  }

  @override
  String get aiEvidenceSection => 'Section';

  @override
  String get aiEvidenceContentType => 'Content type';

  @override
  String get aiEvidenceSourcePath => 'Source path';

  @override
  String get aiEvidenceRawId => 'Raw ID';

  @override
  String get aiEvidenceRetrievalType => 'Retrieval type';

  @override
  String get aiEvidenceRankingReason => 'Ranking reason';

  @override
  String get aiEvidenceTrustNote => 'Trust note';

  @override
  String get aiCoverageDirect => 'Direct candidate';

  @override
  String get aiCoverageRetrieved => 'Retrieved context';

  @override
  String aiEvidenceSemantics(String title, String coverage) {
    return 'GameData evidence: $title; coverage: $coverage';
  }

  @override
  String get aiThinking => 'Thinking…';

  @override
  String get aiReasoning => 'Reasoning…';

  @override
  String get aiProcessing => 'Processing…';

  @override
  String get aiReasoningComplete => 'Reasoning complete';

  @override
  String aiUsingTool(String tool) {
    return 'Using tool: $tool';
  }

  @override
  String aiWorkSummary(int calls, int reads) {
    return '$calls lookups · $reads stories read';
  }

  @override
  String get aiWorkSql => 'Query the knowledge base';

  @override
  String aiWorkGrep(String pattern) {
    return 'Search for “$pattern”';
  }

  @override
  String aiWorkGrepIn(String scope, String pattern) {
    return 'Search “$pattern” in $scope';
  }

  @override
  String aiWorkRead(String story) {
    return 'Read “$story”';
  }

  @override
  String aiWorkOutline(String collection) {
    return 'Chapter list of $collection';
  }

  @override
  String aiWorkFind(String query) {
    return 'Find by meaning: “$query”';
  }

  @override
  String aiWorkSimilar(String name) {
    return 'Names like “$name”';
  }

  @override
  String aiWorkDelegate(String task) {
    return 'Helper: $task';
  }

  @override
  String get aiWorkRedo => 'Sources did not match; rewriting';

  @override
  String aiWorkHits(int hits, int stories) {
    return '$hits hits · $stories stories';
  }

  @override
  String aiWorkRows(int count) {
    return '$count rows';
  }

  @override
  String aiWorkLines(int start, int end) {
    return 'lines $start–$end';
  }

  @override
  String get aiWorkNone => 'nothing found';

  @override
  String get aiWorkFailed => 'failed';

  @override
  String get aiWorkRunning => 'running';

  @override
  String get aiWorkRaw => 'Raw output';

  @override
  String aiStepsStatus(String status, int count) {
    return '$status ($count steps)';
  }

  @override
  String get aiRetry => 'Retry';

  @override
  String get aiCancel => 'Cancel';

  @override
  String get aiSend => 'Send';

  @override
  String get aiInputPlaceholder => 'Enter lore query or claim...';

  @override
  String get aiSettingsRequired =>
      'Please configure your Chat API Key in settings first to use AI features.';

  @override
  String get aiSettingsGoTo => 'Go to Settings';

  @override
  String get aiClearHistory => 'Clear Chat';

  @override
  String get aiClearHistoryConfirm =>
      'Are you sure you want to clear the chat history for this tab?';

  @override
  String get aiClearConfirmBtn => 'Clear';

  @override
  String get aiNewConversation => 'New conversation';

  @override
  String get aiHistoryTitle => 'Chat History';

  @override
  String get aiHistoryEmpty =>
      'No conversations yet. Messages are saved to the on-device chat_sessions folder automatically.';

  @override
  String get aiHistoryContinue => 'Continue';

  @override
  String get aiHistoryView => 'View';

  @override
  String get aiHistoryDelete => 'Delete';

  @override
  String get aiHistoryDeleteConfirm =>
      'Delete this conversation? This cannot be undone.';

  @override
  String get aiHistoryCorrupt => 'Corrupt session file';

  @override
  String aiHistoryTurns(int count) {
    return '$count turns';
  }

  @override
  String get settingsAppIcon => 'App icon';

  @override
  String get settingsIconLightLabel => 'Light icon';

  @override
  String get settingsIconDarkLabel => 'Dark icon';

  @override
  String get settingsIconLightShort => 'LIGHT';

  @override
  String get settingsIconDarkShort => 'DARK';

  @override
  String get settingsIconUnsupported =>
      'Runtime icon switching is not supported on this platform. Settings were saved.';

  @override
  String get settingsWikiSources => 'Wiki Sources';

  @override
  String get settingsWikiSourcesDesc =>
      'Edit built-in Wiki URLs or add custom Wiki entries.';

  @override
  String get wikiSourcesAddTitle => 'Add Wiki';

  @override
  String get wikiSourcesEditTitle => 'Edit Wiki';

  @override
  String get wikiSourcesNameLabel => 'Name';

  @override
  String get wikiSourcesIconUrlLabel => 'Icon URL (optional)';

  @override
  String get wikiSourcesEndfieldPreset => 'Endfield Wiki presets';

  @override
  String get wikiSourcesReset => 'Reset';

  @override
  String get wikiSourcesEdit => 'Edit';

  @override
  String get wikiSourcesDelete => 'Delete';

  @override
  String get wikiSourcesCancel => 'Cancel';

  @override
  String get wikiSourcesSave => 'Save';

  @override
  String get wikiSourcesNameRequired => 'Please enter a Wiki name.';

  @override
  String get wikiSourcesUrlRequired => 'Please enter a valid URL.';

  @override
  String get kbStructuredTitle => 'GameData structured knowledge base';

  @override
  String get kbScopeDescription =>
      'The AI uses only the Chinese GameData knowledge base as evidence: entities, aliases, raw records, story text and search indexes, plus optional story vectors. Wiki pages and imported materials are not used as evidence.';

  @override
  String kbStatusError(String error) {
    return 'Failed to read GameData status: $error';
  }

  @override
  String get kbInstalled => 'GameData main knowledge base installed';

  @override
  String get kbNoAssetUrl =>
      'This build has no GameData release asset URL configured';

  @override
  String get kbErrorInvalidUrl =>
      'Could not resolve the download URL. On a real device, make sure the phone can reach this GitHub / LAN URL.';

  @override
  String kbConnecting(int attempt) {
    return 'Connecting to the server… (attempt $attempt)';
  }

  @override
  String get kbVerifying => 'Checking the file…';

  @override
  String get kbInstalling =>
      'Unzipping and installing, about a minute or two. Please do not quit…';

  @override
  String get kbCancelDownload => 'Cancel';

  @override
  String kbManualHint(String dir) {
    return 'If the network cannot reach the server: download arklores_gamedata_zh.db.gz from the Release on another network, rename it to arklores_gamedata_zh.db.download.gz, put it in $dir, then tap Download.';
  }

  @override
  String get kbErrorTimeout =>
      'Connection timed out. Check the network and try again; the downloaded part is kept.';

  @override
  String get kbErrorNetwork =>
      'The connection was interrupted (unstable network or GitHub temporarily unreachable). It was retried several times; the downloaded part is kept, and tapping Update resumes from there.';

  @override
  String get kbErrorNotFound =>
      'The knowledge base file was not found on the server (the new version may not be public yet). Please try again later.';

  @override
  String get kbErrorChecksum =>
      'GameData DB checksum failed. The file may be corrupted or the SHA256 does not match the build parameters.';

  @override
  String kbDownloadFailed(String error) {
    return 'Failed to download the GameData main knowledge base: $error';
  }

  @override
  String get kbNotInstalled => 'Not installed';

  @override
  String get kbDevAssetHint =>
      'Download the published knowledge base (it is unpacked after download; keep about 1 GB of free space).';

  @override
  String get kbUpdateAvailable =>
      'A newer official knowledge base is available. Tap Update to download it (keep about 1 GB of free space).';

  @override
  String get kbDownloading => 'Downloading';

  @override
  String get kbDownload => 'Download';

  @override
  String get kbStatEntities => 'Entities';

  @override
  String get kbStatRecords => 'Raw records';

  @override
  String get kbStatChunks => 'Document chunks';

  @override
  String get kbStatSourceCommit => 'Source commit';

  @override
  String get kbBuildSectionTitle => 'Build from source repo';

  @override
  String get kbBuildSectionDesc =>
      'Pull the latest unpacked data from Kengxxiao/ArknightsGameData and build or incrementally update the knowledge base on this device. Requires network; ~1.5–2 GB free space for the first build.';

  @override
  String get kbBuildLatestCommit => 'Latest commit';

  @override
  String get kbBuildInstalledCommit => 'Installed commit';

  @override
  String get kbBuildCheckUpdates => 'Check for updates';

  @override
  String get kbBuildFromSource => 'Build from source';

  @override
  String get kbBuildCancel => 'Cancel';

  @override
  String get kbBuildChecking => 'Checking upstream commits…';

  @override
  String get kbBuildDownloadingZip =>
      'Downloading source bundle (first time, large)…';

  @override
  String get kbBuildDownloadingChanges => 'Downloading incremental changes…';

  @override
  String get kbBuildExtracting => 'Extracting and filtering source data…';

  @override
  String get kbBuildSwapping => 'Replacing the knowledge base…';

  @override
  String get kbBuildStageStart => 'Preparing build';

  @override
  String get kbBuildStageCopy => 'Copying existing database';

  @override
  String get kbBuildStageIncremental => 'Applying incremental changes';

  @override
  String get kbBuildStageProfiles => 'Importing character profiles';

  @override
  String get kbBuildStageVoices => 'Importing voices';

  @override
  String get kbBuildStageStructured => 'Importing structured tables';

  @override
  String get kbBuildStageStories => 'Importing stories';

  @override
  String get kbBuildStageCoverage => 'Building entity coverage layer';

  @override
  String get kbBuildStageCoverageSpeakers => 'Expanding speaker entities…';

  @override
  String get kbBuildStageCoverageTrie => 'Building entity index…';

  @override
  String get kbBuildStageCoverageScan => 'Scanning character appearances…';

  @override
  String get kbBuildStageCoverageRare => 'Counting rare terms…';

  @override
  String get kbBuildStageCoverageProfiles => 'Writing chapter profiles…';

  @override
  String get kbBuildStageFts => 'Rebuilding full-text indexes';

  @override
  String get kbBuildIncrementalDone =>
      'Incremental update complete; the knowledge base has been replaced.';

  @override
  String get kbBuildFullDone =>
      'Full build complete; the knowledge base has been replaced.';

  @override
  String get kbBuildError => 'Build failed';

  @override
  String get kbBuildTokenTitle => 'GitHub token (optional)';

  @override
  String get kbBuildTokenDesc =>
      'Enter a GitHub Personal Access Token (ghp_… or github_pat_…) to raise the API quota from 60 to 5000 requests/hour and avoid rate-limit failures on shared proxy egress IPs. The token is stored in OS secure storage and never logged.';

  @override
  String get kbBuildTokenPlaceholder => 'Paste GitHub token';

  @override
  String get kbBuildTokenSave => 'Save';

  @override
  String get kbBuildTokenSaved => 'GitHub token saved.';

  @override
  String get kbBuildTokenCleared => 'GitHub token cleared.';

  @override
  String get kbBuildTokenSetHint => 'GitHub token set (quota 5000/hr)';

  @override
  String get materialsPausedTitle => 'User material import is not enabled yet';

  @override
  String get materialsPausedDesc =>
      'The legacy PDF/TXT import pipeline is paused. The AI currently uses only the GameData knowledge base as evidence.';

  @override
  String get wikiLoadFailed => 'Wiki page failed to load';

  @override
  String get wikiRetry => 'Retry';

  @override
  String get wikiErrorDns =>
      'Could not resolve the Wiki domain. Check your network, DNS, or proxy and retry.';

  @override
  String get wikiErrorTimeout =>
      'Connection timed out. Switch networks or check that your proxy/VPN is connected, then retry.';

  @override
  String get wikiErrorOffline =>
      'The device currently has no network connection.';

  @override
  String kbBuildChangeSummary(int stories, int tables, int levels) {
    return 'Upstream has updates: $stories story files, $tables data tables, $levels level files.';
  }

  @override
  String get kbBuildNoChanges =>
      'Nothing upstream concerns the knowledge base; no update needed.';

  @override
  String get kbBuildTooManyChanges =>
      'Too much changed upstream to apply file by file; Build will rebuild completely instead (about 170 MB to download, takes a while).';

  @override
  String get kbBuildDownloadingContext =>
      'Downloading the data tables the update needs…';

  @override
  String get kbBuildReportTitle => 'What this update changed';

  @override
  String kbBuildReportStories(int added, int changed, int removed) {
    return 'Story files: $added added, $changed changed, $removed removed';
  }

  @override
  String kbBuildReportEntries(String text) {
    return 'Entries: $text';
  }

  @override
  String kbBuildReportNew(String names) {
    return 'New collections: $names';
  }

  @override
  String kbBuildReportVectors(int count) {
    return '$count vectors became invalid because their story changed; you can add them below under Story vectors.';
  }

  @override
  String get kbVectorTitle => 'Story vectors (semantic search)';

  @override
  String get kbVectorDesc =>
      'Vectors let story search match by meaning, not only by exact words. Everything works without them; those stories just get keyword search only. Vectors only locate; the evidence of an answer is still the original text.';

  @override
  String kbVectorStatus(int vectors, int stories) {
    return '$vectors vectors covering $stories stories';
  }

  @override
  String get kbVectorNone => 'No vectors yet';

  @override
  String kbVectorPending(int stories, int chunks, String tokens) {
    return 'To generate: $stories stories, about $chunks chunks, about $tokens×10k tokens';
  }

  @override
  String kbVectorCost(String yuan) {
    return 'About ¥$yuan at Bailian\'s price (an estimate only; your provider\'s bill decides, and other providers charge differently: convert from the token count)';
  }

  @override
  String get kbVectorUpToDate => 'Every story has vectors; nothing to update.';

  @override
  String get kbVectorFirstBuild =>
      'This generates vectors for all stories, which costs and takes far more than an incremental update.';

  @override
  String kbVectorConfigure(String model, int dims) {
    return 'Configure the vector service first: Settings → API settings → Vectors (default Bailian $model, $dims dimensions, needs that service\'s API key).';
  }

  @override
  String kbVectorMismatch(String have, String want) {
    return 'Existing vectors come from $have, the configuration says $want. They cannot be mixed: set the vector settings back to $have.';
  }

  @override
  String get kbVectorStart => 'Generate vectors';

  @override
  String get kbVectorRefresh => 'Recalculate';

  @override
  String kbVectorRunning(int done, int total, int chunks) {
    return 'Generating vectors: $done / $total stories ($chunks chunks)';
  }

  @override
  String kbVectorDone(int chunks, int tokens) {
    return 'Generated $chunks chunks; the provider counted $tokens tokens.';
  }

  @override
  String get kbVectorCancel => 'Stop';

  @override
  String get kbVectorConfirmTitle => 'Generate vectors for all stories?';

  @override
  String kbVectorConfirmBody(int stories, int chunks, String tokens) {
    return 'About $stories stories, $chunks chunks, $tokens×10k tokens. This costs money at your vector service. You can stop any time; finished stories are kept.';
  }

  @override
  String get kbVectorConfirm => 'Start';

  @override
  String get lineKindSubtitle => 'Caption';

  @override
  String get lineKindDocument => 'Document';

  @override
  String get lineKindChoice => 'Choice';

  @override
  String get lineKindTitle => 'Title';

  @override
  String get lineKindTutorial => 'Tutorial';

  @override
  String get aiAnswerOptions => 'Answer options';

  @override
  String get aiAnswerReview => 'Review';

  @override
  String get aiAnswerReviewHint =>
      'Another model reads the draft and raises questions, checked in the text before the final answer (slower)';

  @override
  String get aiAnswerDigest => 'Digest';

  @override
  String get aiAnswerDigestHint =>
      'Long answers open with a few summary paragraphs, the details folded below (one more call)';

  @override
  String librarySearchIn(String name) {
    return 'In “$name”';
  }

  @override
  String get librarySearchEverywhere => 'Search the whole library';

  @override
  String librarySearchNoNameMatch(String query) {
    return 'Nothing is named “$query”; below are close names and texts that contain it';
  }

  @override
  String get librarySearchSimilar => 'Close names';

  @override
  String get librarySearchMentions => 'In the text';

  @override
  String get librarySearchNoMentions => 'Not found in the texts';

  @override
  String librarySearchInText(String query) {
    return 'Search the texts for “$query”';
  }

  @override
  String get librarySearchSemantic => 'Find stories by meaning';

  @override
  String get librarySearchSemanticTitle => 'Stories close in meaning';

  @override
  String get librarySearchSemanticNeedsService =>
      'Set up an embedding service to find stories by meaning (Settings → API settings → Embedding)';

  @override
  String get librarySearchSemanticNoVectors =>
      'This knowledge base has no story vectors (they can be made on the knowledge base page)';

  @override
  String get librarySearchSemanticOtherModel =>
      'The knowledge base’s vectors were made with another embedding model than the one configured';

  @override
  String get librarySearchSemanticFailed =>
      'The embedding service request failed';

  @override
  String librarySearchMatchCount(int n) {
    return '$n matches';
  }

  @override
  String librarySearchFurther(String query) {
    return 'Search for “$query” (close names and texts too)';
  }

  @override
  String get storyReaderFindHint => 'Find in this story';

  @override
  String get gameArknights => 'Arknights';

  @override
  String get gameEndfield => 'Endfield';

  @override
  String libraryGameMissing(String game) {
    return '$game knowledge base not installed';
  }

  @override
  String get kbEndfieldTitle => 'Endfield knowledge base';

  @override
  String get kbEndfieldDescription =>
      'Story and texts of Arknights: Endfield (unpacked from the game client; a separate file, downloaded apart from the Arknights one). Once installed, the library shows Endfield\'s shelves and answers look in one or both games.';
}

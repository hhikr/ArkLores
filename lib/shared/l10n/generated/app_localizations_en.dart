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
  String get apiSettingsChatDesc =>
      'Used for AI conversations (Fact Check, Summary, Roleplay).';

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
      'Import PDF or TXT files to build your personal lore reference library.';

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
  String get aiChatTitle => 'Lore Advisor';

  @override
  String get aiChatSubtitle => 'Fact Check · Summary · Roleplay';

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
      'Your AI-enhanced companion for exploring Arknights and Endfield lore.\n\n• Browse PRTS & Endfield Wikis\n• AI-powered fact checking & summaries\n• Import your lore books\n• Immersive character roleplay';

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
  String get settingsVersionLabel => 'ARKLORES / 0.9 DEVELOPMENT';

  @override
  String get settingsShowOnboarding => 'Show Onboarding Guide';

  @override
  String get settingsShowOnboardingDesc =>
      'Replay the first-launch guide to configure the app';

  @override
  String get aiTabAsk => 'Ask AI';

  @override
  String get aiModeAuto => 'Auto';

  @override
  String get aiModeAutoDesc =>
      'AI picks the best mode (summarize / verify / investigate)';

  @override
  String get aiModeSummarize => 'Summarize';

  @override
  String get aiModeSummarizeDesc =>
      'Summarize known lore: characters, events, factions, timeline';

  @override
  String get aiModeVerify => 'Verify';

  @override
  String get aiModeVerifyDesc =>
      'Judge whether a claim is true (supported / refuted)';

  @override
  String get aiModeInvestigate => 'Investigate';

  @override
  String get aiModeInvestigateDesc =>
      'Cross-chapter reasoning: culprit, cause, foreshadowing, truth';

  @override
  String get aiAskSource =>
      'Answers are grounded in installed GameData story text only';

  @override
  String get aiAskEmpty =>
      'Ask any lore question — summarize, verify, or dig deeper; auto mode picks the approach for you.';

  @override
  String get aiAskInputPlaceholder => 'Ask any lore question...';

  @override
  String get aiAskSuggestionAmiya => 'Who is Amiya?';

  @override
  String get aiAskSuggestionVerify =>
      'Is Amiya the public leader of Rhodes Island?';

  @override
  String get aiAskSuggestionInvestigate => 'What happened to Miogre\'s death?';

  @override
  String get aiAskError => 'Failed to answer. Please retry.';

  @override
  String get aiAskCanceled => 'Answer canceled.';

  @override
  String get aiTabFactCheck => 'Fact Check';

  @override
  String get aiTabSummary => 'Summary';

  @override
  String get aiTabInvestigation => 'Investigation';

  @override
  String get aiTabRoleplay => 'Roleplay';

  @override
  String get aiInvestigationSource =>
      'Investigation scope: installed GameData story text only (appearance enumeration + line-level reading + cross-chapter echoes)';

  @override
  String get aiInvestigationEmpty =>
      'Ask a cross-chapter causality or culprit question. The investigation enumerates appearances, reads key chapters, locates cross-chapter details, and compares evidence per suspect before concluding with an evidence chain.';

  @override
  String get aiInvestigationInputPlaceholder =>
      'e.g. Who is responsible for a character\'s death...';

  @override
  String get aiInvestigationSuggestionDeath =>
      'What is the truth behind Theresis\'s death';

  @override
  String get aiInvestigationSuggestionWeapon =>
      'Key weapon clues in a death scene';

  @override
  String get aiInvestigationVerdict => 'Investigation verdict';

  @override
  String get aiInvestigationConfidence => 'Confidence';

  @override
  String get aiInvestigationBasis => 'Basis';

  @override
  String get aiInvestigationEvidenceChain => 'Evidence chain references';

  @override
  String get aiInvestigationCoverage => 'Coverage';

  @override
  String get aiInvestigationRead => 'read';

  @override
  String get aiInvestigationMapped => 'mapped';

  @override
  String get aiInvestigationSkipped => 'skipped';

  @override
  String get aiInvestigationError => 'Investigation failed. Please retry.';

  @override
  String get aiFactCheckSource => 'Evidence: installed Chinese GameData only';

  @override
  String get aiFactCheckEmpty =>
      'Enter a lore claim to check it against local GameData evidence.';

  @override
  String get aiFactCheckInputPlaceholder => 'Enter a claim to verify...';

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
  String get aiSummaryInputPlaceholder =>
      'Enter character, event, location or faction to summarize...';

  @override
  String get aiSummarySource => 'Evidence: installed Chinese GameData only';

  @override
  String get aiSummaryEmpty =>
      'Enter an Arknights character, event, location, or faction to summarize from local GameData evidence.';

  @override
  String get aiSummarySuggestionAmiya => 'Amiya';

  @override
  String get aiSummarySuggestionKaltsit => 'Kal\'tsit';

  @override
  String get aiSummarySuggestionRhine => 'Rhine Lab';

  @override
  String get aiSummarySuggestionChernobog => 'Chernobog Incident';

  @override
  String get aiSummaryError => 'Summary generation failed. Please retry.';

  @override
  String get aiSummaryCanceled => 'Summary generation canceled.';

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
  String get aiRoleplayChoose => 'Choose a character';

  @override
  String get aiRoleplayChooseDesc =>
      'The character is resolved to a stable GameData entity before dialogue begins.';

  @override
  String get aiRoleplayCharacter => 'Character name or alias';

  @override
  String get aiRoleplayScene => 'Scene (optional)';

  @override
  String get aiRoleplaySceneContext =>
      'The scene is session context, not GameData evidence';

  @override
  String get aiRoleplayStart => 'Resolve character and start';

  @override
  String get aiRoleplayResolving => 'Resolving…';

  @override
  String get aiRoleplayNoDatabase =>
      'The Chinese GameData knowledge base is not installed. Install it in Settings first.';

  @override
  String get aiRoleplayNotFound =>
      'No matching character was found in GameData. Check the name or alias.';

  @override
  String get aiRoleplayDisambiguate => 'Choose the matching GameData entity';

  @override
  String get aiRoleplayContinue => 'Continue saved local session';

  @override
  String get aiRoleplayRestart => 'Restart';

  @override
  String get aiRoleplayGeneratedNotice =>
      'Character facts use retrieved GameData. Dialogue and stage directions are AI-generated, not official game lines.';

  @override
  String get aiRoleplayEmpty =>
      'Send the first message. The first turn retrieves profiles, voices, operator records, modules, and related mission stories.';

  @override
  String get aiRoleplayInputPlaceholder => 'Talk to the character…';

  @override
  String get aiRoleplayError => 'Generation failed. Please retry.';

  @override
  String get aiRoleplayCanceled => 'Generation canceled.';

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
  String get kbErrorTimeout =>
      'Connection timed out. Switch networks, or make sure the temporary HTTP server and the phone are on the same network.';

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
}

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

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
  String get settingsProfileSectionsOpen => 'Open file sections in the library';

  @override
  String get settingsProfileSectionsOpenDesc =>
      'Show every section of an operator\'s file unfolded when opening its page; when off, all start folded and open on tap. Story synopses always start folded.';

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
  String get kbUpdate => 'Update';

  @override
  String get kbUpToDate => 'Up to date';

  @override
  String get kbRedownload => 'Download again';

  @override
  String get kbRedownloadTitle => 'Download the knowledge base again?';

  @override
  String get kbRedownloadBody =>
      'You already have the latest version. Downloading again fetches about 115 MB and rebuilds the database (about 1 GB of free space needed). It is rarely necessary.';

  @override
  String get kbRedownloadConfirm => 'Download again';

  @override
  String get kbCancel => 'Cancel';

  @override
  String get materialsTitle => 'Materials';

  @override
  String get materialsEmptyDesc =>
      'Keep texts here: lore excerpts, notes, research. They stay on this device and never enter the knowledge base.';

  @override
  String get materialsCancel => 'Cancel';

  @override
  String get materialsSave => 'Save';

  @override
  String get materialsDeleteConfirm => 'Delete this text?';

  @override
  String get materialsDelete => 'Delete';

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
      'Ask uses your own model service: requests go from this phone straight to the provider, with no ArkLores server in between. What you filled in before is read in; unchanged, just go on.';

  @override
  String get onboardingSaveContinue => 'Save & Continue';

  @override
  String get onboardingConfigureLater => 'Configure later';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingSkipGuide => 'Skip the guide';

  @override
  String get onboardingAppearanceTitle => 'Appearance';

  @override
  String get onboardingAppearanceDesc =>
      'The theme and the reading font; both can be changed in Settings later.';

  @override
  String get onboardingProfileDesc =>
      'How the stories address you is replaced with this name.';

  @override
  String get onboardingEmbeddingDesc =>
      'The vector service finds story text by meaning. It can be left empty, but answers will be much worse.';

  @override
  String get onboardingKbTitle => 'Knowledge bases';

  @override
  String get onboardingKbDesc =>
      'The story text and the game records are in the knowledge bases, which reading and Ask both use. One per game, usable offline once downloaded; those already downloaded say so.';

  @override
  String get onboardingWikiTitle => 'Wiki sites';

  @override
  String get onboardingWikiDesc =>
      'The Wiki tab shows these sites, and Ask looks things up in them. Their addresses can be changed and other sites added.';

  @override
  String get onboardingBackgroundTitle => 'Running in the background';

  @override
  String get onboardingDoneTitle => 'All Set!';

  @override
  String get onboardingDoneDesc =>
      'Everything can be changed again in Settings, where this guide can also be opened again.';

  @override
  String get onboardingStartExploring => 'Start Exploring';

  @override
  String get backgroundAccessTitle => 'Keep answering in the background';

  @override
  String get backgroundAccessBody =>
      'ArkLores has no server of its own: calling the model, searching the knowledge base and writing the answer all happen on this phone, and an answer takes minutes. Once you switch to another app, some systems (ColorOS, for one) freeze the app within seconds, its connections drop, and the answer stops.\n\nExempt from battery optimisation, ArkLores runs in the background only while such work goes on (an answer, a download; the notification shows it), and stops when it is done.';

  @override
  String get backgroundAccessAllow => 'Allow';

  @override
  String get backgroundAccessNotifications => 'Notifications';

  @override
  String get backgroundAccessNotificationsDesc =>
      'Shows the progress of background work.';

  @override
  String get backgroundAccessBattery =>
      'Not restricted by battery optimisation';

  @override
  String get backgroundAccessBatteryDesc =>
      'Answers and downloads are not frozen when you switch apps.';

  @override
  String get backgroundAccessGranted => 'Allowed';

  @override
  String get backgroundAccessGrant => 'Allow';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsKnowledgeCategory => 'Knowledge & Library';

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
  String get settingsUpdate => 'Updates';

  @override
  String get settingsUpdateDesc =>
      'Check for a new version and update in the app';

  @override
  String updateVersionBuild(String version, int build) {
    return '$version (build $build)';
  }

  @override
  String get updateAutoCheck => 'Check automatically';

  @override
  String get updateAutoCheckDesc =>
      'Checks when the app opens, at most once a day. It only tells you; nothing is downloaded.';

  @override
  String get updateCheck => 'Check for updates';

  @override
  String get updateChecking => 'Checking.';

  @override
  String get updateUpToDate => 'You have the latest version.';

  @override
  String updateAvailable(String version) {
    return 'New version $version';
  }

  @override
  String updateAvailableSize(String size) {
    return 'Package: $size.';
  }

  @override
  String get updateDownloadInstall => 'Download and install';

  @override
  String updateDownloading(String received, String total) {
    return 'Downloading $received / $total';
  }

  @override
  String get updateVerifying => 'Checking the package.';

  @override
  String get updateCancel => 'Cancel';

  @override
  String get updateNeedsPermission =>
      'To install the update, allow ArkLores to install apps. Come back here afterwards and it continues.';

  @override
  String get updateAllow => 'Allow';

  @override
  String get updateReady =>
      'The installer is open. If the update was not installed, tap again.';

  @override
  String get updateInstall => 'Install';

  @override
  String get updateRetry => 'Retry';

  @override
  String get updateErrorCheck =>
      'Could not read the releases. Check the network and retry.';

  @override
  String get updateErrorDownload =>
      'The download did not finish. Retry continues it.';

  @override
  String get updateErrorChecksum =>
      'The package did not match its checksum and was deleted. Download it again.';

  @override
  String get updateErrorInstall => 'Could not open the installer.';

  @override
  String get updateUnsupported => 'Only the Android app can update itself.';

  @override
  String get updateSignatureNote =>
      'The update must have the same signature as the installed app. CI releases cannot replace a local debug-signed build.';

  @override
  String updateFound(String version) {
    return 'New version $version';
  }

  @override
  String get updateFoundOpen => 'View';

  @override
  String get updateNotification => 'Downloading the update';

  @override
  String get aiTabAsk => 'Ask AI';

  @override
  String get aiAskSource =>
      'Searches the story text of both installed games, and the wikis when \"Wiki\" is on; every point of an answer has a source';

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
    return 'Details / $count points';
  }

  @override
  String aiEvidenceSummary(int count, int stories) {
    return '$count citations / $stories stories';
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
  String get aiStoryReaderEnd => 'End of chapter';

  @override
  String get libraryTabMine => 'References';

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
  String get libraryFilterHint => 'Filter this list';

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
    return 'Continue / line $line';
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
    return '$calls lookups / $reads stories read';
  }

  @override
  String aiWorkHits(int hits, int stories) {
    return '$hits hits / $stories stories';
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
  String get aiWorkPlanned => 'planned';

  @override
  String get aiWorkInContext => 'already above';

  @override
  String get aiWorkNotRun => 'not run';

  @override
  String get aiWorkWikiDown => 'wiki timed out';

  @override
  String aiWorkChars(int count) {
    return '$count chars';
  }

  @override
  String aiWorkRecord(String text) {
    return 'Record: $text';
  }

  @override
  String aiWorkHelper(int number) {
    return 'Helper $number';
  }

  @override
  String aiWorkStories(int count) {
    return '$count stories';
  }

  @override
  String aiWorkGathered(int given, int located) {
    return '$given of $located stories';
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
  String get aiConversations => 'Conversations';

  @override
  String get aiConversationsAnswering => 'Answering';

  @override
  String aiConversationsAnsweringCount(int count) {
    return '$count answering';
  }

  @override
  String get aiConversationsRecent => 'Recent';

  @override
  String get aiConversationsAll => 'See all';

  @override
  String get aiConversationsNone =>
      'No conversations yet. They appear here once you ask.';

  @override
  String get aiNewConversation => 'New conversation';

  @override
  String get aiHistoryTitle => 'Chat History';

  @override
  String get aiHistoryEmpty =>
      'No conversations yet. They are saved to the on-device chat_sessions folder as you ask; tap one to go on with it.';

  @override
  String get aiHistoryCurrent => 'Current';

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
  String get kbArknightsTitle => 'Arknights knowledge base';

  @override
  String kbCountLines(String count) {
    return '$count story lines';
  }

  @override
  String kbCountRecords(String count) {
    return '$count records';
  }

  @override
  String kbDataVersion(String commit) {
    return 'data version $commit';
  }

  @override
  String get kbLocalBuild => 'Updated here';

  @override
  String get kbLocalBuildNote =>
      'This knowledge base was updated on this device from the game data; it is newer than the official one published with the app.';

  @override
  String get kbBackToOfficial => 'Back to the official one';

  @override
  String get kbBackToOfficialTitle => 'Go back to the official knowledge base?';

  @override
  String get kbBackToOfficialBody =>
      'The official knowledge base published with the app (about 115 MB) is downloaded again and replaces the one updated on this device; the newer game content in it is lost.';

  @override
  String get kbEndfieldSourceNote =>
      'Endfield\'s data is unpacked from the game client and updated with the app\'s releases; it cannot be updated from game data on the device.';

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
  String kbManualHint(String file, String dir) {
    return 'If the network cannot reach the server: download $file.gz from the Release on another network, rename it to $file.download.gz, put it in $dir, then tap Download.';
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
  String get kbOriginOfficial => 'official release';

  @override
  String get kbOriginLocal => 'updated on this device';

  @override
  String kbUpdateNewerData(String commit) {
    return 'The official knowledge base ($commit) has newer game data than the one updated on this device. Tap “Update” to download it (keep about 1 GB free).';
  }

  @override
  String get kbUpdateSameData =>
      'The official knowledge base now has the same game data. Tap “Update” to switch to it (all vectors included; keep about 1 GB free).';

  @override
  String get kbBuildOfficialHasIt =>
      'The official knowledge base is already at this commit: use “Update” above.';

  @override
  String get kbDownloading => 'Downloading';

  @override
  String get kbDownload => 'Download';

  @override
  String get kbBuildSectionTitle => 'Update from game data';

  @override
  String get kbBuildSectionDesc =>
      'The official knowledge base is published with the app and may lag behind the game. This pulls the latest unpacked data from Kengxxiao/ArknightsGameData and brings the knowledge base on this device up to the game\'s latest content. Requires network.';

  @override
  String get kbBuildFullConfirm =>
      'This update can only be a complete rebuild: about 170 MB to download, a long build, 1.5–2 GB of free space; and the new database has no vectors — the existing ones are lost and must be generated again with your own embedding service (at a cost).';

  @override
  String get kbBuildFullConfirmButton => 'Rebuild completely anyway';

  @override
  String get kbBuildLatestCommit => 'Latest commit';

  @override
  String get kbBuildInstalledCommit => 'Installed commit';

  @override
  String get kbBuildCheckUpdates => 'Check for updates';

  @override
  String get kbBuildFromSource => 'Pull and update';

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
  String get kbBuildStageCompact => 'Removing data no longer used…';

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
    return '$count vectors became invalid because their story changed; you can add them above under Semantic search.';
  }

  @override
  String get kbVectorTitle => 'Semantic search (vectors)';

  @override
  String kbVectorSummary(int stories, int records) {
    return '$stories story vectors / $records record vectors';
  }

  @override
  String get kbVectorComplete => 'complete';

  @override
  String get kbVectorDesc =>
      'Vectors let search match stories and records (archives, voice lines, descriptions) by meaning, not only by exact words. Everything works without them; that text just gets keyword search only. Vectors only locate; the evidence of an answer is still the original text.';

  @override
  String kbVectorRecordStatus(int vectors) {
    return '$vectors record vectors';
  }

  @override
  String kbVectorPendingRecords(int chunks) {
    return 'Of which records (archives, voice lines, descriptions): $chunks chunks';
  }

  @override
  String kbVectorRunningRecords(int done, int total) {
    return 'Generating record vectors: $done / $total chunks';
  }

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
  String get kbVectorUpToDate =>
      'Every story and record has vectors; nothing to update.';

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
      'Another model reads this answer as a reader and raises questions; they are checked in the text and answered below (a few more calls)';

  @override
  String get aiReviewRequest => 'Review the answer above';

  @override
  String get aiAnswerDigest => 'Digest';

  @override
  String get aiAnswerDigestHint =>
      'Add a few summary paragraphs above this answer, the details folded below (one more call)';

  @override
  String get aiAnswerWiki => 'Wiki';

  @override
  String get aiAnswerWikiShort =>
      'Search PRTS / Warfarin online; cited as wiki';

  @override
  String get aiAnswerDelegate => 'Sub-agents';

  @override
  String get aiAnswerDelegateShort =>
      'Parallel search for wide questions; costs more';

  @override
  String get aiDeepThinkingShort =>
      'Think before answering: slower, more tokens';

  @override
  String get aiNoVectorWarning =>
      'No embedding service configured: keyword search only, answers will be markedly worse. Set one up in Settings.';

  @override
  String get aiCitedWiki => 'Wiki';

  @override
  String aiCitedWikiPages(int count) {
    return '$count wiki pages';
  }

  @override
  String aiCitationParagraph(int n) {
    return '¶$n';
  }

  @override
  String aiCitationParagraphs(int start, int end) {
    return '¶$start–$end';
  }

  @override
  String get aiWikiOpen => 'Open in Wiki';

  @override
  String aiWikiVersion(String site, String date) {
    return '$site / version read on $date';
  }

  @override
  String get aiWikiSecondary =>
      'Wikis are written by the community: a secondary source. Where they differ from the game text, the game text wins.';

  @override
  String get aiWikiPageUnavailable =>
      'This version of the page is not kept on this device (the question may have been asked elsewhere); open the current version in the Wiki.';

  @override
  String aiWorkWikiPages(int count) {
    return '$count pages';
  }

  @override
  String aiWorkParagraphs(int start, int end) {
    return '¶$start–$end';
  }

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
  String get storyReaderFindEmpty =>
      'Type a name or a word: the lines of this story that have it are listed here; tap one to go to it.';

  @override
  String get gameArknights => 'Arknights';

  @override
  String get gameEndfield => 'Endfield';

  @override
  String get launchTagline => 'Story reader and Q&A';

  @override
  String libraryGameMissing(String game) {
    return '$game knowledge base not installed';
  }

  @override
  String get kbEndfieldTitle => 'Endfield knowledge base';

  @override
  String get libraryFigureStories => 'Stories';

  @override
  String get libraryFigureCollections => 'Collections';

  @override
  String get libraryFigureEntries => 'Codex entries';

  @override
  String get libraryOpenKnowledgeBase => 'Open knowledge base';

  @override
  String get wikiTools => 'Page tools';

  @override
  String get wikiToolsClose => 'Close page tools';

  @override
  String get wikiZoomOut => 'Smaller text';

  @override
  String get wikiZoomIn => 'Larger text';

  @override
  String get wikiRefresh => 'Reload';

  @override
  String get wikiDarkPage => 'Dark page';

  @override
  String get wikiBookmarkAdd => 'Add bookmark';

  @override
  String get wikiBookmarkRemove => 'Remove bookmark';

  @override
  String get bookmarksRemoved => 'Bookmark removed';

  @override
  String get commonUndo => 'Undo';

  @override
  String get bookmarksDelete => 'Remove';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsThemeSystemShort => 'System';

  @override
  String get settingsThemeSystem => 'Light or dark, as the system is';

  @override
  String get settingsReadingFont => 'Reading font';

  @override
  String get settingsReadingFontDesc =>
      'The font of stories, files and answers';

  @override
  String get settingsReadingFontSans => 'Sans';

  @override
  String get settingsReadingFontKai => 'LXGW WenKai';

  @override
  String get apiSettingsShowKey => 'Show key';

  @override
  String get apiSettingsHideKey => 'Hide key';

  @override
  String get wikiSourcesResetConfirm =>
      'The sites go back to the built-in list; added sites are removed.';

  @override
  String get aiConfigRequiredTitle => 'Set up the chat service first';

  @override
  String get aiAskTry => 'Try asking';

  @override
  String get settingsContextWarnTokens => 'Context warning threshold';

  @override
  String get settingsContextWarnTokensDesc =>
      'Warn when a conversation exceeds this value.';

  @override
  String get settingsCompactPercent => 'Auto-compaction point';

  @override
  String get settingsCompactPercentDesc =>
      'When the context reaches this share of the warning threshold, earlier content is compacted into notes.';

  @override
  String get settingsSkipOperatorNames =>
      'Leave operator names plain in answers';

  @override
  String get settingsSkipOperatorNamesDesc =>
      'When on, operators\' names in answers are not underlined and do not open their portraits; other characters still do.';

  @override
  String aiContextMeter(String n, String limit) {
    return 'Context $n / $limit';
  }

  @override
  String aiContextNotice(String n, String limit) {
    return 'This conversation has exceeded the context warning threshold ($n / $limit). Longer context costs more per step and makes earlier content easier to miss. You can continue in a new conversation.';
  }

  @override
  String get aiContextWarningTitle => 'Context warning threshold exceeded';

  @override
  String aiContextWarningBody(String n, String limit) {
    return 'This conversation now has $n of context (warning threshold $limit). Longer context costs more per step and makes earlier content easier to miss. You can continue in a new conversation.';
  }

  @override
  String get aiContextNewChat => 'New conversation';

  @override
  String get aiContextStop => 'Stop answering';

  @override
  String get aiContextDismiss => 'Got it';

  @override
  String aiWorkCompaction(String from, String to, int count) {
    return 'Compact context / ≈ $from → $to / $count passages kept';
  }

  @override
  String get portraitPackMissing => 'No portrait pack installed.';

  @override
  String get portraitNotInPack => 'This portrait is not in the pack.';

  @override
  String get portraitBlank => 'The portrait for this line is blank.';

  @override
  String get portraitPackTitle => 'Story portraits';

  @override
  String get portraitPackOldIndex =>
      'The installed knowledge base has no portrait data yet. Update it before downloading the portrait pack.';

  @override
  String get portraitPackUnreleased =>
      'The portrait pack has not been released yet.';

  @override
  String portraitPackDescription(String size) {
    return 'View story portraits by tapping speakers in the reader or names in answers. About $size.';
  }

  @override
  String portraitPackInstalled(int count, String size) {
    return 'Installed: $count sprites, $size.';
  }

  @override
  String portraitPackUpdateAvailable(String size) {
    return 'A new portrait pack is available ($size).';
  }

  @override
  String get portraitPackDownload => 'Download portrait pack';

  @override
  String get portraitPackUpdate => 'Update';

  @override
  String get portraitPackDelete => 'Delete';

  @override
  String get portraitPackCancel => 'Cancel';

  @override
  String get portraitPackCredit =>
      'Portraits: Arkwaifu (CC BY-NC 4.0) / Hypergryph';

  @override
  String get portraitPackEndfield =>
      'Endfield stories have no portrait data yet.';

  @override
  String get portraitPackDeleteConfirm =>
      'Delete the downloaded portrait pack? You can download it again later.';

  @override
  String get portraitPackError =>
      'The portrait pack operation failed. Please retry.';

  @override
  String portraitPackProgress(String received, String total, String percent) {
    return '$received / $total ($percent%)';
  }

  @override
  String get portraitEyebrow => 'PORTRAIT';

  @override
  String portraitLines(int n) {
    return '$n lines';
  }

  @override
  String portraitStories(int n) {
    return '$n stories';
  }

  @override
  String portraitSprites(int n) {
    return '$n variants';
  }

  @override
  String portraitFaceBody(int face, int body) {
    return 'face $face / outfit $body';
  }

  @override
  String get portraitGroupSpeakers => 'Who else uses this portrait?';

  @override
  String get portraitSpeakerGroups => 'Other portraits of this character';

  @override
  String get portraitOperator => 'Operator file';

  @override
  String get portraitNoSprite => 'No portrait is shown for this line.';

  @override
  String portraitTapSpeaker(String name) {
    return 'Show portraits of “$name”';
  }

  @override
  String get portraitGroupPageTitle => 'Portrait speakers';

  @override
  String portraitSpeakerPageTitle(String name) {
    return 'Portraits of “$name”';
  }

  @override
  String portraitSpeakerCount(int n) {
    return '$n speakers';
  }

  @override
  String get portraitMore => 'More';

  @override
  String portraitStoryTitle(String name) {
    return 'Stories with $name';
  }

  @override
  String get portraitNoStories => 'No stories found.';
}

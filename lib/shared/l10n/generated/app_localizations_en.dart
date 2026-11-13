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
      'Sets the Doctor\'s name shown in the story text, as in Dr. xxx. Left empty, it is the default: Doctor.';

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
  String get settingsProfileSectionsOpen => 'Open file sections by default';

  @override
  String get settingsProfileSectionsOpenDesc =>
      'Whether the sections of a file, such as an operator\'s, start folded or open when its page opens.';

  @override
  String get settingsSkipUnreadOpens =>
      'Don\'t record stories that were only tapped';

  @override
  String get settingsSkipUnreadOpensDesc =>
      'A story opened and left without reading on from the line it opened at is not added to Recently read.';

  @override
  String get settingsSessionLogs => 'Save AI conversations';

  @override
  String get settingsSessionLogsDesc =>
      'Fully record every AI conversation to the chat_sessions folder in device storage, used by Chat History for viewing and restoring. When off, AI conversations are not recorded.';

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
      'Enables semantic story-line recall for investigations. The model\'s vectors must match those of the installed knowledge base (qwen3.7-text-embedding). Without a key only keyword search is used, and answers will be much worse.';

  @override
  String get apiSettingsLabelBaseUrl => 'URL';

  @override
  String get apiSettingsLabelApiKey => 'API KEY';

  @override
  String get apiSettingsLabelModel => 'MODEL';

  @override
  String get apiSettingsSave => 'Save Configuration';

  @override
  String get apiSettingsSaved => 'Saved';

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
      'You already have the latest version. Downloading again rebuilds the database (about 1 GB of free space needed). Unless something is wrong, it is rarely necessary.';

  @override
  String get kbRedownloadConfirm => 'Download again';

  @override
  String get kbCancel => 'Cancel';

  @override
  String get materialsCancel => 'Cancel';

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
      'An AI-enhanced reading and research tool for Arknights and Endfield lore fans.\n\n• Browse PRTS & Endfield Wikis\n• AI-assisted lore research, with sources from the original text\n• Read the stories and game records\n• A RAG knowledge base built from in-game data, so the sources are reliable';

  @override
  String get onboardingGetStarted => 'Get Started';

  @override
  String get onboardingApiTitle => 'Configure the Ask AI API';

  @override
  String get onboardingApiDesc =>
      'ArkLores has no server: looking things up in the records and wikis happens on your phone, and the model runs at the AI provider. To use the model, configure an API.';

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
  String get onboardingAppearanceDesc => 'Set the theme and the reading font.';

  @override
  String get onboardingProfileDesc =>
      'What should we call you, Doctor? This sets the Doctor\'s name in the stories and records.';

  @override
  String get onboardingEmbeddingDesc =>
      'The vector service builds the RAG knowledge base, for good AI answers and fuzzy search in the library. It can be left empty, but answers will be much worse.';

  @override
  String get onboardingKbTitle => 'Knowledge bases';

  @override
  String get onboardingKbDesc =>
      'Used for reading stories in the library and for Ask.';

  @override
  String get onboardingWikiTitle => 'Wiki sites';

  @override
  String get onboardingWikiDesc =>
      'The Wiki tab shows these sites, and Ask looks things up in them. Their addresses can be changed and other sites added.';

  @override
  String get onboardingPortraitsDesc =>
      'Character portraits, story CGs and dialogue backgrounds.';

  @override
  String get onboardingBackgroundTitle => 'Permissions';

  @override
  String get onboardingDoneTitle => 'All Set!';

  @override
  String get onboardingDoneDesc =>
      'Everything can be changed in Settings. You can go through this guide again under Help & guide.';

  @override
  String get onboardingStartExploring => 'Start Exploring';

  @override
  String get backgroundAccessTitle => 'Keep answering in the background';

  @override
  String get backgroundAccessBody =>
      'ArkLores has no server of its own: calling the model, searching the knowledge base and putting the answer together all happen on this phone, and one question takes at least a few minutes. After you switch to another app, some systems (ColorOS, for example) freeze background apps within seconds; the connection drops and the answer stops.\n\nOnce ArkLores is exempt from battery optimization, it keeps running in the background while answering or downloading a knowledge base (shown in the notification bar).';

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
      'Go through the first-launch guide and configuration again';

  @override
  String updateVersionBuild(String version, int build) {
    return '$version (build $build)';
  }

  @override
  String get updateAutoCheck => 'Check automatically';

  @override
  String get updateAutoCheckDesc =>
      'Checks for updates when the app opens, at most once a day. New versions are not downloaded automatically.';

  @override
  String get updateCheck => 'Check for updates';

  @override
  String get updateChecking => 'Checking…';

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
  String get updateVerifying => 'Checking the package…';

  @override
  String get updateCancel => 'Cancel';

  @override
  String get updateNeedsPermission =>
      'To install the update, allow ArkLores to install apps.';

  @override
  String get updateAllow => 'Allow';

  @override
  String get updateReady => 'The installer is open.';

  @override
  String get updateInstall => 'Install';

  @override
  String get updateRetry => 'Retry';

  @override
  String get updateErrorCheck =>
      'Could not read the update information. Check the network and retry.';

  @override
  String get updateErrorDownload =>
      'The download did not finish. Please retry.';

  @override
  String get updateErrorChecksum =>
      'The package content was wrong and has been deleted. Download it again.';

  @override
  String get updateErrorInstall => 'Could not open the installer.';

  @override
  String get updateUnsupported =>
      'Only the Android app can update itself in the app.';

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
      'Searches the records in the knowledge base; with \"Wiki\" on it may also look things up in the wikis.';

  @override
  String get aiAskEmpty =>
      'Ask anything you like. Judge for yourself whether an answer holds up, from the evidence it gives: it relies on the knowledge base and tends to look for what makes sense in the story rather than to think critically, so read it carefully.';

  @override
  String get aiInputExpand => 'Expand';

  @override
  String get aiInputCollapse => 'Collapse';

  @override
  String get aiInputFullscreen => 'Full screen';

  @override
  String get aiInputExitFullscreen => 'Exit full screen';

  @override
  String get aiAskInputPlaceholder => 'Ask anything…';

  @override
  String get aiAskSuggestionAmiya => 'Outline the history of Reunion';

  @override
  String get aiAskSuggestionVerify =>
      'Is SilverAsh the public leader of Kjerag?';

  @override
  String get aiAskSuggestionInvestigate => 'How did the Seaborn come to be?';

  @override
  String get aiAskError => 'Failed to answer. Please retry.';

  @override
  String get aiAskCanceled => 'Answer canceled.';

  @override
  String get aiAnswerStatusAnswered => 'Answered';

  @override
  String get aiAnswerStatusPartial => 'May be incomplete';

  @override
  String get aiAnswerStatusNotCovered => 'No source text found';

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
      'Download or build it under Settings → Knowledge base; the stories and texts to read appear here. With no knowledge base, or a very old one, building takes a long time.';

  @override
  String get libraryOldSchemaTitle => 'The knowledge base needs an update';

  @override
  String get libraryOldSchemaDesc =>
      'This knowledge base is ancient. Please update it!';

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
  String get libraryNoText => 'No text';

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
  String get materialsNew => 'New';

  @override
  String get materialsTitleHint => 'Title (optional)';

  @override
  String get materialsBodyHint => 'Text';

  @override
  String get materialsSave => 'Save';

  @override
  String get materialsDelete => 'Delete';

  @override
  String get materialsEdit => 'Edit';

  @override
  String get materialsDeleteConfirm => 'Delete this text?';

  @override
  String materialsChars(int n) {
    return '$n characters';
  }

  @override
  String get materialsDiscard => 'Discard unsaved changes?';

  @override
  String get materialsDiscardAction => 'Discard';

  @override
  String get materialsSaveFailed => 'Could not save. Try again.';

  @override
  String get materialsIntro =>
      'Choose the materials Ask may consult; they are searched together with the game texts and the wikis.';

  @override
  String get materialsImportFile => 'Import file';

  @override
  String get materialsPaste => 'Paste text';

  @override
  String get materialsImportEmpty =>
      'The file is empty. Choose one with text in it.';

  @override
  String get materialsImportUnreadable =>
      'Could not read the file. Choose a UTF-8 Markdown or text file.';

  @override
  String get materialsPasteEmpty => 'The clipboard holds no text to import.';

  @override
  String get materialsRetry => 'Retry';

  @override
  String get materialsIncluded => 'Included';

  @override
  String get materialsPersonal => 'Your own';

  @override
  String get materialsPersonalEmpty =>
      'Save a note or import a text, then choose whether Ask uses it.';

  @override
  String get materialsNewMaterial => 'New material';

  @override
  String get materialsIndexNotice =>
      'When one of your own materials is on, its text is sent to the configured embedding service to be indexed. Edits to a material that is on are indexed again by themselves; a choice applies from the next question.';

  @override
  String get materialsStateReady => 'Ready';

  @override
  String get materialsStateIndexing => 'Indexing';

  @override
  String get materialsStateFailed => 'Indexing failed';

  @override
  String get materialsStatePending => 'To update';

  @override
  String get materialsPolicy => 'Source notes';

  @override
  String get materialsRetryIndex => 'Index again';

  @override
  String get materialsCancelIndex => 'Stop indexing';

  @override
  String get materialsUntitled => 'Untitled';

  @override
  String get materialsUsed => 'Used by Ask';

  @override
  String get materialsUnused => 'Not used by Ask';

  @override
  String materialsUseSwitch(String title) {
    return 'Ask uses $title';
  }

  @override
  String get materialsReaderTitle => 'Material text';

  @override
  String get materialsReaderFailed => 'Could not read the material\'s text.';

  @override
  String get materialsReaderMissing =>
      'This version of the material\'s text is not here.';

  @override
  String get materialsCitedOnly =>
      'Only the paragraphs Ask cited of this material are shown.';

  @override
  String get materialsPolicyPresetFailed => 'Could not read the preset notes.';

  @override
  String get materialsPolicyHint =>
      'These notes help explain the material. They do not prove its text right and do not replace the search for what is relevant.';

  @override
  String get materialsPolicyKind => 'Kind of content';

  @override
  String get materialsPolicyText =>
      'Source, what the author knew, where it applies and its limits';

  @override
  String get materialsPolicyRestore => 'Restore the preset notes';

  @override
  String get readingHistoryTitle => 'Recently read';

  @override
  String get readingHistoryEmpty => 'Nothing read yet.';

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
  String get aiHistoryEmpty => 'No conversations yet.';

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
      'This knowledge base was updated on this device from the game data; it is newer than the last official one on this device.';

  @override
  String get kbBackToOfficial => 'Back to the official one';

  @override
  String get kbBackToOfficialTitle => 'Go back to the official knowledge base?';

  @override
  String get kbBackToOfficialBody =>
      'The official knowledge base published with the app is downloaded again and replaces the one updated on this device.';

  @override
  String get kbEndfieldSourceNote =>
      'There is no mature, regularly updated Endfield unpack, so the developer updates the Endfield knowledge base from time to time.';

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
  String get kbErrorTimeout =>
      'Connection timed out. Check the network and try again; the downloaded part is kept.';

  @override
  String get kbErrorNetwork =>
      'The connection was interrupted (unstable network or GitHub temporarily unreachable). It was retried several times; the downloaded part is kept, and tapping Update resumes from there.';

  @override
  String get kbErrorNotFound =>
      'The knowledge base file was not found on the server. Please try again later.';

  @override
  String get kbErrorChecksum =>
      'GameData DB checksum failed. The file may be corrupted.';

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
      'The knowledge base on GitHub checks for updates automatically every hour and may lag behind the game. This pulls the latest unpacked data from Kengxxiao/ArknightsGameData and brings the knowledge base on this device up to the game\'s latest content. Requires network.';

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
      'Enter a GitHub Personal Access Token (ghp_… or github_pat_…) to greatly raise how often the repository can be read. Without one, the knowledge base may fail to build.';

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
  String get wikiErrorTimeout => 'Connection timed out.';

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
  String get aiCitedMaterial => 'Material';

  @override
  String aiCitedMaterials(int count) {
    return '$count materials';
  }

  @override
  String get aiNameLinks => 'Name underlines';

  @override
  String get aiBlockNameQuestion => 'Stop underlining this name?';

  @override
  String get aiBlockNameDesc =>
      'Answers will leave it plain. You can undo this in Settings.';

  @override
  String get aiBlockNameConfirm => 'Stop';

  @override
  String get aiBlockNameCancel => 'Cancel';

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
  String libraryWordCount(String n) {
    return '$n characters';
  }

  @override
  String get librarySortTime => 'Time';

  @override
  String get librarySortWords => 'Length';

  @override
  String get collectionArtSpoilerTitle => 'May contain spoilers';

  @override
  String get collectionArtSpoilerBody =>
      'These pictures come from the stories and may give away what you have not read yet.';

  @override
  String get collectionArtSpoilerGo => 'Continue';

  @override
  String portraitOutfit(int n) {
    return 'Outfit $n';
  }

  @override
  String get portraitThumbsExpand => 'Show all thumbnails';

  @override
  String get portraitThumbsCollapse => 'Hide thumbnails';

  @override
  String get storyReaderContents => 'Contents';

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
  String get bookmarksOtherSite => 'A removed site';

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
  String get settingsTokenPrices => 'Answer cost';

  @override
  String get settingsTokenPricesDesc =>
      'Enter your model service\'s prices to see what each question cost under its answer.';

  @override
  String get settingsTokenPricesUnset => 'Not set';

  @override
  String get tokenPricesIntro =>
      'Enter the prices from your model service\'s price list, per million tokens, in any currency; the cost under answers uses the same unit. Leave them empty to show no cost. The cost is worked out with the prices as they are now, so changing them changes the cost of earlier answers too. Embedding requests cost too little and are not included.';

  @override
  String get tokenPricesInput => 'Input price (per million tokens)';

  @override
  String get tokenPricesOutput => 'Output price (per million tokens)';

  @override
  String get tokenPricesCached => 'Cached input (% of the input price)';

  @override
  String get tokenPricesCachedHint =>
      '20 means cached input costs 20% of the input price. Empty means 100%: no discount on cached input.';

  @override
  String get tokenPricesInvalid => 'Enter a number of 0 or more';

  @override
  String get tokenPricesCachedInvalid => 'Enter a number from 0 to 100';

  @override
  String get tokenPricesSaved => 'Saved';

  @override
  String get settingsSkipOperatorNames =>
      'Leave operator names plain in answers';

  @override
  String get settingsSkipOperatorNamesDesc =>
      'When on, operators\' names in answers are not underlined and do not open their portraits; other characters still do.';

  @override
  String get settingsNameLinks => 'Underline names';

  @override
  String get settingsNameLinksDesc =>
      'Names of characters with a portrait are underlined in answers and story lines, and open it. The Ask top bar and the reader\'s tools have this switch too.';

  @override
  String get settingsBlockedNames => 'Names left plain';

  @override
  String get settingsBlockedNamesDesc =>
      'These names are never underlined. Long-press an underlined name in an answer to add it.';

  @override
  String settingsBlockedNamesCount(int count) {
    return '$count';
  }

  @override
  String get blockedNamesHint => 'Name to leave plain';

  @override
  String get blockedNamesAdd => 'Add';

  @override
  String get blockedNamesEmpty =>
      'No names yet. Type one above, or long-press an underlined name in an answer.';

  @override
  String blockedNamesRemove(String name) {
    return 'Underline $name again';
  }

  @override
  String get blockedNamesDuplicate => 'This name is already on the list.';

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
  String get storyArtPackMissing => 'No story art pack installed.';

  @override
  String get portraitNotInPack => 'This portrait is not in the pack.';

  @override
  String get portraitBlank => 'The portrait for this line is blank.';

  @override
  String get storyArtPackTitle => 'Story art';

  @override
  String get storyArtPackOldIndex =>
      'The installed knowledge base has no portrait data yet. Update it before downloading the story art pack.';

  @override
  String storyArtPackDescription(String size) {
    return 'Download size: $size';
  }

  @override
  String storyArtPackInstalled(int count, int scenes, int cgs, String size) {
    return 'Portraits $count / Scenes $scenes / CG $cgs / $size';
  }

  @override
  String storyArtPackUpdateAvailable(String size) {
    return 'A new story art pack is available ($size).';
  }

  @override
  String get storyArtVariantStandard => 'Standard';

  @override
  String get storyArtVariantHd => 'HD';

  @override
  String get storyArtVariantStandardSpec =>
      'Portraits scaled to 800 pixels high, moderate quality, smaller.';

  @override
  String get storyArtVariantHdSpec =>
      'Portraits at their original size and every image at a higher quality, larger. Scenes and CGs are not large to begin with: mostly fewer compression marks.';

  @override
  String get storyArtVariantUnreleased =>
      'This version has not been released yet.';

  @override
  String get storyArtChannelUnreachable =>
      'Could not read what is released; GitHub may be out of reach.';

  @override
  String get storyArtRetry => 'Try again';

  @override
  String get kbCheckChannel => 'Check for knowledge base updates';

  @override
  String get storyArtVariantDownload => 'Download';

  @override
  String get storyArtInUse => 'In use';

  @override
  String get storyArtUseThis => 'Use this one';

  @override
  String get storyArtPackDownload => 'Download story art pack';

  @override
  String get storyArtPackUpdate => 'Update';

  @override
  String get storyArtPackDelete => 'Delete';

  @override
  String get storyArtPackCancel => 'Cancel';

  @override
  String get storyArtCredit => 'Images: Arkwaifu (CC BY-NC 4.0) / Hypergryph';

  @override
  String get storyArtPackEndfield => 'Endfield stories have no art data.';

  @override
  String get storyArtPackDeleteConfirm =>
      'Delete the downloaded story art pack? You can download it again later.';

  @override
  String get storyArtPackError =>
      'The story art pack operation failed. Please retry.';

  @override
  String storyArtPackProgress(String received, String total, String percent) {
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
  String portraitStoriesWith(String name) {
    return 'Stories where “$name” has this portrait';
  }

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
  String portraitPassingPortraits(int n) {
    return '$n more portraits used little';
  }

  @override
  String get portraitPassingHint =>
      'Too few lines; probably voices from off the stage';

  @override
  String portraitPassingSpeakers(int n) {
    return '$n more who appear little, their main portrait elsewhere';
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

  @override
  String get storyArtDescription =>
      'Portraits, backgrounds, CGs and close-ups from stories.';

  @override
  String get storyArtClose => 'Close';

  @override
  String get storyArtJump => 'Return to this point in the story';

  @override
  String get storyArtScene => 'Scene';

  @override
  String get storyArtTall => 'Tall image, tap to see all';

  @override
  String get storyArtNoScene => 'No scene has appeared yet';

  @override
  String get storyArtMissing => 'Image not in the story art pack.';

  @override
  String storyArtSceneSemantic(int number, int total) {
    return 'Scene $number of $total';
  }

  @override
  String storyArtCgSemantic(int number, int total, String title) {
    return 'CG $number of $total, $title';
  }

  @override
  String get portraitFullscreen => 'View portrait fullscreen';

  @override
  String get portraitTitle => 'Portrait';

  @override
  String get collectionArtTitle => 'Story art';

  @override
  String get settingsStoryArt => 'Story art';

  @override
  String get settingsStoryArtFolded => 'Folded';

  @override
  String get settingsStoryArtOpen => 'Open';

  @override
  String get settingsStoryArtFoldedDesc =>
      'The story art overview opens folded, so pictures do not spoil a story. A collection\'s art page and the reader always show them.';

  @override
  String get settingsStoryArtOpenDesc =>
      'The story art overview opens with everything shown. A collection\'s art page and the reader always show them.';

  @override
  String get settingsStoryArtNeedsPack => 'Requires the story art pack';

  @override
  String get artGalleryPortraits => 'Portraits';

  @override
  String get artGalleryBackgrounds => 'Backgrounds';

  @override
  String get artGallerySearch => 'Search people, pictures or collections';

  @override
  String get artGallerySearchClear => 'Clear the search';

  @override
  String get kbUpdateFoundTitle => 'Knowledge base update';

  @override
  String get kbUpdateFoundBody => 'New content can be downloaded:';

  @override
  String get kbUpdateFoundArknights => 'Arknights knowledge base';

  @override
  String get kbUpdateFoundEndfield => 'Endfield knowledge base';

  @override
  String kbUpdateFoundArt(String size) {
    return 'Story art pack ($size)';
  }

  @override
  String get kbUpdateFoundLater => 'Later';

  @override
  String get kbUpdateFoundOpen => 'Update';

  @override
  String get artGalleryEmpty => 'No matching images';

  @override
  String artGalleryCounts(int portraits, int backgrounds, int cgs) {
    return '$portraits portrait sets · $backgrounds backgrounds · $cgs CGs';
  }
}

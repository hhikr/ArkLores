import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'ArkLores'**
  String get appTitle;

  /// No description provided for @navWiki.
  ///
  /// In en, this message translates to:
  /// **'Wiki'**
  String get navWiki;

  /// No description provided for @navAI.
  ///
  /// In en, this message translates to:
  /// **'AI'**
  String get navAI;

  /// No description provided for @navMaterials.
  ///
  /// In en, this message translates to:
  /// **'Materials'**
  String get navMaterials;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSystemCode.
  ///
  /// In en, this message translates to:
  /// **'ARKLORES / SYSTEM'**
  String get settingsSystemCode;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsThemeArk.
  ///
  /// In en, this message translates to:
  /// **'Night mode'**
  String get settingsThemeArk;

  /// No description provided for @settingsThemeEndfield.
  ///
  /// In en, this message translates to:
  /// **'Day mode'**
  String get settingsThemeEndfield;

  /// No description provided for @settingsThemeArkShort.
  ///
  /// In en, this message translates to:
  /// **'NIGHT'**
  String get settingsThemeArkShort;

  /// No description provided for @settingsThemeEndfieldShort.
  ///
  /// In en, this message translates to:
  /// **'DAY'**
  String get settingsThemeEndfieldShort;

  /// No description provided for @localeEnglishShort.
  ///
  /// In en, this message translates to:
  /// **'EN'**
  String get localeEnglishShort;

  /// No description provided for @localeChineseShort.
  ///
  /// In en, this message translates to:
  /// **'中文'**
  String get localeChineseShort;

  /// No description provided for @settingsProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get settingsProfile;

  /// No description provided for @settingsProfileDesc.
  ///
  /// In en, this message translates to:
  /// **'How the stories address you.'**
  String get settingsProfileDesc;

  /// No description provided for @settingsProfileSectionCode.
  ///
  /// In en, this message translates to:
  /// **'PROFILE'**
  String get settingsProfileSectionCode;

  /// No description provided for @profileNicknameLabel.
  ///
  /// In en, this message translates to:
  /// **'Form of address'**
  String get profileNicknameLabel;

  /// No description provided for @profileNicknameHelp.
  ///
  /// In en, this message translates to:
  /// **'Stories write the Doctor\'s name as a placeholder; it is shown as what you enter here (left empty: \"Doctor\"). The knowledge base is not changed.'**
  String get profileNicknameHelp;

  /// No description provided for @profileNicknameDefault.
  ///
  /// In en, this message translates to:
  /// **'Doctor'**
  String get profileNicknameDefault;

  /// No description provided for @settingsAiServices.
  ///
  /// In en, this message translates to:
  /// **'AI Services'**
  String get settingsAiServices;

  /// No description provided for @settingsAiSectionCode.
  ///
  /// In en, this message translates to:
  /// **'AI SERVICE'**
  String get settingsAiSectionCode;

  /// No description provided for @settingsApiSettings.
  ///
  /// In en, this message translates to:
  /// **'API Settings'**
  String get settingsApiSettings;

  /// No description provided for @settingsApiSettingsDesc.
  ///
  /// In en, this message translates to:
  /// **'Configure the chat provider'**
  String get settingsApiSettingsDesc;

  /// No description provided for @settingsSessionLogs.
  ///
  /// In en, this message translates to:
  /// **'Save AI conversations'**
  String get settingsSessionLogs;

  /// No description provided for @settingsSessionLogsDesc.
  ///
  /// In en, this message translates to:
  /// **'Fully record every AI conversation (mode selection, auto-routing decision, complete reasoning and retrieved text) to the chat_sessions folder in device storage, used by Chat History for viewing and restoring. Stored on-device only; deletable in-app or from the file manager.'**
  String get settingsSessionLogsDesc;

  /// No description provided for @settingsKnowledgeBase.
  ///
  /// In en, this message translates to:
  /// **'Knowledge Base Management'**
  String get settingsKnowledgeBase;

  /// No description provided for @settingsKnowledgeSectionCode.
  ///
  /// In en, this message translates to:
  /// **'KNOWLEDGE BASE'**
  String get settingsKnowledgeSectionCode;

  /// No description provided for @settingsKnowledgeBaseDesc.
  ///
  /// In en, this message translates to:
  /// **'Manage GameData knowledge base'**
  String get settingsKnowledgeBaseDesc;

  /// No description provided for @apiSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'API Settings'**
  String get apiSettingsTitle;

  /// No description provided for @apiSettingsChatSection.
  ///
  /// In en, this message translates to:
  /// **'Chat API'**
  String get apiSettingsChatSection;

  /// No description provided for @apiSettingsChatDesc.
  ///
  /// In en, this message translates to:
  /// **'Used for Ask AI (story questions).'**
  String get apiSettingsChatDesc;

  /// No description provided for @apiSettingsEmbeddingSection.
  ///
  /// In en, this message translates to:
  /// **'Embedding API (optional)'**
  String get apiSettingsEmbeddingSection;

  /// No description provided for @apiSettingsEmbeddingDesc.
  ///
  /// In en, this message translates to:
  /// **'Enables semantic story-line recall for investigations. Must use the same model as the installed knowledge base vectors (e.g. Alibaba Cloud Bailian qwen3.7-text-embedding). Leave the key empty to use keyword search only.'**
  String get apiSettingsEmbeddingDesc;

  /// No description provided for @apiSettingsUseSameProvider.
  ///
  /// In en, this message translates to:
  /// **'Use same provider as Chat'**
  String get apiSettingsUseSameProvider;

  /// No description provided for @apiSettingsLabelBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get apiSettingsLabelBaseUrl;

  /// No description provided for @apiSettingsLabelApiKey.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get apiSettingsLabelApiKey;

  /// No description provided for @apiSettingsLabelModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get apiSettingsLabelModel;

  /// No description provided for @apiSettingsSave.
  ///
  /// In en, this message translates to:
  /// **'Save Configuration'**
  String get apiSettingsSave;

  /// No description provided for @apiSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'✓ Saved'**
  String get apiSettingsSaved;

  /// No description provided for @kbTitle.
  ///
  /// In en, this message translates to:
  /// **'Knowledge Base'**
  String get kbTitle;

  /// No description provided for @kbConfigWarning.
  ///
  /// In en, this message translates to:
  /// **'Please configure your API Key in Settings before building the knowledge base.'**
  String get kbConfigWarning;

  /// No description provided for @kbIndexOverview.
  ///
  /// In en, this message translates to:
  /// **'Index Overview'**
  String get kbIndexOverview;

  /// No description provided for @kbTotalChunks.
  ///
  /// In en, this message translates to:
  /// **'Total Chunks'**
  String get kbTotalChunks;

  /// No description provided for @kbWikiChunks.
  ///
  /// In en, this message translates to:
  /// **'Wiki Chunks'**
  String get kbWikiChunks;

  /// No description provided for @kbBookChunks.
  ///
  /// In en, this message translates to:
  /// **'Book Chunks'**
  String get kbBookChunks;

  /// No description provided for @kbBooks.
  ///
  /// In en, this message translates to:
  /// **'Books'**
  String get kbBooks;

  /// No description provided for @kbWikiSources.
  ///
  /// In en, this message translates to:
  /// **'Wiki Sources'**
  String get kbWikiSources;

  /// No description provided for @kbUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get kbUpdate;

  /// No description provided for @kbUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get kbUpToDate;

  /// No description provided for @kbRedownload.
  ///
  /// In en, this message translates to:
  /// **'Download again'**
  String get kbRedownload;

  /// No description provided for @kbRedownloadTitle.
  ///
  /// In en, this message translates to:
  /// **'Download the knowledge base again?'**
  String get kbRedownloadTitle;

  /// No description provided for @kbRedownloadBody.
  ///
  /// In en, this message translates to:
  /// **'You already have the latest version. Downloading again fetches about 185 MB and rebuilds the database (about 1 GB of free space needed). It is rarely necessary.'**
  String get kbRedownloadBody;

  /// No description provided for @kbRedownloadConfirm.
  ///
  /// In en, this message translates to:
  /// **'Download again'**
  String get kbRedownloadConfirm;

  /// No description provided for @kbCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get kbCancel;

  /// No description provided for @kbIndexing.
  ///
  /// In en, this message translates to:
  /// **'Indexing...'**
  String get kbIndexing;

  /// No description provided for @kbStartingCrawl.
  ///
  /// In en, this message translates to:
  /// **'Starting crawl of {site}...'**
  String kbStartingCrawl(Object site);

  /// No description provided for @kbCrawlingPages.
  ///
  /// In en, this message translates to:
  /// **'Crawling {site}: {count} pages...'**
  String kbCrawlingPages(Object count, Object site);

  /// No description provided for @kbCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed: {chunks} chunks from {pages} pages.'**
  String kbCompleted(Object chunks, Object pages);

  /// No description provided for @kbFailed.
  ///
  /// In en, this message translates to:
  /// **'Indexing failed: {error}'**
  String kbFailed(Object error);

  /// No description provided for @kbEngineNative.
  ///
  /// In en, this message translates to:
  /// **'Search engine: sqlite-vec (native)'**
  String get kbEngineNative;

  /// No description provided for @kbEngineFallback.
  ///
  /// In en, this message translates to:
  /// **'Search engine: pure Dart (fallback)'**
  String get kbEngineFallback;

  /// No description provided for @materialsTitle.
  ///
  /// In en, this message translates to:
  /// **'Materials'**
  String get materialsTitle;

  /// No description provided for @materialsWarning.
  ///
  /// In en, this message translates to:
  /// **'⚠️ Imported book content may contain unofficial interpretations, translation errors, or personal summaries. AI will prioritize Wiki content and cite book sources with caution.'**
  String get materialsWarning;

  /// No description provided for @materialsNoBooks.
  ///
  /// In en, this message translates to:
  /// **'No books yet'**
  String get materialsNoBooks;

  /// No description provided for @materialsEmptyDesc.
  ///
  /// In en, this message translates to:
  /// **'Keep texts here: lore excerpts, notes, research. They stay on this device and never enter the knowledge base.'**
  String get materialsEmptyDesc;

  /// No description provided for @materialsNoApiKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Configure your API Key in Settings to enable import.'**
  String get materialsNoApiKeyHint;

  /// No description provided for @materialsImportButton.
  ///
  /// In en, this message translates to:
  /// **'Import Books'**
  String get materialsImportButton;

  /// No description provided for @materialsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load books: {error}'**
  String materialsLoadFailed(Object error);

  /// No description provided for @materialsEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Display Name'**
  String get materialsEditTitle;

  /// No description provided for @materialsEditHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a display name'**
  String get materialsEditHint;

  /// No description provided for @materialsCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get materialsCancel;

  /// No description provided for @materialsSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get materialsSave;

  /// No description provided for @materialsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Book'**
  String get materialsDeleteTitle;

  /// No description provided for @materialsDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this text?'**
  String get materialsDeleteConfirm;

  /// No description provided for @materialsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get materialsDelete;

  /// No description provided for @materialsImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String materialsImportFailed(Object error);

  /// No description provided for @materialsChunks.
  ///
  /// In en, this message translates to:
  /// **'{count} chunks'**
  String materialsChunks(Object count);

  /// No description provided for @materialsJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get materialsJustNow;

  /// No description provided for @materialsMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}m ago'**
  String materialsMinutesAgo(Object n);

  /// No description provided for @materialsHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}h ago'**
  String materialsHoursAgo(Object n);

  /// No description provided for @materialsDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}d ago'**
  String materialsDaysAgo(Object n);

  /// No description provided for @importReading.
  ///
  /// In en, this message translates to:
  /// **'Reading {file}'**
  String importReading(Object file);

  /// No description provided for @importChunking.
  ///
  /// In en, this message translates to:
  /// **'Chunking text...'**
  String get importChunking;

  /// No description provided for @importStoring.
  ///
  /// In en, this message translates to:
  /// **'Saving to knowledge base...'**
  String get importStoring;

  /// No description provided for @importDone.
  ///
  /// In en, this message translates to:
  /// **'Import complete'**
  String get importDone;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get importFailed;

  /// No description provided for @importErrorOccurred.
  ///
  /// In en, this message translates to:
  /// **'Error occurred during import.'**
  String get importErrorOccurred;

  /// No description provided for @importDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get importDismiss;

  /// No description provided for @aiChatTitle.
  ///
  /// In en, this message translates to:
  /// **'Lore Advisor'**
  String get aiChatTitle;

  /// No description provided for @aiChatComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming in v0.4'**
  String get aiChatComingSoon;

  /// No description provided for @aiChatComingSoonDesc.
  ///
  /// In en, this message translates to:
  /// **'Three AI agent modes with citation cards and streaming markdown responses.'**
  String get aiChatComingSoonDesc;

  /// No description provided for @wikiTabPrts.
  ///
  /// In en, this message translates to:
  /// **'PRTS Wiki'**
  String get wikiTabPrts;

  /// No description provided for @wikiTabEndfield.
  ///
  /// In en, this message translates to:
  /// **'Endfield Wiki'**
  String get wikiTabEndfield;

  /// No description provided for @wikiSendToAi.
  ///
  /// In en, this message translates to:
  /// **'Send to AI'**
  String get wikiSendToAi;

  /// No description provided for @wikiSendToAiDesc.
  ///
  /// In en, this message translates to:
  /// **'Selected Wiki text is reading context only; factual claims are verified separately with GameData.'**
  String get wikiSendToAiDesc;

  /// No description provided for @wikiSendToSummaryDesc.
  ///
  /// In en, this message translates to:
  /// **'Summarize from the page and selected text'**
  String get wikiSendToSummaryDesc;

  /// No description provided for @wikiSendToFactCheckDesc.
  ///
  /// In en, this message translates to:
  /// **'Use the selected text as the claim to check'**
  String get wikiSendToFactCheckDesc;

  /// No description provided for @wikiReaderMode.
  ///
  /// In en, this message translates to:
  /// **'Reader mode'**
  String get wikiReaderMode;

  /// No description provided for @wikiReaderFontSmaller.
  ///
  /// In en, this message translates to:
  /// **'Smaller text'**
  String get wikiReaderFontSmaller;

  /// No description provided for @wikiReaderFontLarger.
  ///
  /// In en, this message translates to:
  /// **'Larger text'**
  String get wikiReaderFontLarger;

  /// No description provided for @bookmarksTitle.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get bookmarksTitle;

  /// No description provided for @bookmarksLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load bookmarks: {error}'**
  String bookmarksLoadFailed(Object error);

  /// No description provided for @bookmarksEmpty.
  ///
  /// In en, this message translates to:
  /// **'No bookmarks yet'**
  String get bookmarksEmpty;

  /// No description provided for @bookmarksEmptyDesc.
  ///
  /// In en, this message translates to:
  /// **'Save Wiki pages you want to revisit later.'**
  String get bookmarksEmptyDesc;

  /// No description provided for @citationWiki.
  ///
  /// In en, this message translates to:
  /// **'Wiki'**
  String get citationWiki;

  /// No description provided for @citationBook.
  ///
  /// In en, this message translates to:
  /// **'Book'**
  String get citationBook;

  /// No description provided for @citationViewInWiki.
  ///
  /// In en, this message translates to:
  /// **'View in Wiki'**
  String get citationViewInWiki;

  /// No description provided for @onboardingNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get onboardingNotNow;

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to ArkLores'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeDesc.
  ///
  /// In en, this message translates to:
  /// **'Your AI-enhanced companion for exploring Arknights and Endfield lore.\n\n• Browse PRTS & Endfield Wikis\n• Ask AI about the story, with sources from the original text\n• Read the stories and game records'**
  String get onboardingWelcomeDesc;

  /// No description provided for @onboardingGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get onboardingGetStarted;

  /// No description provided for @onboardingApiTitle.
  ///
  /// In en, this message translates to:
  /// **'Configure Chat API'**
  String get onboardingApiTitle;

  /// No description provided for @onboardingApiDesc.
  ///
  /// In en, this message translates to:
  /// **'ArkLores uses your own AI API key.\nConfigure a Chat provider to use AI features.'**
  String get onboardingApiDesc;

  /// No description provided for @onboardingSaveContinue.
  ///
  /// In en, this message translates to:
  /// **'Save & Continue'**
  String get onboardingSaveContinue;

  /// No description provided for @onboardingConfigureLater.
  ///
  /// In en, this message translates to:
  /// **'Configure later'**
  String get onboardingConfigureLater;

  /// No description provided for @onboardingDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'All Set!'**
  String get onboardingDoneTitle;

  /// No description provided for @onboardingDoneDesc.
  ///
  /// In en, this message translates to:
  /// **'You\'re ready to explore the world of Arknights and Endfield.\n\nInstall the GameData knowledge base in Settings,\nor start browsing the Wiki!'**
  String get onboardingDoneDesc;

  /// No description provided for @onboardingStartExploring.
  ///
  /// In en, this message translates to:
  /// **'Start Exploring'**
  String get onboardingStartExploring;

  /// No description provided for @settingsHelpGuide.
  ///
  /// In en, this message translates to:
  /// **'Help & Guide'**
  String get settingsHelpGuide;

  /// No description provided for @settingsHelpSectionCode.
  ///
  /// In en, this message translates to:
  /// **'HELP & GUIDE'**
  String get settingsHelpSectionCode;

  /// No description provided for @settingsVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'ARKLORES / {version}'**
  String settingsVersionLabel(String version);

  /// No description provided for @settingsShowOnboarding.
  ///
  /// In en, this message translates to:
  /// **'Show Onboarding Guide'**
  String get settingsShowOnboarding;

  /// No description provided for @settingsShowOnboardingDesc.
  ///
  /// In en, this message translates to:
  /// **'Replay the first-launch guide to configure the app'**
  String get settingsShowOnboardingDesc;

  /// No description provided for @aiTabAsk.
  ///
  /// In en, this message translates to:
  /// **'Ask AI'**
  String get aiTabAsk;

  /// No description provided for @aiAskSource.
  ///
  /// In en, this message translates to:
  /// **'Answers are grounded in installed GameData story text only'**
  String get aiAskSource;

  /// No description provided for @aiAskEmpty.
  ///
  /// In en, this message translates to:
  /// **'Ask any lore question: what a character went through, how an event came about, whether a claim is true.'**
  String get aiAskEmpty;

  /// No description provided for @aiInputExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand the input'**
  String get aiInputExpand;

  /// No description provided for @aiInputCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse the input'**
  String get aiInputCollapse;

  /// No description provided for @aiInputFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Full-screen input'**
  String get aiInputFullscreen;

  /// No description provided for @aiInputExitFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Exit full screen'**
  String get aiInputExitFullscreen;

  /// No description provided for @aiAskInputPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Ask any lore question...'**
  String get aiAskInputPlaceholder;

  /// No description provided for @aiAskSuggestionAmiya.
  ///
  /// In en, this message translates to:
  /// **'Who is Amiya?'**
  String get aiAskSuggestionAmiya;

  /// No description provided for @aiAskSuggestionVerify.
  ///
  /// In en, this message translates to:
  /// **'Is Amiya the public leader of Rhodes Island?'**
  String get aiAskSuggestionVerify;

  /// No description provided for @aiAskSuggestionInvestigate.
  ///
  /// In en, this message translates to:
  /// **'How was Reunion founded?'**
  String get aiAskSuggestionInvestigate;

  /// No description provided for @aiAskError.
  ///
  /// In en, this message translates to:
  /// **'Failed to answer. Please retry.'**
  String get aiAskError;

  /// No description provided for @aiAskCanceled.
  ///
  /// In en, this message translates to:
  /// **'Answer canceled.'**
  String get aiAskCanceled;

  /// No description provided for @aiTabFactCheck.
  ///
  /// In en, this message translates to:
  /// **'Fact Check'**
  String get aiTabFactCheck;

  /// No description provided for @aiTabSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get aiTabSummary;

  /// No description provided for @aiAnswerStatus.
  ///
  /// In en, this message translates to:
  /// **'Answer status'**
  String get aiAnswerStatus;

  /// No description provided for @aiAnswerStatusAnswered.
  ///
  /// In en, this message translates to:
  /// **'Answered'**
  String get aiAnswerStatusAnswered;

  /// No description provided for @aiAnswerStatusPartial.
  ///
  /// In en, this message translates to:
  /// **'Partial (limited evidence)'**
  String get aiAnswerStatusPartial;

  /// No description provided for @aiAnswerStatusNotCovered.
  ///
  /// In en, this message translates to:
  /// **'Not covered by the knowledge base'**
  String get aiAnswerStatusNotCovered;

  /// No description provided for @aiInvestigationConfidence.
  ///
  /// In en, this message translates to:
  /// **'Confidence'**
  String get aiInvestigationConfidence;

  /// No description provided for @aiCitationLine.
  ///
  /// In en, this message translates to:
  /// **'line {line}'**
  String aiCitationLine(int line);

  /// No description provided for @aiCitationLines.
  ///
  /// In en, this message translates to:
  /// **'lines {start}–{end}'**
  String aiCitationLines(int start, int end);

  /// No description provided for @aiAnswerDetails.
  ///
  /// In en, this message translates to:
  /// **'Details · {count} points'**
  String aiAnswerDetails(int count);

  /// No description provided for @aiEvidenceSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} citations · {stories} stories'**
  String aiEvidenceSummary(int count, int stories);

  /// No description provided for @aiChapterCount.
  ///
  /// In en, this message translates to:
  /// **'{count} cited'**
  String aiChapterCount(int count);

  /// No description provided for @aiCitedRecord.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get aiCitedRecord;

  /// No description provided for @aiCitedRecords.
  ///
  /// In en, this message translates to:
  /// **'{count} other records'**
  String aiCitedRecords(int count);

  /// No description provided for @aiCitedLinesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Original text unavailable (knowledge base missing or updated)'**
  String get aiCitedLinesUnavailable;

  /// No description provided for @aiStoryReaderTitle.
  ///
  /// In en, this message translates to:
  /// **'Original text'**
  String get aiStoryReaderTitle;

  /// No description provided for @aiCitationSources.
  ///
  /// In en, this message translates to:
  /// **'Sources {count}'**
  String aiCitationSources(int count);

  /// No description provided for @aiStoryReaderJumpBack.
  ///
  /// In en, this message translates to:
  /// **'Back to the cited lines'**
  String get aiStoryReaderJumpBack;

  /// No description provided for @aiStoryReaderCited.
  ///
  /// In en, this message translates to:
  /// **'Cited: {range}'**
  String aiStoryReaderCited(String range);

  /// No description provided for @aiStoryReaderEnd.
  ///
  /// In en, this message translates to:
  /// **'End of chapter'**
  String get aiStoryReaderEnd;

  /// No description provided for @libraryTabRead.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get libraryTabRead;

  /// No description provided for @libraryTabMine.
  ///
  /// In en, this message translates to:
  /// **'My texts'**
  String get libraryTabMine;

  /// No description provided for @librarySearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get librarySearchTitle;

  /// No description provided for @librarySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search chapters, entries, stage codes'**
  String get librarySearchHint;

  /// No description provided for @libraryContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue reading'**
  String get libraryContinue;

  /// No description provided for @libraryShelves.
  ///
  /// In en, this message translates to:
  /// **'Shelves'**
  String get libraryShelves;

  /// No description provided for @libraryViewAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get libraryViewAll;

  /// No description provided for @shelfMain.
  ///
  /// In en, this message translates to:
  /// **'Main story'**
  String get shelfMain;

  /// No description provided for @shelfActivity.
  ///
  /// In en, this message translates to:
  /// **'Other events'**
  String get shelfActivity;

  /// No description provided for @shelfSideStory.
  ///
  /// In en, this message translates to:
  /// **'Side Story'**
  String get shelfSideStory;

  /// No description provided for @shelfMiniStory.
  ///
  /// In en, this message translates to:
  /// **'Story collections'**
  String get shelfMiniStory;

  /// No description provided for @shelfBranchline.
  ///
  /// In en, this message translates to:
  /// **'Interludes'**
  String get shelfBranchline;

  /// No description provided for @shelfMemory.
  ///
  /// In en, this message translates to:
  /// **'Operators'**
  String get shelfMemory;

  /// No description provided for @shelfRoguelike.
  ///
  /// In en, this message translates to:
  /// **'Integrated Strategies'**
  String get shelfRoguelike;

  /// No description provided for @shelfSandbox.
  ///
  /// In en, this message translates to:
  /// **'Sandbox'**
  String get shelfSandbox;

  /// No description provided for @shelfRetro.
  ///
  /// In en, this message translates to:
  /// **'Re-runs'**
  String get shelfRetro;

  /// No description provided for @shelfCodex.
  ///
  /// In en, this message translates to:
  /// **'Codex'**
  String get shelfCodex;

  /// No description provided for @shelfOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get shelfOther;

  /// No description provided for @libraryOperatorRecords.
  ///
  /// In en, this message translates to:
  /// **'Operator records'**
  String get libraryOperatorRecords;

  /// No description provided for @libraryOperatorProfile.
  ///
  /// In en, this message translates to:
  /// **'Operator file'**
  String get libraryOperatorProfile;

  /// No description provided for @libraryAllEntries.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get libraryAllEntries;

  /// No description provided for @libraryCountCollections.
  ///
  /// In en, this message translates to:
  /// **'{n} sets'**
  String libraryCountCollections(int n);

  /// No description provided for @libraryCountStories.
  ///
  /// In en, this message translates to:
  /// **'{n} stories'**
  String libraryCountStories(int n);

  /// No description provided for @libraryCountEntries.
  ///
  /// In en, this message translates to:
  /// **'{n} entries'**
  String libraryCountEntries(int n);

  /// No description provided for @libraryNotInstalledTitle.
  ///
  /// In en, this message translates to:
  /// **'No knowledge base yet'**
  String get libraryNotInstalledTitle;

  /// No description provided for @libraryNotInstalledDesc.
  ///
  /// In en, this message translates to:
  /// **'Download or build it under Settings → Knowledge base; the stories and texts to read appear here.'**
  String get libraryNotInstalledDesc;

  /// No description provided for @libraryOldSchemaTitle.
  ///
  /// In en, this message translates to:
  /// **'The knowledge base needs an update'**
  String get libraryOldSchemaTitle;

  /// No description provided for @libraryOldSchemaDesc.
  ///
  /// In en, this message translates to:
  /// **'The installed knowledge base is an older version without the story-set index. Update it under Settings → Knowledge base to read here.'**
  String get libraryOldSchemaDesc;

  /// No description provided for @libraryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get libraryEmpty;

  /// No description provided for @libraryStories.
  ///
  /// In en, this message translates to:
  /// **'Stories'**
  String get libraryStories;

  /// No description provided for @libraryOtherSections.
  ///
  /// In en, this message translates to:
  /// **'Related texts'**
  String get libraryOtherSections;

  /// No description provided for @libraryParts.
  ///
  /// In en, this message translates to:
  /// **'Unlocked stories'**
  String get libraryParts;

  /// No description provided for @libraryLeftoverStories.
  ///
  /// In en, this message translates to:
  /// **'Other stories'**
  String get libraryLeftoverStories;

  /// No description provided for @libraryFilterHint.
  ///
  /// In en, this message translates to:
  /// **'Filter this list'**
  String get libraryFilterHint;

  /// No description provided for @libraryProgress.
  ///
  /// In en, this message translates to:
  /// **'{percent}% read'**
  String libraryProgress(int percent);

  /// No description provided for @libraryFinished.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get libraryFinished;

  /// No description provided for @storyReaderBattleDialogue.
  ///
  /// In en, this message translates to:
  /// **'In-battle dialogue'**
  String get storyReaderBattleDialogue;

  /// No description provided for @libraryReadTimes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Read once} other{Read {count} times}}'**
  String libraryReadTimes(int count);

  /// No description provided for @libraryRelease.
  ///
  /// In en, this message translates to:
  /// **'Released {month}'**
  String libraryRelease(String month);

  /// No description provided for @libraryRelated.
  ///
  /// In en, this message translates to:
  /// **'Related'**
  String get libraryRelated;

  /// No description provided for @libraryNoText.
  ///
  /// In en, this message translates to:
  /// **'This entry has no text'**
  String get libraryNoText;

  /// No description provided for @libraryNoResults.
  ///
  /// In en, this message translates to:
  /// **'Nothing found'**
  String get libraryNoResults;

  /// No description provided for @librarySearchCollections.
  ///
  /// In en, this message translates to:
  /// **'Story sets and topics'**
  String get librarySearchCollections;

  /// No description provided for @librarySearchEntries.
  ///
  /// In en, this message translates to:
  /// **'Entries'**
  String get librarySearchEntries;

  /// No description provided for @storyReaderNext.
  ///
  /// In en, this message translates to:
  /// **'Next chapter'**
  String get storyReaderNext;

  /// No description provided for @storyReaderPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous chapter'**
  String get storyReaderPrevious;

  /// No description provided for @storyReaderResumed.
  ///
  /// In en, this message translates to:
  /// **'Continue · line {line}'**
  String storyReaderResumed(int line);

  /// No description provided for @storyReaderSynopsis.
  ///
  /// In en, this message translates to:
  /// **'Official synopsis'**
  String get storyReaderSynopsis;

  /// No description provided for @materialsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No texts of your own yet'**
  String get materialsEmptyTitle;

  /// No description provided for @materialsNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get materialsNew;

  /// No description provided for @materialsPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste from clipboard'**
  String get materialsPaste;

  /// No description provided for @materialsTitleHint.
  ///
  /// In en, this message translates to:
  /// **'Title (optional)'**
  String get materialsTitleHint;

  /// No description provided for @materialsBodyHint.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get materialsBodyHint;

  /// No description provided for @materialsEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get materialsEdit;

  /// No description provided for @materialsChars.
  ///
  /// In en, this message translates to:
  /// **'{n} characters'**
  String materialsChars(int n);

  /// No description provided for @materialsClipboardEmpty.
  ///
  /// In en, this message translates to:
  /// **'The clipboard has no text'**
  String get materialsClipboardEmpty;

  /// No description provided for @materialsDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard unsaved changes?'**
  String get materialsDiscard;

  /// No description provided for @materialsDiscardAction.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get materialsDiscardAction;

  /// No description provided for @materialsAskAbout.
  ///
  /// In en, this message translates to:
  /// **'Ask about it'**
  String get materialsAskAbout;

  /// No description provided for @readingHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Recently read'**
  String get readingHistoryTitle;

  /// No description provided for @readingHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing read yet. Stories you open from an answer\'s evidence show up here.'**
  String get readingHistoryEmpty;

  /// No description provided for @readingHistoryPage.
  ///
  /// In en, this message translates to:
  /// **'Page {page} / {pages}'**
  String readingHistoryPage(Object page, Object pages);

  /// No description provided for @readingHistoryClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get readingHistoryClear;

  /// No description provided for @readingHistoryJumpTitle.
  ///
  /// In en, this message translates to:
  /// **'Go to page'**
  String get readingHistoryJumpTitle;

  /// No description provided for @readingHistoryJumpHint.
  ///
  /// In en, this message translates to:
  /// **'1 – {pages}'**
  String readingHistoryJumpHint(int pages);

  /// No description provided for @readingHistoryJumpGo.
  ///
  /// In en, this message translates to:
  /// **'Go'**
  String get readingHistoryJumpGo;

  /// No description provided for @readingHistoryClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear the whole reading history?'**
  String get readingHistoryClearConfirm;

  /// No description provided for @readingHistoryRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove from history'**
  String get readingHistoryRemove;

  /// No description provided for @readingHistoryLine.
  ///
  /// In en, this message translates to:
  /// **'line {line}'**
  String readingHistoryLine(int line);

  /// No description provided for @aiStoryReaderMoved.
  ///
  /// In en, this message translates to:
  /// **'The text changed; showing the approximate place'**
  String get aiStoryReaderMoved;

  /// No description provided for @aiMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get aiMoreActions;

  /// No description provided for @aiThinkingProcess.
  ///
  /// In en, this message translates to:
  /// **'Thinking'**
  String get aiThinkingProcess;

  /// No description provided for @aiDeepThinking.
  ///
  /// In en, this message translates to:
  /// **'Deep thinking'**
  String get aiDeepThinking;

  /// No description provided for @aiDeepThinkingTooltip.
  ///
  /// In en, this message translates to:
  /// **'Think before writing the answer (slower, more tokens)'**
  String get aiDeepThinkingTooltip;

  /// No description provided for @aiScrollToBottom.
  ///
  /// In en, this message translates to:
  /// **'Scroll to bottom'**
  String get aiScrollToBottom;

  /// No description provided for @aiInvestigationCoverage.
  ///
  /// In en, this message translates to:
  /// **'Coverage'**
  String get aiInvestigationCoverage;

  /// No description provided for @aiInvestigationRead.
  ///
  /// In en, this message translates to:
  /// **'read'**
  String get aiInvestigationRead;

  /// No description provided for @aiInvestigationMapped.
  ///
  /// In en, this message translates to:
  /// **'mapped'**
  String get aiInvestigationMapped;

  /// No description provided for @aiInvestigationSkipped.
  ///
  /// In en, this message translates to:
  /// **'skipped'**
  String get aiInvestigationSkipped;

  /// No description provided for @aiVerdictSupported.
  ///
  /// In en, this message translates to:
  /// **'Supported'**
  String get aiVerdictSupported;

  /// No description provided for @aiVerdictRefuted.
  ///
  /// In en, this message translates to:
  /// **'Refuted'**
  String get aiVerdictRefuted;

  /// No description provided for @aiVerdictUncertain.
  ///
  /// In en, this message translates to:
  /// **'Uncertain'**
  String get aiVerdictUncertain;

  /// No description provided for @aiVerdictUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Cannot confirm'**
  String get aiVerdictUnavailable;

  /// No description provided for @aiVerdictSemantics.
  ///
  /// In en, this message translates to:
  /// **'Fact-check verdict: {verdict}'**
  String aiVerdictSemantics(String verdict);

  /// No description provided for @aiEvidenceTitle.
  ///
  /// In en, this message translates to:
  /// **'GameData evidence ({count})'**
  String aiEvidenceTitle(int count);

  /// No description provided for @aiEvidenceSection.
  ///
  /// In en, this message translates to:
  /// **'Section'**
  String get aiEvidenceSection;

  /// No description provided for @aiEvidenceContentType.
  ///
  /// In en, this message translates to:
  /// **'Content type'**
  String get aiEvidenceContentType;

  /// No description provided for @aiEvidenceSourcePath.
  ///
  /// In en, this message translates to:
  /// **'Source path'**
  String get aiEvidenceSourcePath;

  /// No description provided for @aiEvidenceRawId.
  ///
  /// In en, this message translates to:
  /// **'Raw ID'**
  String get aiEvidenceRawId;

  /// No description provided for @aiEvidenceRetrievalType.
  ///
  /// In en, this message translates to:
  /// **'Retrieval type'**
  String get aiEvidenceRetrievalType;

  /// No description provided for @aiEvidenceRankingReason.
  ///
  /// In en, this message translates to:
  /// **'Ranking reason'**
  String get aiEvidenceRankingReason;

  /// No description provided for @aiEvidenceTrustNote.
  ///
  /// In en, this message translates to:
  /// **'Trust note'**
  String get aiEvidenceTrustNote;

  /// No description provided for @aiCoverageDirect.
  ///
  /// In en, this message translates to:
  /// **'Direct candidate'**
  String get aiCoverageDirect;

  /// No description provided for @aiCoverageRetrieved.
  ///
  /// In en, this message translates to:
  /// **'Retrieved context'**
  String get aiCoverageRetrieved;

  /// No description provided for @aiEvidenceSemantics.
  ///
  /// In en, this message translates to:
  /// **'GameData evidence: {title}; coverage: {coverage}'**
  String aiEvidenceSemantics(String title, String coverage);

  /// No description provided for @aiThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get aiThinking;

  /// No description provided for @aiReasoning.
  ///
  /// In en, this message translates to:
  /// **'Reasoning…'**
  String get aiReasoning;

  /// No description provided for @aiProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing…'**
  String get aiProcessing;

  /// No description provided for @aiReasoningComplete.
  ///
  /// In en, this message translates to:
  /// **'Reasoning complete'**
  String get aiReasoningComplete;

  /// No description provided for @aiUsingTool.
  ///
  /// In en, this message translates to:
  /// **'Using tool: {tool}'**
  String aiUsingTool(String tool);

  /// No description provided for @aiWorkSummary.
  ///
  /// In en, this message translates to:
  /// **'{calls} lookups · {reads} stories read'**
  String aiWorkSummary(int calls, int reads);

  /// No description provided for @aiWorkSql.
  ///
  /// In en, this message translates to:
  /// **'Query the knowledge base'**
  String get aiWorkSql;

  /// No description provided for @aiWorkGrep.
  ///
  /// In en, this message translates to:
  /// **'Search for “{pattern}”'**
  String aiWorkGrep(String pattern);

  /// No description provided for @aiWorkGrepIn.
  ///
  /// In en, this message translates to:
  /// **'Search “{pattern}” in {scope}'**
  String aiWorkGrepIn(String scope, String pattern);

  /// No description provided for @aiWorkRead.
  ///
  /// In en, this message translates to:
  /// **'Read “{story}”'**
  String aiWorkRead(String story);

  /// No description provided for @aiWorkOutline.
  ///
  /// In en, this message translates to:
  /// **'Chapter list of {collection}'**
  String aiWorkOutline(String collection);

  /// No description provided for @aiWorkFind.
  ///
  /// In en, this message translates to:
  /// **'Find by meaning: “{query}”'**
  String aiWorkFind(String query);

  /// No description provided for @aiWorkSimilar.
  ///
  /// In en, this message translates to:
  /// **'Names like “{name}”'**
  String aiWorkSimilar(String name);

  /// No description provided for @aiWorkDelegate.
  ///
  /// In en, this message translates to:
  /// **'Helper: {task}'**
  String aiWorkDelegate(String task);

  /// No description provided for @aiWorkRedo.
  ///
  /// In en, this message translates to:
  /// **'Sources did not match; rewriting'**
  String get aiWorkRedo;

  /// No description provided for @aiWorkHits.
  ///
  /// In en, this message translates to:
  /// **'{hits} hits · {stories} stories'**
  String aiWorkHits(int hits, int stories);

  /// No description provided for @aiWorkRows.
  ///
  /// In en, this message translates to:
  /// **'{count} rows'**
  String aiWorkRows(int count);

  /// No description provided for @aiWorkLines.
  ///
  /// In en, this message translates to:
  /// **'lines {start}–{end}'**
  String aiWorkLines(int start, int end);

  /// No description provided for @aiWorkNone.
  ///
  /// In en, this message translates to:
  /// **'nothing found'**
  String get aiWorkNone;

  /// No description provided for @aiWorkFailed.
  ///
  /// In en, this message translates to:
  /// **'failed'**
  String get aiWorkFailed;

  /// No description provided for @aiWorkRunning.
  ///
  /// In en, this message translates to:
  /// **'running'**
  String get aiWorkRunning;

  /// No description provided for @aiWorkRaw.
  ///
  /// In en, this message translates to:
  /// **'Raw output'**
  String get aiWorkRaw;

  /// No description provided for @aiStepsStatus.
  ///
  /// In en, this message translates to:
  /// **'{status} ({count} steps)'**
  String aiStepsStatus(String status, int count);

  /// No description provided for @aiRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get aiRetry;

  /// No description provided for @aiCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get aiCancel;

  /// No description provided for @aiSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get aiSend;

  /// No description provided for @aiInputPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Enter lore query or claim...'**
  String get aiInputPlaceholder;

  /// No description provided for @aiSettingsRequired.
  ///
  /// In en, this message translates to:
  /// **'Please configure your Chat API Key in settings first to use AI features.'**
  String get aiSettingsRequired;

  /// No description provided for @aiSettingsGoTo.
  ///
  /// In en, this message translates to:
  /// **'Go to Settings'**
  String get aiSettingsGoTo;

  /// No description provided for @aiClearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear Chat'**
  String get aiClearHistory;

  /// No description provided for @aiClearHistoryConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to clear the chat history for this tab?'**
  String get aiClearHistoryConfirm;

  /// No description provided for @aiClearConfirmBtn.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get aiClearConfirmBtn;

  /// No description provided for @aiNewConversation.
  ///
  /// In en, this message translates to:
  /// **'New conversation'**
  String get aiNewConversation;

  /// No description provided for @aiHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat History'**
  String get aiHistoryTitle;

  /// No description provided for @aiHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet. Messages are saved to the on-device chat_sessions folder automatically.'**
  String get aiHistoryEmpty;

  /// No description provided for @aiHistoryContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get aiHistoryContinue;

  /// No description provided for @aiHistoryView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get aiHistoryView;

  /// No description provided for @aiHistoryDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get aiHistoryDelete;

  /// No description provided for @aiHistoryDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this conversation? This cannot be undone.'**
  String get aiHistoryDeleteConfirm;

  /// No description provided for @aiHistoryCorrupt.
  ///
  /// In en, this message translates to:
  /// **'Corrupt session file'**
  String get aiHistoryCorrupt;

  /// No description provided for @aiHistoryTurns.
  ///
  /// In en, this message translates to:
  /// **'{count} turns'**
  String aiHistoryTurns(int count);

  /// No description provided for @settingsAppIcon.
  ///
  /// In en, this message translates to:
  /// **'App icon'**
  String get settingsAppIcon;

  /// No description provided for @settingsIconLightLabel.
  ///
  /// In en, this message translates to:
  /// **'Light icon'**
  String get settingsIconLightLabel;

  /// No description provided for @settingsIconDarkLabel.
  ///
  /// In en, this message translates to:
  /// **'Dark icon'**
  String get settingsIconDarkLabel;

  /// No description provided for @settingsIconLightShort.
  ///
  /// In en, this message translates to:
  /// **'LIGHT'**
  String get settingsIconLightShort;

  /// No description provided for @settingsIconDarkShort.
  ///
  /// In en, this message translates to:
  /// **'DARK'**
  String get settingsIconDarkShort;

  /// No description provided for @settingsIconUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Runtime icon switching is not supported on this platform. Settings were saved.'**
  String get settingsIconUnsupported;

  /// No description provided for @settingsWikiSources.
  ///
  /// In en, this message translates to:
  /// **'Wiki Sources'**
  String get settingsWikiSources;

  /// No description provided for @settingsWikiSourcesDesc.
  ///
  /// In en, this message translates to:
  /// **'Edit built-in Wiki URLs or add custom Wiki entries.'**
  String get settingsWikiSourcesDesc;

  /// No description provided for @wikiSourcesAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Wiki'**
  String get wikiSourcesAddTitle;

  /// No description provided for @wikiSourcesEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Wiki'**
  String get wikiSourcesEditTitle;

  /// No description provided for @wikiSourcesNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get wikiSourcesNameLabel;

  /// No description provided for @wikiSourcesIconUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Icon URL (optional)'**
  String get wikiSourcesIconUrlLabel;

  /// No description provided for @wikiSourcesEndfieldPreset.
  ///
  /// In en, this message translates to:
  /// **'Endfield Wiki presets'**
  String get wikiSourcesEndfieldPreset;

  /// No description provided for @wikiSourcesReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get wikiSourcesReset;

  /// No description provided for @wikiSourcesEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get wikiSourcesEdit;

  /// No description provided for @wikiSourcesDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get wikiSourcesDelete;

  /// No description provided for @wikiSourcesCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get wikiSourcesCancel;

  /// No description provided for @wikiSourcesSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get wikiSourcesSave;

  /// No description provided for @wikiSourcesNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a Wiki name.'**
  String get wikiSourcesNameRequired;

  /// No description provided for @wikiSourcesUrlRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid URL.'**
  String get wikiSourcesUrlRequired;

  /// No description provided for @kbStructuredTitle.
  ///
  /// In en, this message translates to:
  /// **'GameData structured knowledge base'**
  String get kbStructuredTitle;

  /// No description provided for @kbScopeDescription.
  ///
  /// In en, this message translates to:
  /// **'The AI uses only the Chinese GameData knowledge base as evidence: entities, aliases, raw records, story text and search indexes, plus optional story vectors. Wiki pages and imported materials are not used as evidence.'**
  String get kbScopeDescription;

  /// No description provided for @kbStatusError.
  ///
  /// In en, this message translates to:
  /// **'Failed to read GameData status: {error}'**
  String kbStatusError(String error);

  /// No description provided for @kbInstalled.
  ///
  /// In en, this message translates to:
  /// **'GameData main knowledge base installed'**
  String get kbInstalled;

  /// No description provided for @kbNoAssetUrl.
  ///
  /// In en, this message translates to:
  /// **'This build has no GameData release asset URL configured'**
  String get kbNoAssetUrl;

  /// No description provided for @kbErrorInvalidUrl.
  ///
  /// In en, this message translates to:
  /// **'Could not resolve the download URL. On a real device, make sure the phone can reach this GitHub / LAN URL.'**
  String get kbErrorInvalidUrl;

  /// No description provided for @kbConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to the server… (attempt {attempt})'**
  String kbConnecting(int attempt);

  /// No description provided for @kbVerifying.
  ///
  /// In en, this message translates to:
  /// **'Checking the file…'**
  String get kbVerifying;

  /// No description provided for @kbInstalling.
  ///
  /// In en, this message translates to:
  /// **'Unzipping and installing, about a minute or two. Please do not quit…'**
  String get kbInstalling;

  /// No description provided for @kbCancelDownload.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get kbCancelDownload;

  /// No description provided for @kbManualHint.
  ///
  /// In en, this message translates to:
  /// **'If the network cannot reach the server: download arklores_gamedata_zh.db.gz from the Release on another network, rename it to arklores_gamedata_zh.db.download.gz, put it in {dir}, then tap Download.'**
  String kbManualHint(String dir);

  /// No description provided for @kbErrorTimeout.
  ///
  /// In en, this message translates to:
  /// **'Connection timed out. Check the network and try again; the downloaded part is kept.'**
  String get kbErrorTimeout;

  /// No description provided for @kbErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'The connection was interrupted (unstable network or GitHub temporarily unreachable). It was retried several times; the downloaded part is kept, and tapping Update resumes from there.'**
  String get kbErrorNetwork;

  /// No description provided for @kbErrorNotFound.
  ///
  /// In en, this message translates to:
  /// **'The knowledge base file was not found on the server (the new version may not be public yet). Please try again later.'**
  String get kbErrorNotFound;

  /// No description provided for @kbErrorChecksum.
  ///
  /// In en, this message translates to:
  /// **'GameData DB checksum failed. The file may be corrupted or the SHA256 does not match the build parameters.'**
  String get kbErrorChecksum;

  /// No description provided for @kbDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to download the GameData main knowledge base: {error}'**
  String kbDownloadFailed(String error);

  /// No description provided for @kbNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Not installed'**
  String get kbNotInstalled;

  /// No description provided for @kbDevAssetHint.
  ///
  /// In en, this message translates to:
  /// **'Download the published knowledge base (it is unpacked after download; keep about 1 GB of free space).'**
  String get kbDevAssetHint;

  /// No description provided for @kbUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'A newer official knowledge base is available. Tap Update to download it (keep about 1 GB of free space).'**
  String get kbUpdateAvailable;

  /// No description provided for @kbDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get kbDownloading;

  /// No description provided for @kbDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get kbDownload;

  /// No description provided for @kbStatEntities.
  ///
  /// In en, this message translates to:
  /// **'Entities'**
  String get kbStatEntities;

  /// No description provided for @kbStatRecords.
  ///
  /// In en, this message translates to:
  /// **'Raw records'**
  String get kbStatRecords;

  /// No description provided for @kbStatChunks.
  ///
  /// In en, this message translates to:
  /// **'Document chunks'**
  String get kbStatChunks;

  /// No description provided for @kbStatSourceCommit.
  ///
  /// In en, this message translates to:
  /// **'Source commit'**
  String get kbStatSourceCommit;

  /// No description provided for @kbBuildSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Build from source repo'**
  String get kbBuildSectionTitle;

  /// No description provided for @kbBuildSectionDesc.
  ///
  /// In en, this message translates to:
  /// **'Pull the latest unpacked data from Kengxxiao/ArknightsGameData and build or incrementally update the knowledge base on this device. Requires network; ~1.5–2 GB free space for the first build.'**
  String get kbBuildSectionDesc;

  /// No description provided for @kbBuildLatestCommit.
  ///
  /// In en, this message translates to:
  /// **'Latest commit'**
  String get kbBuildLatestCommit;

  /// No description provided for @kbBuildInstalledCommit.
  ///
  /// In en, this message translates to:
  /// **'Installed commit'**
  String get kbBuildInstalledCommit;

  /// No description provided for @kbBuildCheckUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get kbBuildCheckUpdates;

  /// No description provided for @kbBuildFromSource.
  ///
  /// In en, this message translates to:
  /// **'Build from source'**
  String get kbBuildFromSource;

  /// No description provided for @kbBuildCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get kbBuildCancel;

  /// No description provided for @kbBuildChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking upstream commits…'**
  String get kbBuildChecking;

  /// No description provided for @kbBuildDownloadingZip.
  ///
  /// In en, this message translates to:
  /// **'Downloading source bundle (first time, large)…'**
  String get kbBuildDownloadingZip;

  /// No description provided for @kbBuildDownloadingChanges.
  ///
  /// In en, this message translates to:
  /// **'Downloading incremental changes…'**
  String get kbBuildDownloadingChanges;

  /// No description provided for @kbBuildExtracting.
  ///
  /// In en, this message translates to:
  /// **'Extracting and filtering source data…'**
  String get kbBuildExtracting;

  /// No description provided for @kbBuildSwapping.
  ///
  /// In en, this message translates to:
  /// **'Replacing the knowledge base…'**
  String get kbBuildSwapping;

  /// No description provided for @kbBuildStageStart.
  ///
  /// In en, this message translates to:
  /// **'Preparing build'**
  String get kbBuildStageStart;

  /// No description provided for @kbBuildStageCopy.
  ///
  /// In en, this message translates to:
  /// **'Copying existing database'**
  String get kbBuildStageCopy;

  /// No description provided for @kbBuildStageIncremental.
  ///
  /// In en, this message translates to:
  /// **'Applying incremental changes'**
  String get kbBuildStageIncremental;

  /// No description provided for @kbBuildStageProfiles.
  ///
  /// In en, this message translates to:
  /// **'Importing character profiles'**
  String get kbBuildStageProfiles;

  /// No description provided for @kbBuildStageVoices.
  ///
  /// In en, this message translates to:
  /// **'Importing voices'**
  String get kbBuildStageVoices;

  /// No description provided for @kbBuildStageStructured.
  ///
  /// In en, this message translates to:
  /// **'Importing structured tables'**
  String get kbBuildStageStructured;

  /// No description provided for @kbBuildStageStories.
  ///
  /// In en, this message translates to:
  /// **'Importing stories'**
  String get kbBuildStageStories;

  /// No description provided for @kbBuildStageCoverage.
  ///
  /// In en, this message translates to:
  /// **'Building entity coverage layer'**
  String get kbBuildStageCoverage;

  /// No description provided for @kbBuildStageCoverageSpeakers.
  ///
  /// In en, this message translates to:
  /// **'Expanding speaker entities…'**
  String get kbBuildStageCoverageSpeakers;

  /// No description provided for @kbBuildStageCoverageTrie.
  ///
  /// In en, this message translates to:
  /// **'Building entity index…'**
  String get kbBuildStageCoverageTrie;

  /// No description provided for @kbBuildStageCoverageScan.
  ///
  /// In en, this message translates to:
  /// **'Scanning character appearances…'**
  String get kbBuildStageCoverageScan;

  /// No description provided for @kbBuildStageCoverageRare.
  ///
  /// In en, this message translates to:
  /// **'Counting rare terms…'**
  String get kbBuildStageCoverageRare;

  /// No description provided for @kbBuildStageCoverageProfiles.
  ///
  /// In en, this message translates to:
  /// **'Writing chapter profiles…'**
  String get kbBuildStageCoverageProfiles;

  /// No description provided for @kbBuildStageFts.
  ///
  /// In en, this message translates to:
  /// **'Rebuilding full-text indexes'**
  String get kbBuildStageFts;

  /// No description provided for @kbBuildIncrementalDone.
  ///
  /// In en, this message translates to:
  /// **'Incremental update complete; the knowledge base has been replaced.'**
  String get kbBuildIncrementalDone;

  /// No description provided for @kbBuildFullDone.
  ///
  /// In en, this message translates to:
  /// **'Full build complete; the knowledge base has been replaced.'**
  String get kbBuildFullDone;

  /// No description provided for @kbBuildError.
  ///
  /// In en, this message translates to:
  /// **'Build failed'**
  String get kbBuildError;

  /// No description provided for @kbBuildTokenTitle.
  ///
  /// In en, this message translates to:
  /// **'GitHub token (optional)'**
  String get kbBuildTokenTitle;

  /// No description provided for @kbBuildTokenDesc.
  ///
  /// In en, this message translates to:
  /// **'Enter a GitHub Personal Access Token (ghp_… or github_pat_…) to raise the API quota from 60 to 5000 requests/hour and avoid rate-limit failures on shared proxy egress IPs. The token is stored in OS secure storage and never logged.'**
  String get kbBuildTokenDesc;

  /// No description provided for @kbBuildTokenPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Paste GitHub token'**
  String get kbBuildTokenPlaceholder;

  /// No description provided for @kbBuildTokenSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get kbBuildTokenSave;

  /// No description provided for @kbBuildTokenSaved.
  ///
  /// In en, this message translates to:
  /// **'GitHub token saved.'**
  String get kbBuildTokenSaved;

  /// No description provided for @kbBuildTokenCleared.
  ///
  /// In en, this message translates to:
  /// **'GitHub token cleared.'**
  String get kbBuildTokenCleared;

  /// No description provided for @kbBuildTokenSetHint.
  ///
  /// In en, this message translates to:
  /// **'GitHub token set (quota 5000/hr)'**
  String get kbBuildTokenSetHint;

  /// No description provided for @materialsPausedTitle.
  ///
  /// In en, this message translates to:
  /// **'User material import is not enabled yet'**
  String get materialsPausedTitle;

  /// No description provided for @materialsPausedDesc.
  ///
  /// In en, this message translates to:
  /// **'The legacy PDF/TXT import pipeline is paused. The AI currently uses only the GameData knowledge base as evidence.'**
  String get materialsPausedDesc;

  /// No description provided for @wikiLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Wiki page failed to load'**
  String get wikiLoadFailed;

  /// No description provided for @wikiRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get wikiRetry;

  /// No description provided for @wikiErrorDns.
  ///
  /// In en, this message translates to:
  /// **'Could not resolve the Wiki domain. Check your network, DNS, or proxy and retry.'**
  String get wikiErrorDns;

  /// No description provided for @wikiErrorTimeout.
  ///
  /// In en, this message translates to:
  /// **'Connection timed out. Switch networks or check that your proxy/VPN is connected, then retry.'**
  String get wikiErrorTimeout;

  /// No description provided for @wikiErrorOffline.
  ///
  /// In en, this message translates to:
  /// **'The device currently has no network connection.'**
  String get wikiErrorOffline;

  /// No description provided for @kbBuildChangeSummary.
  ///
  /// In en, this message translates to:
  /// **'Upstream has updates: {stories} story files, {tables} data tables, {levels} level files.'**
  String kbBuildChangeSummary(int stories, int tables, int levels);

  /// No description provided for @kbBuildNoChanges.
  ///
  /// In en, this message translates to:
  /// **'Nothing upstream concerns the knowledge base; no update needed.'**
  String get kbBuildNoChanges;

  /// No description provided for @kbBuildTooManyChanges.
  ///
  /// In en, this message translates to:
  /// **'Too much changed upstream to apply file by file; Build will rebuild completely instead (about 170 MB to download, takes a while).'**
  String get kbBuildTooManyChanges;

  /// No description provided for @kbBuildDownloadingContext.
  ///
  /// In en, this message translates to:
  /// **'Downloading the data tables the update needs…'**
  String get kbBuildDownloadingContext;

  /// No description provided for @kbBuildReportTitle.
  ///
  /// In en, this message translates to:
  /// **'What this update changed'**
  String get kbBuildReportTitle;

  /// No description provided for @kbBuildReportStories.
  ///
  /// In en, this message translates to:
  /// **'Story files: {added} added, {changed} changed, {removed} removed'**
  String kbBuildReportStories(int added, int changed, int removed);

  /// No description provided for @kbBuildReportEntries.
  ///
  /// In en, this message translates to:
  /// **'Entries: {text}'**
  String kbBuildReportEntries(String text);

  /// No description provided for @kbBuildReportNew.
  ///
  /// In en, this message translates to:
  /// **'New collections: {names}'**
  String kbBuildReportNew(String names);

  /// No description provided for @kbBuildReportVectors.
  ///
  /// In en, this message translates to:
  /// **'{count} vectors became invalid because their story changed; you can add them below under Story vectors.'**
  String kbBuildReportVectors(int count);

  /// No description provided for @kbVectorTitle.
  ///
  /// In en, this message translates to:
  /// **'Story vectors (semantic search)'**
  String get kbVectorTitle;

  /// No description provided for @kbVectorDesc.
  ///
  /// In en, this message translates to:
  /// **'Vectors let story search match by meaning, not only by exact words. Everything works without them; those stories just get keyword search only. Vectors only locate; the evidence of an answer is still the original text.'**
  String get kbVectorDesc;

  /// No description provided for @kbVectorStatus.
  ///
  /// In en, this message translates to:
  /// **'{vectors} vectors covering {stories} stories'**
  String kbVectorStatus(int vectors, int stories);

  /// No description provided for @kbVectorNone.
  ///
  /// In en, this message translates to:
  /// **'No vectors yet'**
  String get kbVectorNone;

  /// No description provided for @kbVectorPending.
  ///
  /// In en, this message translates to:
  /// **'To generate: {stories} stories, about {chunks} chunks, about {tokens}×10k tokens'**
  String kbVectorPending(int stories, int chunks, String tokens);

  /// No description provided for @kbVectorCost.
  ///
  /// In en, this message translates to:
  /// **'About ¥{yuan} at Bailian\'s price (an estimate only; your provider\'s bill decides, and other providers charge differently: convert from the token count)'**
  String kbVectorCost(String yuan);

  /// No description provided for @kbVectorUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Every story has vectors; nothing to update.'**
  String get kbVectorUpToDate;

  /// No description provided for @kbVectorFirstBuild.
  ///
  /// In en, this message translates to:
  /// **'This generates vectors for all stories, which costs and takes far more than an incremental update.'**
  String get kbVectorFirstBuild;

  /// No description provided for @kbVectorConfigure.
  ///
  /// In en, this message translates to:
  /// **'Configure the vector service first: Settings → API settings → Vectors (default Bailian {model}, {dims} dimensions, needs that service\'s API key).'**
  String kbVectorConfigure(String model, int dims);

  /// No description provided for @kbVectorMismatch.
  ///
  /// In en, this message translates to:
  /// **'Existing vectors come from {have}, the configuration says {want}. They cannot be mixed: set the vector settings back to {have}.'**
  String kbVectorMismatch(String have, String want);

  /// No description provided for @kbVectorStart.
  ///
  /// In en, this message translates to:
  /// **'Generate vectors'**
  String get kbVectorStart;

  /// No description provided for @kbVectorRefresh.
  ///
  /// In en, this message translates to:
  /// **'Recalculate'**
  String get kbVectorRefresh;

  /// No description provided for @kbVectorRunning.
  ///
  /// In en, this message translates to:
  /// **'Generating vectors: {done} / {total} stories ({chunks} chunks)'**
  String kbVectorRunning(int done, int total, int chunks);

  /// No description provided for @kbVectorDone.
  ///
  /// In en, this message translates to:
  /// **'Generated {chunks} chunks; the provider counted {tokens} tokens.'**
  String kbVectorDone(int chunks, int tokens);

  /// No description provided for @kbVectorCancel.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get kbVectorCancel;

  /// No description provided for @kbVectorConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Generate vectors for all stories?'**
  String get kbVectorConfirmTitle;

  /// No description provided for @kbVectorConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'About {stories} stories, {chunks} chunks, {tokens}×10k tokens. This costs money at your vector service. You can stop any time; finished stories are kept.'**
  String kbVectorConfirmBody(int stories, int chunks, String tokens);

  /// No description provided for @kbVectorConfirm.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get kbVectorConfirm;

  /// No description provided for @lineKindSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Caption'**
  String get lineKindSubtitle;

  /// No description provided for @lineKindDocument.
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get lineKindDocument;

  /// No description provided for @lineKindChoice.
  ///
  /// In en, this message translates to:
  /// **'Choice'**
  String get lineKindChoice;

  /// No description provided for @lineKindTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get lineKindTitle;

  /// No description provided for @lineKindTutorial.
  ///
  /// In en, this message translates to:
  /// **'Tutorial'**
  String get lineKindTutorial;

  /// No description provided for @aiAnswerOptions.
  ///
  /// In en, this message translates to:
  /// **'Answer options'**
  String get aiAnswerOptions;

  /// No description provided for @aiAnswerReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get aiAnswerReview;

  /// No description provided for @aiAnswerReviewHint.
  ///
  /// In en, this message translates to:
  /// **'Another model reads the draft and raises questions, checked in the text before the final answer (slower)'**
  String get aiAnswerReviewHint;

  /// No description provided for @aiAnswerDigest.
  ///
  /// In en, this message translates to:
  /// **'Digest'**
  String get aiAnswerDigest;

  /// No description provided for @aiAnswerDigestHint.
  ///
  /// In en, this message translates to:
  /// **'Long answers open with a few summary paragraphs, the details folded below (one more call)'**
  String get aiAnswerDigestHint;

  /// No description provided for @librarySearchIn.
  ///
  /// In en, this message translates to:
  /// **'In “{name}”'**
  String librarySearchIn(String name);

  /// No description provided for @librarySearchEverywhere.
  ///
  /// In en, this message translates to:
  /// **'Search the whole library'**
  String get librarySearchEverywhere;

  /// No description provided for @librarySearchNoNameMatch.
  ///
  /// In en, this message translates to:
  /// **'Nothing is named “{query}”; below are close names and texts that contain it'**
  String librarySearchNoNameMatch(String query);

  /// No description provided for @librarySearchSimilar.
  ///
  /// In en, this message translates to:
  /// **'Close names'**
  String get librarySearchSimilar;

  /// No description provided for @librarySearchMentions.
  ///
  /// In en, this message translates to:
  /// **'In the text'**
  String get librarySearchMentions;

  /// No description provided for @librarySearchNoMentions.
  ///
  /// In en, this message translates to:
  /// **'Not found in the texts'**
  String get librarySearchNoMentions;

  /// No description provided for @librarySearchInText.
  ///
  /// In en, this message translates to:
  /// **'Search the texts for “{query}”'**
  String librarySearchInText(String query);

  /// No description provided for @librarySearchSemantic.
  ///
  /// In en, this message translates to:
  /// **'Find stories by meaning'**
  String get librarySearchSemantic;

  /// No description provided for @librarySearchSemanticTitle.
  ///
  /// In en, this message translates to:
  /// **'Stories close in meaning'**
  String get librarySearchSemanticTitle;

  /// No description provided for @librarySearchSemanticNeedsService.
  ///
  /// In en, this message translates to:
  /// **'Set up an embedding service to find stories by meaning (Settings → API settings → Embedding)'**
  String get librarySearchSemanticNeedsService;

  /// No description provided for @librarySearchSemanticNoVectors.
  ///
  /// In en, this message translates to:
  /// **'This knowledge base has no story vectors (they can be made on the knowledge base page)'**
  String get librarySearchSemanticNoVectors;

  /// No description provided for @librarySearchSemanticOtherModel.
  ///
  /// In en, this message translates to:
  /// **'The knowledge base’s vectors were made with another embedding model than the one configured'**
  String get librarySearchSemanticOtherModel;

  /// No description provided for @librarySearchSemanticFailed.
  ///
  /// In en, this message translates to:
  /// **'The embedding service request failed'**
  String get librarySearchSemanticFailed;

  /// No description provided for @librarySearchMatchCount.
  ///
  /// In en, this message translates to:
  /// **'{n} matches'**
  String librarySearchMatchCount(int n);

  /// No description provided for @librarySearchFurther.
  ///
  /// In en, this message translates to:
  /// **'Search for “{query}” (close names and texts too)'**
  String librarySearchFurther(String query);

  /// No description provided for @storyReaderFindHint.
  ///
  /// In en, this message translates to:
  /// **'Find in this story'**
  String get storyReaderFindHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}

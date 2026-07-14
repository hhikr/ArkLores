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
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
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

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsThemeArk.
  ///
  /// In en, this message translates to:
  /// **'Tactical Archive'**
  String get settingsThemeArk;

  /// No description provided for @settingsThemeEndfield.
  ///
  /// In en, this message translates to:
  /// **'Holographic Projection'**
  String get settingsThemeEndfield;

  /// No description provided for @settingsAiServices.
  ///
  /// In en, this message translates to:
  /// **'AI Services'**
  String get settingsAiServices;

  /// No description provided for @settingsApiSettings.
  ///
  /// In en, this message translates to:
  /// **'API Settings'**
  String get settingsApiSettings;

  /// No description provided for @settingsApiSettingsDesc.
  ///
  /// In en, this message translates to:
  /// **'Configure Chat & Embedding providers'**
  String get settingsApiSettingsDesc;

  /// No description provided for @settingsKnowledgeBase.
  ///
  /// In en, this message translates to:
  /// **'Knowledge Base Management'**
  String get settingsKnowledgeBase;

  /// No description provided for @settingsKnowledgeBaseDesc.
  ///
  /// In en, this message translates to:
  /// **'Manage Wiki index, view stats, update knowledge base'**
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
  /// **'Used for AI conversations (Fact Check, Summary, Roleplay).'**
  String get apiSettingsChatDesc;

  /// No description provided for @apiSettingsEmbedSection.
  ///
  /// In en, this message translates to:
  /// **'Embedding API'**
  String get apiSettingsEmbedSection;

  /// No description provided for @apiSettingsEmbedDesc.
  ///
  /// In en, this message translates to:
  /// **'Used for knowledge base indexing (Wiki, books). Can use a different provider from Chat.'**
  String get apiSettingsEmbedDesc;

  /// No description provided for @apiSettingsUseSameProvider.
  ///
  /// In en, this message translates to:
  /// **'Use same provider as Chat'**
  String get apiSettingsUseSameProvider;

  /// No description provided for @apiSettingsEmbedFallbackNote.
  ///
  /// In en, this message translates to:
  /// **'Embedding will use the Chat API config above. Note: DeepSeek does not support embeddings — if you use DeepSeek for chat, uncheck this to configure a separate embedding provider.'**
  String get apiSettingsEmbedFallbackNote;

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

  /// No description provided for @kbEmbedding.
  ///
  /// In en, this message translates to:
  /// **'Embedding {title} ({count} chunks)...'**
  String kbEmbedding(Object count, Object title);

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
  /// **'Import PDF or TXT files to build your personal lore reference library.'**
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
  /// **'Remove \"{name}\" and all its chunks from the knowledge base?'**
  String materialsDeleteConfirm(Object name);

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

  /// No description provided for @importEmbedding.
  ///
  /// In en, this message translates to:
  /// **'Generating embeddings...'**
  String get importEmbedding;

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
  /// **'AI Chat'**
  String get aiChatTitle;

  /// No description provided for @aiChatSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fact Check · Summary · Roleplay'**
  String get aiChatSubtitle;

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

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to ArkLores'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeDesc.
  ///
  /// In en, this message translates to:
  /// **'Your AI-enhanced companion for exploring Arknights and Endfield lore.\n\n• Browse PRTS & Endfield Wikis\n• AI-powered fact checking & summaries\n• Import your lore books\n• Immersive character roleplay'**
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
  /// **'ArkLores uses your own AI API key.\nConfigure at least a Chat provider now;\nEmbedding can be set up later in Settings.'**
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
  /// **'You\'re ready to explore the world of Arknights and Endfield.\n\nVisit Settings > API Settings to configure\na separate Embedding provider if needed,\nor start browsing the Wiki!'**
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

  /// No description provided for @aiTabRoleplay.
  ///
  /// In en, this message translates to:
  /// **'Roleplay'**
  String get aiTabRoleplay;

  /// No description provided for @aiInputPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Enter lore query or claim...'**
  String get aiInputPlaceholder;

  /// No description provided for @aiSummaryInputPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Enter character, event, location or faction to summarize...'**
  String get aiSummaryInputPlaceholder;

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
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
    case 'zh': return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}

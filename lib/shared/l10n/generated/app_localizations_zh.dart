import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'ArkLores';

  @override
  String get navWiki => 'Wiki';

  @override
  String get navAI => 'AI';

  @override
  String get navMaterials => '资料';

  @override
  String get navSettings => '设置';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsTheme => '主题';

  @override
  String get settingsThemeArk => '战术档案';

  @override
  String get settingsThemeEndfield => '全息投影';

  @override
  String get settingsAiServices => 'AI 服务';

  @override
  String get settingsApiSettings => 'API 设置';

  @override
  String get settingsApiSettingsDesc => '配置对话服务提供商';

  @override
  String get settingsKnowledgeBase => '知识库管理';

  @override
  String get settingsKnowledgeBaseDesc => '管理 GameData 知识库';

  @override
  String get apiSettingsTitle => 'API 设置';

  @override
  String get apiSettingsChatSection => '对话 API';

  @override
  String get apiSettingsChatDesc => '用于 AI 对话（事实核查、梗概生成、角色扮演）。';

  @override
  String get apiSettingsUseSameProvider => '使用与对话相同的提供商';

  @override
  String get apiSettingsLabelBaseUrl => '接口地址';

  @override
  String get apiSettingsLabelApiKey => 'API 密钥';

  @override
  String get apiSettingsLabelModel => '模型';

  @override
  String get apiSettingsSave => '保存配置';

  @override
  String get apiSettingsSaved => '✓ 已保存';

  @override
  String get kbTitle => '知识库';

  @override
  String get kbConfigWarning => '请先在设置中配置 API 密钥，再建立知识库。';

  @override
  String get kbIndexOverview => '索引概览';

  @override
  String get kbTotalChunks => '总片段数';

  @override
  String get kbWikiChunks => 'Wiki 片段';

  @override
  String get kbBookChunks => '书籍片段';

  @override
  String get kbBooks => '书籍数';

  @override
  String get kbWikiSources => 'Wiki 来源';

  @override
  String get kbUpdate => '更新';

  @override
  String get kbIndexing => '索引中...';

  @override
  String kbStartingCrawl(Object site) {
    return '开始爬取 $site...';
  }

  @override
  String kbCrawlingPages(Object count, Object site) {
    return '正在爬取 $site：$count 页...';
  }

  @override
  String kbCompleted(Object chunks, Object pages) {
    return '完成：来自 $pages 个页面的 $chunks 个片段。';
  }

  @override
  String kbFailed(Object error) {
    return '索引失败：$error';
  }

  @override
  String get kbEngineNative => '搜索引擎：sqlite-vec（原生）';

  @override
  String get kbEngineFallback => '搜索引擎：纯 Dart（回退）';

  @override
  String get materialsTitle => '资料';

  @override
  String get materialsWarning => '⚠️ 资料内容属用户导入，可能包含非官方解读、翻译误差或个人总结。AI 将小心引用并以 Wiki 内容为优先参考。';

  @override
  String get materialsNoBooks => '还没有书籍';

  @override
  String get materialsEmptyDesc => '导入 PDF 或 TXT 文件来构建你的个人剧情资料库。';

  @override
  String get materialsNoApiKeyHint => '请在设置中配置 API 密钥以启用导入功能。';

  @override
  String get materialsImportButton => '导入书籍';

  @override
  String materialsLoadFailed(Object error) {
    return '加载书籍失败：$error';
  }

  @override
  String get materialsEditTitle => '编辑显示名称';

  @override
  String get materialsEditHint => '输入显示名称';

  @override
  String get materialsCancel => '取消';

  @override
  String get materialsSave => '保存';

  @override
  String get materialsDeleteTitle => '删除书籍';

  @override
  String materialsDeleteConfirm(Object name) {
    return '确定要删除 \"$name\" 及其所有知识库片段吗？';
  }

  @override
  String get materialsDelete => '删除';

  @override
  String materialsImportFailed(Object error) {
    return '导入失败：$error';
  }

  @override
  String materialsChunks(Object count) {
    return '$count 个片段';
  }

  @override
  String get materialsJustNow => '刚刚';

  @override
  String materialsMinutesAgo(Object n) {
    return '$n 分钟前';
  }

  @override
  String materialsHoursAgo(Object n) {
    return '$n 小时前';
  }

  @override
  String materialsDaysAgo(Object n) {
    return '$n 天前';
  }

  @override
  String importReading(Object file) {
    return '正在读取 $file';
  }

  @override
  String get importChunking => '正在分块...';

  @override
  String get importStoring => '正在保存到知识库...';

  @override
  String get importDone => '导入完成';

  @override
  String get importFailed => '导入失败';

  @override
  String get importErrorOccurred => '导入过程中发生错误。';

  @override
  String get importDismiss => '关闭';

  @override
  String get aiChatTitle => 'AI 对话';

  @override
  String get aiChatSubtitle => '事实核查 · 梗概生成 · 角色扮演';

  @override
  String get aiChatComingSoon => '即将在 v0.4 推出';

  @override
  String get aiChatComingSoonDesc => '三种 AI 代理模式：带引用卡片和流式 Markdown 输出。';

  @override
  String get wikiTabPrts => 'PRTS Wiki';

  @override
  String get wikiTabEndfield => '终末地 Wiki';

  @override
  String get bookmarksTitle => '书签';

  @override
  String bookmarksLoadFailed(Object error) {
    return '加载书签失败：$error';
  }

  @override
  String get bookmarksEmpty => '还没有书签';

  @override
  String get bookmarksEmptyDesc => '保存你想稍后回看的 Wiki 页面。';

  @override
  String get citationWiki => 'Wiki';

  @override
  String get citationBook => '书籍';

  @override
  String get citationViewInWiki => '在 Wiki 中查看';

  @override
  String get onboardingSkip => '跳过';

  @override
  String get onboardingWelcomeTitle => '欢迎使用 ArkLores';

  @override
  String get onboardingWelcomeDesc => '专为明日方舟与终末地剧情爱好者打造的 AI 增强阅读工具。\n\n• 浏览 PRTS 与终末地 Wiki\n• AI 事实核查与梗概生成\n• 导入你的剧情书籍\n• 沉浸式角色扮演对话';

  @override
  String get onboardingGetStarted => '开始使用';

  @override
  String get onboardingApiTitle => '配置对话 API';

  @override
  String get onboardingApiDesc => 'ArkLores 使用你自己的 AI API 密钥。\n请配置一个对话提供商以使用 AI 功能。';

  @override
  String get onboardingSaveContinue => '保存并继续';

  @override
  String get onboardingConfigureLater => '稍后配置';

  @override
  String get onboardingDoneTitle => '准备就绪！';

  @override
  String get onboardingDoneDesc => '你已经准备好探索明日方舟与终末地的世界了。\n\n可前往设置安装 GameData 知识库，\n或直接开始浏览 Wiki！';

  @override
  String get onboardingStartExploring => '开始探索';

  @override
  String get settingsHelpGuide => '帮助与引导';

  @override
  String get settingsShowOnboarding => '新用户导览';

  @override
  String get settingsShowOnboardingDesc => '重新进行首次启动导览与配置';

  @override
  String get aiTabFactCheck => '事实核查';

  @override
  String get aiTabSummary => '剧情梗概';

  @override
  String get aiTabRoleplay => '角色扮演';

  @override
  String get aiFactCheckSource => '证据范围：仅限已安装的中文 GameData';

  @override
  String get aiFactCheckEmpty => '输入一条设定或剧情说法，使用本地 GameData 证据进行核查。';

  @override
  String get aiFactCheckInputPlaceholder => '输入要核查的说法…';

  @override
  String get aiVerdictSupported => '支持';

  @override
  String get aiVerdictRefuted => '反驳';

  @override
  String get aiVerdictUncertain => '存疑';

  @override
  String get aiVerdictUnavailable => '无法确认';

  @override
  String aiVerdictSemantics(String verdict) {
    return '事实核查结论：$verdict';
  }

  @override
  String aiEvidenceTitle(int count) {
    return 'GameData 证据（$count）';
  }

  @override
  String get aiRetry => '重试';

  @override
  String get aiCancel => '取消';

  @override
  String get aiSend => '发送';

  @override
  String get aiInputPlaceholder => '输入剧情内容或设定...';

  @override
  String get aiSummaryInputPlaceholder => '输入人物、事件、地点或组织名称以生成梗概...';

  @override
  String get aiSettingsRequired => '请先在设置中配置对话 API 密钥以使用 AI 功能。';

  @override
  String get aiSettingsGoTo => '去设置';

  @override
  String get aiClearHistory => '清空对话';

  @override
  String get aiClearHistoryConfirm => '确定要清空当前的对话历史吗？';

  @override
  String get aiClearConfirmBtn => '清空';
}

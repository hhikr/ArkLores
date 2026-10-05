// ignore: unused_import
import 'package:intl/intl.dart' as intl;
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
  String get settingsSystemCode => 'ARKLORES / 系统设置';

  @override
  String get settingsTheme => '主题';

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsThemeArk => '夜间模式';

  @override
  String get settingsThemeEndfield => '日间模式';

  @override
  String get settingsThemeArkShort => '夜间';

  @override
  String get settingsThemeEndfieldShort => '日间';

  @override
  String get localeEnglishShort => 'EN';

  @override
  String get localeChineseShort => '中文';

  @override
  String get settingsProfile => '资料设置';

  @override
  String get settingsProfileDesc => '设置剧情里怎样称呼你。';

  @override
  String get settingsProfileSectionCode => 'PROFILE';

  @override
  String get profileNicknameLabel => '称呼';

  @override
  String get profileNicknameHelp =>
      '剧情文本里博士的名字是占位符，阅读时显示为这里填写的称呼（留空显示“博士”）。不会改动知识库。';

  @override
  String get profileNicknameDefault => '博士';

  @override
  String get settingsAiServices => 'AI 服务';

  @override
  String get settingsAiSectionCode => 'AI SERVICE';

  @override
  String get settingsApiSettings => 'API 设置';

  @override
  String get settingsApiSettingsDesc => '配置对话服务提供商';

  @override
  String get settingsSessionLogs => '保存 AI 对话记录';

  @override
  String get settingsSessionLogsDesc =>
      '完整记录每次 AI 对话（含模式选择、自动路由决策、完整推理过程与检索原文）到手机存储的 chat_sessions 目录，用于「对话记录」查看与恢复；仅保存在本机，可在 app 内或文件管理器中删除。';

  @override
  String get settingsKnowledgeBase => '知识库管理';

  @override
  String get settingsKnowledgeSectionCode => 'KNOWLEDGE BASE';

  @override
  String get settingsKnowledgeBaseDesc => '管理 GameData 知识库';

  @override
  String get apiSettingsTitle => 'API 设置';

  @override
  String get apiSettingsChatSection => '对话 API';

  @override
  String get apiSettingsChatDesc => '用于 AI 对话（事实核查、梗概生成、角色扮演）。';

  @override
  String get apiSettingsEmbeddingSection => '向量 API（可选）';

  @override
  String get apiSettingsEmbeddingDesc =>
      '用于剧情调查的语义原文召回。模型需与已安装知识库的向量一致（如阿里云百炼 qwen3.7-text-embedding）。不填 Key 时只用关键词检索。';

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
  String get kbUpToDate => '已是最新';

  @override
  String get kbRedownload => '重新下载';

  @override
  String get kbRedownloadTitle => '重新下载知识库？';

  @override
  String get kbRedownloadBody =>
      '当前已是最新版本。重新下载会再下载约 185 MB 并重建数据库（需约 1 GB 空闲空间），一般没有必要。';

  @override
  String get kbRedownloadConfirm => '重新下载';

  @override
  String get kbCancel => '取消';

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
  String get materialsWarning =>
      '⚠️ 资料内容属用户导入，可能包含非官方解读、翻译误差或个人总结。AI 将小心引用并以 Wiki 内容为优先参考。';

  @override
  String get materialsNoBooks => '还没有书籍';

  @override
  String get materialsEmptyDesc =>
      '把想留的文字放在这里：设定摘录、笔记、考据都可以。它们只保存在这台设备上，不会进入知识库。';

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
  String get materialsDeleteConfirm => '删除这份资料？';

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
  String get aiChatTitle => '剧情智囊';

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
  String get wikiSendToAi => '转交给 AI';

  @override
  String get wikiSendToAiDesc => '选中的 Wiki 文本只作为阅读上下文；事实声明仍会用 GameData 单独核验。';

  @override
  String get wikiSendToSummaryDesc => '根据页面和选中文字生成梗概';

  @override
  String get wikiSendToFactCheckDesc => '把选中文字作为待核查主张';

  @override
  String get wikiReaderMode => '阅读模式';

  @override
  String get wikiReaderFontSmaller => '缩小文字';

  @override
  String get wikiReaderFontLarger => '放大文字';

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
  String get onboardingNotNow => '以后再说';

  @override
  String get onboardingWelcomeTitle => '欢迎使用 ArkLores';

  @override
  String get onboardingWelcomeDesc =>
      '专为明日方舟与终末地剧情爱好者打造的 AI 增强阅读工具。\n\n• 浏览 PRTS 与终末地 Wiki\n• AI 事实核查与梗概生成\n• 导入你的剧情书籍\n• 沉浸式角色扮演对话';

  @override
  String get onboardingGetStarted => '开始使用';

  @override
  String get onboardingApiTitle => '配置对话 API';

  @override
  String get onboardingApiDesc =>
      'ArkLores 使用你自己的 AI API 密钥。\n请配置一个对话提供商以使用 AI 功能。';

  @override
  String get onboardingSaveContinue => '保存并继续';

  @override
  String get onboardingConfigureLater => '稍后配置';

  @override
  String get onboardingDoneTitle => '准备就绪！';

  @override
  String get onboardingDoneDesc =>
      '你已经准备好探索明日方舟与终末地的世界了。\n\n可前往设置安装 GameData 知识库，\n或直接开始浏览 Wiki！';

  @override
  String get onboardingStartExploring => '开始探索';

  @override
  String get settingsHelpGuide => '帮助与引导';

  @override
  String get settingsHelpSectionCode => 'HELP & GUIDE';

  @override
  String get settingsVersionLabel => 'ARKLORES / 0.9 开发版';

  @override
  String get settingsShowOnboarding => '新用户导览';

  @override
  String get settingsShowOnboardingDesc => '重新进行首次启动导览与配置';

  @override
  String get aiTabAsk => 'AI 问答';

  @override
  String get aiAskSource => '仅基于已安装的 GameData 剧情原文回答';

  @override
  String get aiAskEmpty => '直接问任何剧情问题——人物经历、事件前因后果、某个说法是否属实，都可以。';

  @override
  String get aiInputExpand => '展开输入框';

  @override
  String get aiInputCollapse => '收起输入框';

  @override
  String get aiInputFullscreen => '全屏输入';

  @override
  String get aiInputExitFullscreen => '退出全屏';

  @override
  String get aiAskInputPlaceholder => '问任何剧情问题…';

  @override
  String get aiAskSuggestionAmiya => '阿米娅是什么人';

  @override
  String get aiAskSuggestionVerify => '阿米娅是罗德岛的公开领袖吗';

  @override
  String get aiAskSuggestionInvestigate => '整合运动是怎样成立的';

  @override
  String get aiAskError => '回答失败，请重试。';

  @override
  String get aiAskCanceled => '已取消本次回答。';

  @override
  String get aiTabFactCheck => '事实核查';

  @override
  String get aiTabSummary => '剧情梗概';

  @override
  String get aiTabRoleplay => '角色扮演';

  @override
  String get aiAnswerStatus => '回答状态';

  @override
  String get aiAnswerStatusAnswered => '已作答';

  @override
  String get aiAnswerStatusPartial => '部分作答（资料不足）';

  @override
  String get aiAnswerStatusNotCovered => '知识库未覆盖';

  @override
  String get aiInvestigationConfidence => '置信度';

  @override
  String aiCitationLine(int line) {
    return '第 $line 行';
  }

  @override
  String aiCitationLines(int start, int end) {
    return '第 $start–$end 行';
  }

  @override
  String aiAnswerDetails(int count) {
    return '详细经过 · $count 条';
  }

  @override
  String aiEvidenceSummary(int count, int stories) {
    return '证据 $count 处 · 来自 $stories 个故事';
  }

  @override
  String aiChapterCount(int count) {
    return '$count 处';
  }

  @override
  String get aiCitedRecord => '资料';

  @override
  String aiCitedRecords(int count) {
    return '其他资料 $count 条';
  }

  @override
  String get aiCitedLinesUnavailable => '原文暂不可用（知识库未安装或已更新）';

  @override
  String get aiStoryReaderTitle => '原文';

  @override
  String aiCitationSources(int count) {
    return '出处 $count';
  }

  @override
  String get aiStoryReaderJumpBack => '回到引用处';

  @override
  String aiStoryReaderCited(String range) {
    return '引用 · $range';
  }

  @override
  String get aiStoryReaderEnd => '本章完';

  @override
  String get libraryTabRead => '阅读';

  @override
  String get libraryTabMine => '我的资料';

  @override
  String get librarySearchTitle => '搜索';

  @override
  String get librarySearchHint => '搜索章节、条目、关卡代号';

  @override
  String get libraryContinue => '继续阅读';

  @override
  String get libraryShelves => '书架';

  @override
  String get libraryViewAll => '全部';

  @override
  String get shelfMain => '主线';

  @override
  String get shelfActivity => '其他活动';

  @override
  String get shelfSideStory => 'SideStory';

  @override
  String get shelfMiniStory => '故事集';

  @override
  String get shelfBranchline => '插曲';

  @override
  String get shelfMemory => '干员';

  @override
  String get shelfRoguelike => '集成战略';

  @override
  String get shelfSandbox => '生息演算';

  @override
  String get shelfRetro => '复刻';

  @override
  String get shelfCodex => '图鉴';

  @override
  String get libraryOperatorRecords => '干员密录';

  @override
  String get libraryOperatorProfile => '干员档案';

  @override
  String get libraryAllEntries => '全部';

  @override
  String libraryCountCollections(int n) {
    return '$n 项';
  }

  @override
  String libraryCountStories(int n) {
    return '$n 个故事';
  }

  @override
  String libraryCountEntries(int n) {
    return '$n 条';
  }

  @override
  String get libraryNotInstalledTitle => '还没有知识库';

  @override
  String get libraryNotInstalledDesc => '到 设置 → 知识库 下载或构建后，这里会出现可以阅读的剧情和资料。';

  @override
  String get libraryOldSchemaTitle => '知识库需要更新';

  @override
  String get libraryOldSchemaDesc =>
      '当前的知识库是旧版本，没有按故事集分好的目录。到 设置 → 知识库 更新后即可阅读。';

  @override
  String get libraryEmpty => '这里还没有内容';

  @override
  String get libraryStories => '剧情';

  @override
  String get libraryOtherSections => '相关资料';

  @override
  String get libraryParts => '解锁的故事';

  @override
  String get libraryLeftoverStories => '其他剧情';

  @override
  String get libraryFilterHint => '在列表中筛选';

  @override
  String libraryProgress(int percent) {
    return '已读 $percent%';
  }

  @override
  String get libraryFinished => '已读完';

  @override
  String libraryRelease(String month) {
    return '上线 $month';
  }

  @override
  String get libraryRelated => '关联';

  @override
  String get libraryNoText => '这一条没有文字内容';

  @override
  String get libraryNoResults => '没有找到相关内容';

  @override
  String get librarySearchCollections => '故事集与主题';

  @override
  String get librarySearchEntries => '条目';

  @override
  String get storyReaderNext => '下一章';

  @override
  String get storyReaderPrevious => '上一章';

  @override
  String storyReaderResumed(int line) {
    return '继续阅读 · 第 $line 行';
  }

  @override
  String get storyReaderSynopsis => '官方梗概';

  @override
  String get materialsEmptyTitle => '还没有自己的资料';

  @override
  String get materialsNew => '新建';

  @override
  String get materialsPaste => '从剪贴板导入';

  @override
  String get materialsTitleHint => '标题（可留空）';

  @override
  String get materialsBodyHint => '正文';

  @override
  String get materialsEdit => '编辑';

  @override
  String materialsChars(int n) {
    return '$n 字';
  }

  @override
  String get materialsClipboardEmpty => '剪贴板里没有文字';

  @override
  String get materialsDiscard => '放弃未保存的修改？';

  @override
  String get materialsDiscardAction => '放弃';

  @override
  String get materialsAskAbout => '用它提问';

  @override
  String get readingHistoryTitle => '最近阅读';

  @override
  String get readingHistoryEmpty => '还没有阅读记录。在回答的证据链里点开原文后，会记在这里。';

  @override
  String readingHistoryPage(Object page, Object pages) {
    return '第 $page / $pages 页';
  }

  @override
  String get readingHistoryClear => '清空';

  @override
  String get readingHistoryClearConfirm => '清空全部阅读记录？';

  @override
  String get readingHistoryRemove => '删除这条记录';

  @override
  String readingHistoryLine(int line) {
    return '第 $line 行';
  }

  @override
  String get aiStoryReaderMoved => '原文有变动，已定位到大致位置';

  @override
  String get aiMoreActions => '更多';

  @override
  String get aiThinkingProcess => '思考过程';

  @override
  String get aiDeepThinking => '深度思考';

  @override
  String get aiDeepThinkingTooltip => '写答案前先思考（较慢，耗更多 token）';

  @override
  String get aiScrollToBottom => '回到底部';

  @override
  String get aiInvestigationCoverage => '已读范围';

  @override
  String get aiInvestigationRead => '精读';

  @override
  String get aiInvestigationMapped => '画像';

  @override
  String get aiInvestigationSkipped => '未读';

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
  String get aiEvidenceSection => '章节';

  @override
  String get aiEvidenceContentType => '内容类型';

  @override
  String get aiEvidenceSourcePath => '来源路径';

  @override
  String get aiEvidenceRawId => '原始 ID';

  @override
  String get aiEvidenceRetrievalType => '检索类型';

  @override
  String get aiEvidenceRankingReason => '排序原因';

  @override
  String get aiEvidenceTrustNote => '可信度说明';

  @override
  String get aiCoverageDirect => '直接候选证据';

  @override
  String get aiCoverageRetrieved => '检索上下文';

  @override
  String aiEvidenceSemantics(String title, String coverage) {
    return 'GameData 证据：$title；覆盖度：$coverage';
  }

  @override
  String get aiThinking => '正在思考…';

  @override
  String get aiReasoning => '正在推理…';

  @override
  String get aiProcessing => '正在处理…';

  @override
  String get aiReasoningComplete => '推理完成';

  @override
  String aiUsingTool(String tool) {
    return '正在使用工具：$tool';
  }

  @override
  String aiStepsStatus(String status, int count) {
    return '$status（$count 步）';
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
  String get aiSettingsRequired => '请先在设置中配置对话 API 密钥以使用 AI 功能。';

  @override
  String get aiSettingsGoTo => '去设置';

  @override
  String get aiClearHistory => '清空对话';

  @override
  String get aiClearHistoryConfirm => '确定要清空当前的对话历史吗？';

  @override
  String get aiClearConfirmBtn => '清空';

  @override
  String get aiNewConversation => '新建对话';

  @override
  String get aiHistoryTitle => '对话记录';

  @override
  String get aiHistoryEmpty => '暂无对话记录。发送消息后会自动保存在本机的 chat_sessions 目录。';

  @override
  String get aiHistoryContinue => '继续对话';

  @override
  String get aiHistoryView => '查看';

  @override
  String get aiHistoryDelete => '删除';

  @override
  String get aiHistoryDeleteConfirm => '删除这条对话记录？此操作不可撤销。';

  @override
  String get aiHistoryCorrupt => '损坏的会话文件';

  @override
  String aiHistoryTurns(int count) {
    return '$count 轮对话';
  }

  @override
  String get aiRoleplayChoose => '选择角色';

  @override
  String get aiRoleplayChooseDesc => '角色会先解析到 GameData 中的稳定实体，再开始生成对话。';

  @override
  String get aiRoleplayCharacter => '角色名或别名';

  @override
  String get aiRoleplayScene => '场景设定（可选）';

  @override
  String get aiRoleplaySceneContext => '场景属于会话上下文，不是 GameData 证据';

  @override
  String get aiRoleplayStart => '解析角色并开始';

  @override
  String get aiRoleplayResolving => '正在解析…';

  @override
  String get aiRoleplayNoDatabase => '未安装中文 GameData 知识库，请先前往设置安装。';

  @override
  String get aiRoleplayNotFound => '当前 GameData 未找到该角色，请检查名称或别名。';

  @override
  String get aiRoleplayDisambiguate => '请选择对应的 GameData 实体';

  @override
  String get aiRoleplayContinue => '继续本地保存的会话';

  @override
  String get aiRoleplayRestart => '重新开始';

  @override
  String get aiRoleplayGeneratedNotice =>
      '角色事实依据 GameData 检索；对白与舞台说明均为 AI 生成内容，不是游戏官方台词。';

  @override
  String get aiRoleplayEmpty => '输入第一句话。首轮会先检索角色档案、语音、秘录、模组及相关任务剧情。';

  @override
  String get aiRoleplayInputPlaceholder => '与角色对话…';

  @override
  String get aiRoleplayError => '生成失败，请重试。';

  @override
  String get aiRoleplayCanceled => '已取消本次生成。';

  @override
  String get settingsAppIcon => '应用图标';

  @override
  String get settingsIconLightLabel => '白天图标';

  @override
  String get settingsIconDarkLabel => '夜间图标';

  @override
  String get settingsIconLightShort => '浅色';

  @override
  String get settingsIconDarkShort => '深色';

  @override
  String get settingsIconUnsupported => '当前平台暂不支持运行时切换图标，设置已保存。';

  @override
  String get settingsWikiSources => 'Wiki 来源';

  @override
  String get settingsWikiSourcesDesc => '修改内置 Wiki URL，添加自定义 Wiki 入口';

  @override
  String get wikiSourcesAddTitle => '添加 Wiki';

  @override
  String get wikiSourcesEditTitle => '编辑 Wiki';

  @override
  String get wikiSourcesNameLabel => '名称';

  @override
  String get wikiSourcesIconUrlLabel => '图标 URL（可选）';

  @override
  String get wikiSourcesEndfieldPreset => '终末地 Wiki 预设';

  @override
  String get wikiSourcesReset => '重置';

  @override
  String get wikiSourcesEdit => '编辑';

  @override
  String get wikiSourcesDelete => '删除';

  @override
  String get wikiSourcesCancel => '取消';

  @override
  String get wikiSourcesSave => '保存';

  @override
  String get wikiSourcesNameRequired => '请输入 Wiki 名称';

  @override
  String get wikiSourcesUrlRequired => '请输入有效 URL';

  @override
  String get kbStructuredTitle => 'GameData 结构化知识库';

  @override
  String get kbScopeDescription =>
      'AI 只使用中文 GameData 知识库作为证据：实体、别名、原始记录、剧情原文与检索索引，以及可选的剧情向量。Wiki 与导入资料不作为 AI 的证据来源。';

  @override
  String kbStatusError(String error) {
    return 'GameData 状态读取失败：$error';
  }

  @override
  String get kbInstalled => 'GameData 主知识库已安装';

  @override
  String get kbNoAssetUrl => '当前构建未配置 GameData release asset URL';

  @override
  String get kbErrorInvalidUrl => '无法解析下载地址。真机测试请确认手机能访问该 GitHub / 局域网 URL。';

  @override
  String kbConnecting(int attempt) {
    return '正在连接服务器…（第 $attempt 次尝试）';
  }

  @override
  String get kbVerifying => '正在校验文件…';

  @override
  String get kbInstalling => '正在解压并安装，约需一两分钟，请不要退出…';

  @override
  String get kbCancelDownload => '取消';

  @override
  String kbManualHint(String dir) {
    return '网络连不上时：用别的网络下载 Release 里的 arklores_gamedata_zh.db.gz，改名为 arklores_gamedata_zh.db.download.gz，放进 $dir，再点“下载”。';
  }

  @override
  String get kbErrorTimeout => '连接超时。请检查网络后重试，已下载的部分会保留。';

  @override
  String get kbErrorNetwork =>
      '网络连接中断（网络不稳定或暂时无法访问 GitHub）。已自动重试多次；已下载的部分会保留，稍后点“更新”会从断点继续。';

  @override
  String get kbErrorNotFound => '服务器上没有找到知识库文件（新版本可能尚未公开发布），请稍后再试。';

  @override
  String get kbErrorChecksum => 'GameData DB 校验失败，文件可能损坏或 SHA256 与构建参数不一致。';

  @override
  String kbDownloadFailed(String error) {
    return '下载 GameData 主知识库失败：$error';
  }

  @override
  String get kbNotInstalled => '未安装';

  @override
  String get kbDevAssetHint => '下载官方发布的知识库（压缩包下载后会解压，请预留约 1 GB 空闲空间）。';

  @override
  String get kbUpdateAvailable => '有新版官方知识库，点“更新”下载（请预留约 1 GB 空闲空间）。';

  @override
  String get kbDownloading => '下载中';

  @override
  String get kbDownload => '下载';

  @override
  String get kbStatEntities => '实体';

  @override
  String get kbStatRecords => '原始记录';

  @override
  String get kbStatChunks => '文档片段';

  @override
  String get kbStatSourceCommit => '来源提交';

  @override
  String get kbBuildSectionTitle => '从源仓库构建';

  @override
  String get kbBuildSectionDesc =>
      '从 Kengxxiao/ArknightsGameData 拉取最新解包数据，在设备上按项目规约构建或增量更新知识库。需要网络；首次构建约需 1.5–2 GB 空闲空间。';

  @override
  String get kbBuildLatestCommit => '最新提交';

  @override
  String get kbBuildInstalledCommit => '已装提交';

  @override
  String get kbBuildCheckUpdates => '检查更新';

  @override
  String get kbBuildFromSource => '从源仓库构建';

  @override
  String get kbBuildCancel => '取消';

  @override
  String get kbBuildChecking => '正在检查上游提交…';

  @override
  String get kbBuildDownloadingZip => '正在下载源包（首次，较大）…';

  @override
  String get kbBuildDownloadingChanges => '正在下载增量变更文件…';

  @override
  String get kbBuildExtracting => '正在解压并筛选源数据…';

  @override
  String get kbBuildSwapping => '正在替换知识库…';

  @override
  String get kbBuildStageStart => '准备构建';

  @override
  String get kbBuildStageCopy => '复制旧库';

  @override
  String get kbBuildStageIncremental => '应用增量变更';

  @override
  String get kbBuildStageProfiles => '导入角色档案';

  @override
  String get kbBuildStageVoices => '导入语音';

  @override
  String get kbBuildStageStructured => '导入结构化表';

  @override
  String get kbBuildStageStories => '导入剧情';

  @override
  String get kbBuildStageCoverage => '构建实体覆盖层';

  @override
  String get kbBuildStageCoverageSpeakers => '正在补全说话人实体…';

  @override
  String get kbBuildStageCoverageTrie => '正在构建实体索引…';

  @override
  String get kbBuildStageCoverageScan => '正在扫描角色出场…';

  @override
  String get kbBuildStageCoverageRare => '正在统计稀有词…';

  @override
  String get kbBuildStageCoverageProfiles => '正在生成章节画像…';

  @override
  String get kbBuildStageFts => '重建全文索引';

  @override
  String get kbBuildIncrementalDone => '增量更新完成，知识库已替换。';

  @override
  String get kbBuildFullDone => '全量构建完成，知识库已替换。';

  @override
  String get kbBuildError => '构建失败';

  @override
  String get kbBuildTokenTitle => 'GitHub Token（可选）';

  @override
  String get kbBuildTokenDesc =>
      '填写 GitHub Personal Access Token（ghp_… 或 github_pat_…）可把 API 配额从 60 次/小时提升到 5000 次/小时，避免代理出口限流导致拉取失败。Token 仅存入系统安全存储，不会写入日志。';

  @override
  String get kbBuildTokenPlaceholder => '粘贴 GitHub Token';

  @override
  String get kbBuildTokenSave => '保存';

  @override
  String get kbBuildTokenSaved => 'GitHub Token 已保存。';

  @override
  String get kbBuildTokenCleared => 'GitHub Token 已清除。';

  @override
  String get kbBuildTokenSetHint => '已设置 GitHub Token（配额 5000/小时）';

  @override
  String get materialsPausedTitle => '用户资料导入暂未启用';

  @override
  String get materialsPausedDesc =>
      '旧版 PDF/TXT 导入链路已暂停。当前 AI 只使用 GameData 知识库作为证据。';

  @override
  String get wikiLoadFailed => 'Wiki 页面加载失败';

  @override
  String get wikiRetry => '重试';

  @override
  String get wikiErrorDns => '无法解析 Wiki 域名。请确认网络、DNS 或代理已对 ArkLores 生效后重试。';

  @override
  String get wikiErrorTimeout => '连接超时。请切换网络或确认代理/VPN 已连接后重试。';

  @override
  String get wikiErrorOffline => '设备当前没有可用网络连接。';

  @override
  String kbBuildChangeSummary(int stories, int tables, int levels) {
    return '上游有更新：剧情文件 $stories 个、数据表 $tables 个、关卡文件 $levels 个。';
  }

  @override
  String get kbBuildNoChanges => '上游没有与知识库相关的新变化，不需要更新。';

  @override
  String get kbBuildTooManyChanges =>
      '上游变化太多，无法逐个增量应用；点“构建”将改为完整重建（需要下载约 170 MB，耗时较长）。';

  @override
  String get kbBuildDownloadingContext => '正在下载更新所需的数据表…';

  @override
  String get kbBuildReportTitle => '本次更新的内容';

  @override
  String kbBuildReportStories(int added, int changed, int removed) {
    return '剧情文件：新增 $added 个，修改 $changed 个，删除 $removed 个';
  }

  @override
  String kbBuildReportEntries(String text) {
    return '条目变化：$text';
  }

  @override
  String kbBuildReportNew(String names) {
    return '新增集合：$names';
  }

  @override
  String kbBuildReportVectors(int count) {
    return '有 $count 条向量因所在剧情变化而失效，可在下面的“故事向量”里补上。';
  }

  @override
  String get kbVectorTitle => '故事向量（语义检索）';

  @override
  String get kbVectorDesc =>
      '向量让“找剧情”能按意思匹配，而不只是字面相同。没有向量也能用，只是这部分剧情只做关键词检索。向量只用来定位，答案的证据仍然是原文。';

  @override
  String kbVectorStatus(int vectors, int stories) {
    return '已有 $vectors 条向量，覆盖 $stories 个故事';
  }

  @override
  String get kbVectorNone => '还没有向量';

  @override
  String kbVectorPending(int stories, int chunks, String tokens) {
    return '待生成：$stories 个故事，约 $chunks 块，约 $tokens 万 token';
  }

  @override
  String kbVectorCost(String yuan) {
    return '按百炼价格估算约 ¥$yuan（只是估算，以服务商账单为准；其他服务商价格不同，请按 token 数换算）';
  }

  @override
  String get kbVectorUpToDate => '所有故事都有向量，不需要更新。';

  @override
  String get kbVectorFirstBuild => '这会为全部故事生成向量，费用和时间都比增量更新多得多。';

  @override
  String kbVectorConfigure(String model, int dims) {
    return '生成向量需要先配置向量服务：设置 → API 设置 → 向量（默认百炼 $model，维度 $dims，需要该服务的 API Key）。';
  }

  @override
  String kbVectorMismatch(String have, String want) {
    return '已有向量来自 $have，当前配置是 $want。两者不能混用，请把向量设置改回 $have。';
  }

  @override
  String get kbVectorStart => '生成向量';

  @override
  String get kbVectorRefresh => '重新计算';

  @override
  String kbVectorRunning(int done, int total, int chunks) {
    return '正在生成向量：$done / $total 个故事（$chunks 块）';
  }

  @override
  String kbVectorDone(int chunks, int tokens) {
    return '已生成 $chunks 块向量，服务商记录用了 $tokens token。';
  }

  @override
  String get kbVectorCancel => '停止';

  @override
  String get kbVectorConfirmTitle => '为全部故事生成向量？';

  @override
  String kbVectorConfirmBody(int stories, int chunks, String tokens) {
    return '预计 $stories 个故事、约 $chunks 块，约 $tokens 万 token。会产生向量服务的费用，可以随时停止，已完成的故事会保留。';
  }

  @override
  String get kbVectorConfirm => '开始';
}

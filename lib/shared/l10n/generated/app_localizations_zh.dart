// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

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
  String get settingsProfileSectionsOpen => '资料页的档案默认展开';

  @override
  String get settingsProfileSectionsOpenDesc =>
      '打开干员等资料页时，档案的各段全部展开；关掉后全部收起，点标题再展开。剧情开头的梗概始终默认收起。';

  @override
  String get settingsSkipUnreadOpens => '读到第一行不计入历史记录';

  @override
  String get settingsSkipUnreadOpensDesc =>
      '打开剧情后没有往下读、阅读位置停在打开时的那一行就离开，不记入最近阅读，也不改动已有记录的位置和先后。';

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
  String get apiSettingsChatDesc => '用于 AI 剧情问答。';

  @override
  String get apiSettingsEmbeddingSection => '向量 API（可选）';

  @override
  String get apiSettingsEmbeddingDesc =>
      '用于剧情调查的语义原文召回。模型需与已安装知识库的向量一致（如阿里云百炼 qwen3.7-text-embedding）。不填 Key 时只用关键词检索。';

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
  String get kbUpdate => '更新';

  @override
  String get kbUpToDate => '已是最新';

  @override
  String get kbRedownload => '重新下载';

  @override
  String get kbRedownloadTitle => '重新下载知识库？';

  @override
  String get kbRedownloadBody =>
      '当前已是最新版本。重新下载会再下载约 115 MB 并重建数据库（需约 1 GB 空闲空间），一般没有必要。';

  @override
  String get kbRedownloadConfirm => '重新下载';

  @override
  String get kbCancel => '取消';

  @override
  String get materialsTitle => '资料';

  @override
  String get materialsEmptyDesc =>
      '把想留的文字放在这里：设定摘录、笔记、考据都可以。它们只保存在这台设备上，不会进入知识库。';

  @override
  String get materialsCancel => '取消';

  @override
  String get materialsSave => '保存';

  @override
  String get materialsDeleteConfirm => '删除这份资料？';

  @override
  String get materialsDelete => '删除';

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
  String get onboardingNotNow => '以后再说';

  @override
  String get onboardingWelcomeTitle => '欢迎使用 ArkLores';

  @override
  String get onboardingWelcomeDesc =>
      '专为明日方舟与终末地剧情爱好者打造的 AI 增强阅读工具。\n\n• 浏览 PRTS 与终末地 Wiki\n• AI 剧情问答，答案附原文出处\n• 阅读剧情与游戏资料';

  @override
  String get onboardingGetStarted => '开始使用';

  @override
  String get onboardingApiTitle => '配置对话 API';

  @override
  String get onboardingApiDesc =>
      '问答用你自己的模型服务：请求从这台手机直接发给服务商，ArkLores 没有中转服务器。已经填过的会读进来，没改就直接下一步。';

  @override
  String get onboardingSaveContinue => '保存并继续';

  @override
  String get onboardingConfigureLater => '稍后配置';

  @override
  String get onboardingNext => '下一步';

  @override
  String get onboardingSkipGuide => '跳过导览';

  @override
  String get onboardingAppearanceTitle => '外观';

  @override
  String get onboardingAppearanceDesc => '主题和阅读字体，之后都能在设置里改。';

  @override
  String get onboardingProfileDesc => '剧情里对你的称呼会换成这个名字。';

  @override
  String get onboardingEmbeddingDesc => '向量服务用来按意思查找剧情原文。可以不填，但问答质量会显著下降。';

  @override
  String get onboardingKbTitle => '知识库';

  @override
  String get onboardingKbDesc =>
      '剧情原文和游戏资料都在知识库里，阅读和问答都靠它。每个游戏一个，下载后离线可用；已经下载的会显示出来。';

  @override
  String get onboardingWikiTitle => 'Wiki 站点';

  @override
  String get onboardingWikiDesc => 'Wiki 页显示这些站点，问答也会从这里查资料。可以改地址，或者加别的站点。';

  @override
  String get onboardingPortraitsDesc =>
      '阅读器里点说话人、问答里点名字，会显示那个人的剧情立绘。立绘包要另外下载，可以以后再在知识库页下。';

  @override
  String get onboardingReadingTitle => '怎么用';

  @override
  String get onboardingTipBarsTitle => '让开与唤回';

  @override
  String get onboardingTipBars => '在 Wiki、问答和阅读器里往下读，栏会让出屏幕。点一下空白处叫回来，再点一下让开。';

  @override
  String get onboardingTipReaderTitle => '阅读器';

  @override
  String get onboardingTipReader =>
      '按钮在屏幕下方，拇指够得着。点标题打开进度，拖动滑块跳到任意一行；放大镜在本篇里查找。';

  @override
  String get onboardingTipPortraitTitle => '立绘';

  @override
  String get onboardingTipPortrait =>
      '点说话人或答案里画了下划线的名字，先看旁边的小卡片；点“更多”打开能切换差分的大卡片。';

  @override
  String get onboardingTipSourcesTitle => '出处';

  @override
  String get onboardingTipSources => '答案的每一段都有出处。点开看原文，也能从那里跳到剧情里的那一行。';

  @override
  String get onboardingBackgroundTitle => '后台运行';

  @override
  String get onboardingDoneTitle => '准备就绪！';

  @override
  String get onboardingDoneDesc => '设置都可以在“设置”页再改，导览也能从那里重新打开。';

  @override
  String get onboardingStartExploring => '开始探索';

  @override
  String get backgroundAccessTitle => '让问答在后台继续';

  @override
  String get backgroundAccessBody =>
      'ArkLores 没有自己的服务器：调用模型、查知识库、整理答案都在这台手机上进行，一次问答要几分钟。切到别的 App 后，有些系统（比如 ColorOS）几秒内就会冻结后台的 App，连接随之中断，问答就停了。\n\n允许 ArkLores 不受电池优化限制后，它只在问答、下载知识库这类工作进行时在后台运行（通知栏会显示），做完就停。';

  @override
  String get backgroundAccessAllow => '去允许';

  @override
  String get backgroundAccessNotifications => '通知';

  @override
  String get backgroundAccessNotificationsDesc => '后台工作时在通知栏显示进度。';

  @override
  String get backgroundAccessBattery => '不受电池优化限制';

  @override
  String get backgroundAccessBatteryDesc => '切到别的 App 时，问答和下载不会被系统冻结。';

  @override
  String get backgroundAccessGranted => '已允许';

  @override
  String get backgroundAccessGrant => '允许';

  @override
  String get settingsVersion => '版本';

  @override
  String get settingsKnowledgeCategory => '知识库与资料';

  @override
  String get settingsHelpGuide => '帮助与引导';

  @override
  String get settingsHelpSectionCode => 'HELP & GUIDE';

  @override
  String settingsVersionLabel(String version) {
    return 'ARKLORES / $version';
  }

  @override
  String get settingsShowOnboarding => '新用户导览';

  @override
  String get settingsShowOnboardingDesc => '重新进行首次启动导览与配置';

  @override
  String get aiTabAsk => 'AI 问答';

  @override
  String get aiAskSource => '检索已安装的两个游戏的剧情原文，开着“Wiki 资料”时同时查 Wiki；答案里的每一点都有出处';

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
    return '详细经过 / $count 条';
  }

  @override
  String aiEvidenceSummary(int count, int stories) {
    return '证据 $count 处 / 来自 $stories 个故事';
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
  String get aiStoryReaderEnd => '本章完';

  @override
  String get libraryTabMine => '补充资料';

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
  String get shelfCodex => '图鉴';

  @override
  String get shelfOther => '其他';

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
  String get libraryFilterHint => '在列表中筛选';

  @override
  String get libraryFinished => '已读完';

  @override
  String get storyReaderBattleDialogue => '关卡内对话';

  @override
  String libraryReadTimes(int count) {
    return '读过 $count 次';
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
    return '继续阅读 / 第 $line 行';
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
  String get readingHistoryJumpTitle => '跳到第几页';

  @override
  String readingHistoryJumpHint(int pages) {
    return '1 – $pages';
  }

  @override
  String get readingHistoryJumpGo => '跳转';

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
  String aiWorkSummary(int calls, int reads) {
    return '查阅 $calls 次 / 读了 $reads 篇原文';
  }

  @override
  String aiWorkHits(int hits, int stories) {
    return '$hits 处 / $stories 篇';
  }

  @override
  String aiWorkRows(int count) {
    return '$count 条';
  }

  @override
  String aiWorkLines(int start, int end) {
    return '第 $start–$end 行';
  }

  @override
  String get aiWorkNone => '没有结果';

  @override
  String get aiWorkFailed => '出错';

  @override
  String get aiWorkPlanned => '拟定';

  @override
  String get aiWorkInContext => '已在上文';

  @override
  String get aiWorkNotRun => '未执行';

  @override
  String get aiWorkWikiDown => 'Wiki 超时';

  @override
  String aiWorkChars(int count) {
    return '$count 字';
  }

  @override
  String aiWorkRecord(String text) {
    return '记录：$text';
  }

  @override
  String aiWorkHelper(int number) {
    return '助手 $number';
  }

  @override
  String aiWorkStories(int count) {
    return '$count 篇';
  }

  @override
  String aiWorkGathered(int given, int located) {
    return '给了 $given 篇（定位到 $located 篇）';
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
  String get aiConversations => '对话';

  @override
  String get aiConversationsAnswering => '作答中';

  @override
  String aiConversationsAnsweringCount(int count) {
    return '$count 个对话正在作答';
  }

  @override
  String get aiConversationsRecent => '最近';

  @override
  String get aiConversationsAll => '查看全部';

  @override
  String get aiConversationsNone => '还没有对话。提问后会出现在这里。';

  @override
  String get aiNewConversation => '新建对话';

  @override
  String get aiHistoryTitle => '对话记录';

  @override
  String get aiHistoryEmpty =>
      '暂无对话记录。提问后对话会自动保存在本机的 chat_sessions 目录，点一条就能接着聊。';

  @override
  String get aiHistoryCurrent => '当前对话';

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
  String get kbArknightsTitle => '明日方舟知识库';

  @override
  String kbCountLines(String count) {
    return '剧情 $count 行';
  }

  @override
  String kbCountRecords(String count) {
    return '资料 $count 条';
  }

  @override
  String kbDataVersion(String commit) {
    return '数据版本 $commit';
  }

  @override
  String get kbLocalBuild => '本机更新';

  @override
  String get kbLocalBuildNote => '这份知识库在本机用游戏数据更新过，比随 App 发布的官方版本新。';

  @override
  String get kbBackToOfficial => '换回官方版本';

  @override
  String get kbBackToOfficialTitle => '换回官方知识库？';

  @override
  String get kbBackToOfficialBody =>
      '会重新下载随 App 发布的官方知识库（约 115 MB），替换本机更新过的这一份；其中较新的游戏内容会消失。';

  @override
  String get kbEndfieldSourceNote =>
      '终末地的数据从游戏客户端解包整理，随 App 发布更新，不能在设备上用游戏数据更新。';

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
  String kbManualHint(String file, String dir) {
    return '网络连不上时：用别的网络下载 Release 里的 $file.gz，改名为 $file.download.gz，放进 $dir，再点“下载”。';
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
  String get kbOriginOfficial => '官方发布';

  @override
  String get kbOriginLocal => '本机更新';

  @override
  String kbUpdateNewerData(String commit) {
    return '官方知识库的数据版本（$commit）比本机更新的这份新，点“更新”下载（请预留约 1 GB 空闲空间）。';
  }

  @override
  String get kbUpdateSameData =>
      '官方知识库已有同一数据版本，点“更新”换成官方的那份（向量齐全；请预留约 1 GB 空闲空间）。';

  @override
  String get kbBuildOfficialHasIt => '官方知识库已经是这个提交，请用上面的“更新”。';

  @override
  String get kbDownloading => '下载中';

  @override
  String get kbDownload => '下载';

  @override
  String get kbBuildSectionTitle => '用游戏数据更新';

  @override
  String get kbBuildSectionDesc =>
      '官方知识库随 App 发布，可能落后于游戏。这里从 Kengxxiao/ArknightsGameData 拉取最新的解包数据，在设备上把知识库更新到游戏的最新内容。需要网络。';

  @override
  String get kbBuildFullConfirm =>
      '这次只能完整重建：要下载约 170 MB、耗时较长，需要 1.5–2 GB 空闲空间；而且新库不带向量，现有的向量会丢失，要用自己的向量服务重新生成（有费用）。';

  @override
  String get kbBuildFullConfirmButton => '仍然完整重建';

  @override
  String get kbBuildLatestCommit => '最新提交';

  @override
  String get kbBuildInstalledCommit => '已装提交';

  @override
  String get kbBuildCheckUpdates => '检查更新';

  @override
  String get kbBuildFromSource => '拉取并更新';

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
  String get kbBuildStageCompact => '清理不再使用的数据…';

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
    return '有 $count 条向量因所在剧情变化而失效，可在上面的“语义检索”里补上。';
  }

  @override
  String get kbVectorTitle => '语义检索（向量）';

  @override
  String kbVectorSummary(int stories, int records) {
    return '剧情向量 $stories 条 / 资料向量 $records 条';
  }

  @override
  String get kbVectorComplete => '完整';

  @override
  String get kbVectorDesc =>
      '向量让检索能按意思匹配剧情和资料（档案、语音、各种描述），而不只是字面相同。没有向量也能用，只是这部分内容只做关键词检索。向量只用来定位，答案的证据仍然是原文。';

  @override
  String kbVectorRecordStatus(int vectors) {
    return '资料向量 $vectors 条';
  }

  @override
  String kbVectorPendingRecords(int chunks) {
    return '其中资料（档案、语音、描述等）$chunks 块';
  }

  @override
  String kbVectorRunningRecords(int done, int total) {
    return '正在生成资料向量：$done / $total 块';
  }

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
  String get kbVectorUpToDate => '所有故事和资料都有向量，不需要更新。';

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

  @override
  String get lineKindSubtitle => '字幕';

  @override
  String get lineKindDocument => '文档';

  @override
  String get lineKindChoice => '选项';

  @override
  String get lineKindTitle => '标题';

  @override
  String get lineKindTutorial => '教程';

  @override
  String get aiAnswerOptions => '回答选项';

  @override
  String get aiAnswerReview => '复核';

  @override
  String get aiAnswerReviewHint => '另一个模型以读者身份对这份回答提出疑问，回原文核实后在下面重新作答（多几次调用）';

  @override
  String get aiReviewRequest => '复核上面的回答';

  @override
  String get aiAnswerDigest => '提要';

  @override
  String get aiAnswerDigestHint => '在这份回答上方加几段提要，详细经过折叠在下面（多一次调用）';

  @override
  String get aiAnswerWiki => 'Wiki 资料';

  @override
  String get aiAnswerWikiShort => '联网查 PRTS / Warfarin，出处会写明';

  @override
  String get aiAnswerDelegate => '子助手';

  @override
  String get aiAnswerDelegateShort => '问题很宽时并行检索，花费明显增加';

  @override
  String get aiDeepThinkingShort => '写答案前先思考，更慢、更费 token';

  @override
  String get aiNoVectorWarning => '没有配置向量服务：只用关键词检索，问答质量会显著下降。可在设置里配置向量服务。';

  @override
  String get aiCitedWiki => 'Wiki';

  @override
  String aiCitedWikiPages(int count) {
    return 'Wiki 资料 $count 页';
  }

  @override
  String aiCitationParagraph(int n) {
    return '第 $n 段';
  }

  @override
  String aiCitationParagraphs(int start, int end) {
    return '第 $start–$end 段';
  }

  @override
  String get aiWikiOpen => '在 Wiki 中打开';

  @override
  String aiWikiVersion(String site, String date) {
    return '$site / $date 读取的版本';
  }

  @override
  String get aiWikiSecondary => 'Wiki 是社区编写的二手资料；与游戏原文不一致时以原文为准。';

  @override
  String get aiWikiPageUnavailable =>
      '这个页面版本没有保存在本机（可能是在别的设备上问的），可以在 Wiki 中打开当前版本。';

  @override
  String aiWorkWikiPages(int count) {
    return '$count 个页面';
  }

  @override
  String aiWorkParagraphs(int start, int end) {
    return '第 $start–$end 段';
  }

  @override
  String librarySearchIn(String name) {
    return '在「$name」中';
  }

  @override
  String get librarySearchEverywhere => '搜索全部资料';

  @override
  String librarySearchNoNameMatch(String query) {
    return '没有名字含「$query」的条目，下面是相近的名字和正文里的结果';
  }

  @override
  String get librarySearchSimilar => '相近的名字';

  @override
  String get librarySearchMentions => '正文提到';

  @override
  String get librarySearchNoMentions => '正文里没有找到';

  @override
  String librarySearchInText(String query) {
    return '在正文里搜索「$query」';
  }

  @override
  String get librarySearchSemantic => '按意思找剧情';

  @override
  String get librarySearchSemanticTitle => '意思相近的剧情';

  @override
  String get librarySearchSemanticNeedsService =>
      '配置向量服务后可以按意思找剧情（设置 → API 设置 → 向量）';

  @override
  String get librarySearchSemanticNoVectors => '当前知识库没有剧情向量（可以在知识库页生成）';

  @override
  String get librarySearchSemanticOtherModel => '知识库的向量不是用当前配置的向量模型生成的';

  @override
  String get librarySearchSemanticFailed => '向量服务请求失败';

  @override
  String librarySearchMatchCount(int n) {
    return '$n 处';
  }

  @override
  String librarySearchFurther(String query) {
    return '搜索「$query」（含相近名字与正文）';
  }

  @override
  String get storyReaderFindHint => '在本篇中查找';

  @override
  String get storyReaderFindEmpty => '输入人名或词语，这里会列出本篇中含有它的台词，点一句跳过去。';

  @override
  String get gameArknights => '明日方舟';

  @override
  String get gameEndfield => '终末地';

  @override
  String get launchTagline => '剧情阅读与问答';

  @override
  String libraryGameMissing(String game) {
    return '$game知识库未安装';
  }

  @override
  String get kbEndfieldTitle => '终末地知识库';

  @override
  String get libraryFigureStories => '剧情';

  @override
  String get libraryFigureCollections => '故事集';

  @override
  String get libraryFigureEntries => '图鉴条目';

  @override
  String get libraryOpenKnowledgeBase => '前往知识库';

  @override
  String get wikiTools => '页面工具';

  @override
  String get wikiToolsClose => '收起页面工具';

  @override
  String get wikiZoomOut => '缩小文字';

  @override
  String get wikiZoomIn => '放大文字';

  @override
  String get wikiRefresh => '刷新页面';

  @override
  String get wikiDarkPage => '页面深色';

  @override
  String get wikiBookmarkAdd => '加入书签';

  @override
  String get wikiBookmarkRemove => '移除书签';

  @override
  String get bookmarksRemoved => '已移除书签';

  @override
  String get commonUndo => '撤销';

  @override
  String get bookmarksDelete => '移除';

  @override
  String get settingsAppearance => '外观';

  @override
  String get settingsThemeSystemShort => '跟随系统';

  @override
  String get settingsThemeSystem => '随手机的深浅模式切换';

  @override
  String get settingsReadingFont => '阅读字体';

  @override
  String get settingsReadingFontDesc => '剧情、档案和回答正文用的字体';

  @override
  String get settingsReadingFontSans => '黑体';

  @override
  String get settingsReadingFontKai => '霞鹜文楷';

  @override
  String get apiSettingsShowKey => '显示密钥';

  @override
  String get apiSettingsHideKey => '隐藏密钥';

  @override
  String get wikiSourcesResetConfirm => '站点恢复为内置的列表，自己添加的站点会被删除。';

  @override
  String get aiConfigRequiredTitle => '先配置对话服务';

  @override
  String get aiAskTry => '可以这样问';

  @override
  String get settingsContextWarnTokens => '上下文提醒值';

  @override
  String get settingsContextWarnTokensDesc => '一个对话的上下文超过这个值时提醒。';

  @override
  String get settingsCompactPercent => '自动压缩位置';

  @override
  String get settingsCompactPercentDesc => '上下文到提醒值的这个比例时，较早的内容自动压缩成纪要。';

  @override
  String get settingsSkipOperatorNames => '回答里不标干员名';

  @override
  String get settingsSkipOperatorNamesDesc =>
      '打开后，回答里的干员名字不加下划线、不能点开立绘；其他人物照旧。';

  @override
  String aiContextMeter(String n, String limit) {
    return '上下文 $n / $limit';
  }

  @override
  String aiContextNotice(String n, String limit) {
    return '这个对话的上下文已超过提醒值（$n / $limit）。上下文越长，每一步越贵，模型也越容易漏看前面的内容。可以开一个新对话接着问。';
  }

  @override
  String get aiContextWarningTitle => '上下文超过提醒值';

  @override
  String aiContextWarningBody(String n, String limit) {
    return '这个对话的上下文已有 $n（提醒值 $limit）。上下文越长，每一步越贵，模型也越容易漏看前面的内容。可以开一个新对话接着问。';
  }

  @override
  String get aiContextNewChat => '开新对话';

  @override
  String get aiContextStop => '停止作答';

  @override
  String get aiContextDismiss => '知道了';

  @override
  String aiWorkCompaction(String from, String to, int count) {
    return '压缩上下文 / 约 $from → $to / 保留 $count 段';
  }

  @override
  String get portraitPackMissing => '没有安装立绘包。';

  @override
  String get portraitNotInPack => '立绘包里没有这一张。';

  @override
  String get portraitBlank => '这一句的立绘是空的。';

  @override
  String get portraitPackTitle => '剧情立绘';

  @override
  String get portraitPackOldIndex => '装的知识库还没有立绘数据，更新知识库后可以下载立绘包。';

  @override
  String get portraitPackUnreleased => '立绘包还没有发布。';

  @override
  String portraitPackDescription(String size) {
    return '阅读器里点说话人、问答里点名字时显示剧情立绘。约 $size。';
  }

  @override
  String portraitPackInstalled(int count, String size) {
    return '已安装：$count 张差分，$size。';
  }

  @override
  String portraitPackUpdateAvailable(String size) {
    return '有新的立绘包（$size）。';
  }

  @override
  String get portraitPackDownload => '下载立绘包';

  @override
  String get portraitPackUpdate => '更新';

  @override
  String get portraitPackDelete => '删除';

  @override
  String get portraitPackCancel => '取消';

  @override
  String get portraitPackCredit => '立绘：Arkwaifu（CC BY-NC 4.0）/ 鹰角网络';

  @override
  String get portraitPackEndfield => '终末地的剧情还没有立绘数据。';

  @override
  String get portraitPackDeleteConfirm => '删除已下载的立绘包？之后可以重新下载。';

  @override
  String get portraitPackError => '立绘包操作失败，请重试。';

  @override
  String portraitPackProgress(String received, String total, String percent) {
    return '$received / $total（$percent%）';
  }

  @override
  String get portraitEyebrow => 'PORTRAIT';

  @override
  String portraitLines(int n) {
    return '$n 句';
  }

  @override
  String portraitStories(int n) {
    return '$n 篇';
  }

  @override
  String portraitSprites(int n) {
    return '差分 $n 张';
  }

  @override
  String portraitFaceBody(int face, int body) {
    return '表情 $face / 服装 $body';
  }

  @override
  String get portraitGroupSpeakers => '还有谁使用了这个立绘？';

  @override
  String get portraitWhoUses => '谁在用这个立绘？';

  @override
  String portraitStoriesWith(String name) {
    return '“$name”用这个立绘的剧情';
  }

  @override
  String get portraitSpeakerGroups => '这个人还有哪些立绘？';

  @override
  String get portraitOperator => '干员资料';

  @override
  String get portraitNoSprite => '这一句没有显示立绘。';

  @override
  String portraitTapSpeaker(String name) {
    return '查看“$name”的立绘';
  }

  @override
  String get portraitGroupPageTitle => '立绘的说话人';

  @override
  String portraitSpeakerPageTitle(String name) {
    return '“$name”的立绘';
  }

  @override
  String portraitSpeakerCount(int n) {
    return '$n 个说话人';
  }

  @override
  String get portraitMore => '更多';

  @override
  String portraitStoryTitle(String name) {
    return '$name 的剧情';
  }

  @override
  String get portraitNoStories => '没有找到剧情。';
}

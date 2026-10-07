# 测试

`flutter test` 跑全部离线测试（约 40 秒，不联网、不花钱）。

## 目录

测试目录与 `lib/` 一一对应：`lib/core/x/y.dart` 的测试是 `test/core/x/y_test.dart`。
找某段代码的测试、给新文件加测试，都按这个路径。一个 lib 文件里有两个独立部分时，先考虑把 lib 文件拆开；
用 `part` 拆成几个文件的（如 `entry_importer_*.dart`）仍按主文件测（`entry_importer_test.dart`）。
资料页的各个页面（`features/library/*_page.dart`）一起在 `library_ui_test.dart` 里测。

| 目录 | 内容 |
|---|---|
| `core/`、`features/`、`shared/` | 对应 `lib/` 的单元测试与 Widget 测试 |
| `app_test.dart` | 启动后的整个 App：引导页、四个标签页、记住的标签、命名路由 |
| `guards/` | 全仓库守卫（禁止特判的 grep 等） |
| `live/` | 真实 API / 真实知识库的 opt-in 测试，默认跳过，要环境变量才跑（花钱，规则见 CLAUDE.md） |
| `support/` | 共用的夹具与替身 |
| `fixtures/` | 数据文件（live 评测题） |

## 共用夹具（`support/`）

- `gamedata_fixture.dart`：`createGameDataDb` 建**生产 schema**（`createGamedataSchema`）的知识库，
  `insertStory` / `insertEntity` / `insertRecord` 写数据。**不要在测试里手写 `CREATE TABLE`**：
  手写的表会和真实的表分叉（列不同、FTS 分词器不同），测试过了而 App 用的库是另一个样子。
  唯一的例外是专门测“旧版本的库”（如 `gamedata_knowledge_store_test.dart` 里没有索引的旧库），注释里写明。
- `source_fixture.dart`：一棵小的 ArknightsGameData 源码树（3 个角色、1 个物品、一个活动 5 章），
  构建、覆盖层、更新的测试都从它开始；`fake_github.dart` 把它按提交在内存里当作 GitHub 提供
  （提交、git 树、raw 文件、codeload zip）。
- `amiya_fixture.dart`、`two_activities_fixture.dart`：检索、角色扮演、近似名与范围外命中用的小库。
- `fake_llm.dart`：`ScriptedLLM` 按脚本回答并记录收到的请求；截断、流式、永不回答这类特殊行为在测试文件里继承它或 `LLMClient`。
- `fake_installer.dart`、`fake_webview.dart`（WebView 页面在 Widget 测试里显示为空盒子）、
  `plain_theme.dart`（主题的 Google 字体在测试里会联网下载并失败，Widget 测试用 `plainThemeOverride()`）、
  `memory_user_store.dart`、`screenshot.dart`、`sqlite.dart`（`setUpAll(useSqfliteFfi)`）、`temp_dir.dart`（`deleteTempDir`，Windows 文件锁时重试）。

## 约定

- 测试名写行为（“一次更新只下载变化的文件”），不写开发轮次；轮次（R13、R17d）放注释里。
- 夹具里的名字用虚构的；具体人物名可以出现在测试里，但不得进入 `lib/` 的判定（见 CLAUDE.md）。
- 平台通道（path_provider、secure storage）在测试里 mock 到临时目录；HTTP 用 `MockClient`，
  代码内部 `http.Client()` 建的客户端用 `http.runWithClient` 替换。
- 改一个 lib 文件，先跑它对应的测试文件或目录，再跑全量：

```bash
flutter test test/core/gamedata
flutter test
flutter analyze
```

覆盖率：`flutter test --coverage` 生成 `coverage/lcov.info`（不提交）。

## 没有自动测试的部分

- Wiki 浏览器（`features/wiki/wiki_browser_*`、`wiki_reader_*`、`wiki_toolbar.dart`）：内容在 WebView 里，
  页面脚本与站点适配靠真机检查；Widget 测试只覆盖它在 App 外壳里能建出来。
- `app_icon_service.dart`（Android 启动图标切换）、`background_work.dart` 的 Android 前台服务部分：平台代码，真机检查。
- `live/` 下的测试：真实模型与完整知识库，按需手动跑。

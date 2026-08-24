import 'package:arklores/core/gamedata/gamedata_installer.dart';
import 'package:arklores/core/gamedata/gamedata_provider.dart';
import 'package:arklores/features/settings/knowledge_base_page.dart';
import 'package:arklores/features/settings/settings_service.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('SettingsService GitHub token', () {
    test('loads blank, saves and clears the token', () async {
      final service = SettingsService();
      expect(await service.loadGithubToken(), '');

      await service.saveGithubToken('ghp_abc123');
      expect(await service.loadGithubToken(), 'ghp_abc123');

      await service.saveGithubToken('   ');
      expect(await service.loadGithubToken(), '');
    });
  });

  group('knowledge base page GitHub token section', () {
    testWidgets('renders the token input and build actions', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gameDataInstallStatusProvider.overrideWith(
              (ref) async => const GameDataInstallStatus(
                installed: false,
                dbPath: '',
                bytes: 0,
                manifest: {},
              ),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const KnowledgeBasePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('GitHub Token（可选）'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
      expect(find.text('从源仓库构建'), findsWidgets); // card title + button
      expect(find.text('检查更新'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

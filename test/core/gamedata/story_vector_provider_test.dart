// The "story vectors" card: what is missing from the installed knowledge
// base, embedding it with the configured service, and refusing to mix
// vectors of another model.
import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/gamedata/story_vector_provider.dart';
import 'package:arklores/core/llm/embedding_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/gamedata_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

const _config = EmbeddingConfig(
  baseUrl: 'https://e.example.com/v1',
  apiKey: 'k',
  model: 'emb',
  dimensions: 4,
);

/// An embedding service: the same unit vector for every input.
http.Client _service() => MockClient((request) async {
      final input = (jsonDecode(request.body) as Map)['input'] as List;
      return http.Response(
        jsonEncode({
          'data': [
            for (var i = 0; i < input.length; i++)
              {
                'index': i,
                'embedding': [1, 0, 0, 0],
              },
          ],
          'usage': {'total_tokens': input.length},
        }),
        200,
      );
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;
  var config = _config;

  setUpAll(useSqfliteFfi);
  setUp(() {
    docs = Directory.systemTemp.createTempSync('story_vector_provider');
    config = _config;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => docs.path,
    );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await deleteTempDir(docs);
  });

  Future<void> install() async {
    final db = await createGameDataDb('${docs.path}/arklores_gamedata_zh.db');
    await insertStory(db, 'activities/x/level_x_01.txt', ['甲：出发吧。', '天亮了。']);
    await insertStory(db, 'activities/x/level_x_02.txt', ['乙：到了。']);
    await db.close();
  }

  StoryVectorNotifier notifier() {
    final n = StoryVectorNotifier(() => config);
    addTearDown(n.dispose);
    return n;
  }

  test('nothing installed: nothing to plan', () async {
    final n = notifier();
    await n.refresh();
    expect(n.state.plan, isNull);
    expect(n.state.loading, isFalse);
  });

  test('plans the stories without vectors, then embeds them', () async {
    await install();
    final n = notifier();
    await n.refresh();
    expect(n.state.plan!.pendingStories, 2);
    expect(n.state.plan!.isFirstBuild, isTrue);
    expect(n.state.plan!.estimatedTokens, greaterThan(0));

    await http.runWithClient(n.start, _service);
    expect(n.state.error, isNull);
    expect(n.state.running, isFalse);
    expect(n.state.result!.stories, 2);
    expect(n.state.result!.tokensUsed, greaterThan(0));
    // Refreshed after the run.
    expect(n.state.plan!.nothingToDo, isTrue);
    expect(n.state.plan!.model, 'emb');
    expect(n.state.plan!.dims, 4);
  });

  test('without a configured service nothing runs', () async {
    await install();
    config = const EmbeddingConfig();
    final n = notifier();
    await n.start();
    expect(n.state.error, contains('not configured'));
    expect(n.state.result, isNull);
  });

  test('vectors of another model are not mixed in', () async {
    await install();
    final n = notifier();
    await http.runWithClient(n.start, _service);
    // A new story arrives, and the settings now name another model.
    final db = await databaseFactoryFfi.openDatabase('${docs.path}/arklores_gamedata_zh.db');
    await insertStory(db, 'activities/x/level_x_03.txt', ['丙：我也在。']);
    await db.close();
    config = _config.copyWith(model: 'other');

    await n.refresh();
    expect(n.state.mismatch, (have: 'emb@4', want: 'other@4'));
    await http.runWithClient(n.start, _service);
    expect(n.state.error, isNull);
    expect(n.state.plan!.pendingStories, 1);
  });
}

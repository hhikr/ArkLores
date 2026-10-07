// The roleplay tab's state: picking a character, a streamed reply that is
// saved, cancel and retry, and picking the saved conversation up again.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/agent/react_loop.dart';
import 'package:arklores/core/agent/roleplay_agent.dart';
import 'package:arklores/core/agent/roleplay_session_store.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_llm.dart';
import '../../support/temp_dir.dart';

const _character = GameDataEntityCandidate(
  entityId: 'char_x',
  name: '甲',
  entityType: 'operator',
  sourceType: 'operator_profile',
  matchedAlias: '甲',
  matchType: 'name_exact',
  confidence: 1,
);

void main() {
  late Directory dir;
  late RoleplaySessionStore store;
  late String storePath;
  late _Agent agent;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('roleplay_notifier');
    storePath = '${dir.path}/roleplay.json';
    store = RoleplaySessionStore(filePath: storePath);
    agent = _Agent();
  });
  tearDown(() => deleteTempDir(dir));

  RoleplayNotifier notifier() {
    final n = RoleplayNotifier(agent, store);
    addTearDown(n.dispose);
    return n;
  }

  Future<RoleplayNotifier> withCharacter() async {
    final n = notifier()..selectCandidate(_character, scene: ' 甲板上 ');
    return n;
  }

  group('picking a character', () {
    test('a resolved name becomes the character; the scene is trimmed',
        () async {
      agent.resolution = const CharacterResolution(
        CharacterResolutionStatus.resolved,
        character: _character,
      );
      final n = notifier();
      await n.resolveCharacter(' 甲 ', scene: ' 夜里 ');
      expect(n.state.character?.entityId, 'char_x');
      expect(n.state.scene, '夜里');
      expect(n.state.isResolving, isFalse);
      expect(n.state.resolutionStatus, CharacterResolutionStatus.resolved);
    });

    test('a failing lookup does not stay "resolving"', () async {
      agent.resolveError = StateError('no database');
      final n = notifier();
      await n.resolveCharacter('甲');
      expect(n.state.isResolving, isFalse);
      expect(n.state.character, isNull);
    });

    test('an empty name is ignored', () async {
      final n = notifier();
      await n.resolveCharacter('  ');
      expect(agent.resolveCalls, 0);
    });
  });

  group('a reply', () {
    test('streams, completes and is saved', () async {
      agent.script = [
        const ReActEvent(type: ReActEventType.toolCall, toolName: 'search_local_lore'),
        const ReActEvent(type: ReActEventType.finalAnswerToken, content: '……我'),
        const ReActEvent(type: ReActEventType.finalAnswerToken, content: '记得。'),
        const ReActEvent(type: ReActEventType.complete),
      ];
      final n = await withCharacter();
      await n.sendMessage(' 还记得吗？ ');

      final [user, reply] = n.state.messages;
      expect(user.content, '还记得吗？');
      expect(reply.content, '……我记得。');
      expect(reply.isStreaming, isFalse);
      expect(reply.steps.map((s) => s.toolName), ['search_local_lore']);
      expect(agent.lastFirstTurn, isTrue);
      expect(agent.lastScene, '甲板上');

      expect(n.state.hasSavedSession, isTrue);
      final saved = jsonDecode(File(storePath).readAsStringSync()) as Map;
      expect((saved['character'] as Map)['entityId'], 'char_x');
      expect((saved['messages'] as List).map((m) => (m as Map)['content']),
          ['还记得吗？', '……我记得。'],);
    });

    test('the next turn gets the history without failed replies', () async {
      agent.script = [const ReActEvent(type: ReActEventType.complete)];
      agent.failWith = StateError('provider down');
      final n = await withCharacter();
      await n.sendMessage('第一句');
      expect(n.state.messages.last.content, '[ROLEPLAY_ERROR]');
      expect(n.state.messages.last.isError, isTrue);

      agent.failWith = null;
      agent.script = [
        const ReActEvent(type: ReActEventType.finalAnswerReplace, content: '好。'),
        const ReActEvent(type: ReActEventType.complete),
      ];
      await n.sendMessage('第二句');
      expect(agent.lastFirstTurn, isFalse);
      expect(agent.lastHistory.map((m) => m.content), ['第一句']);
      expect(n.state.messages.last.content, '好。');
    });

    test('cancel marks the reply and ignores what still arrives', () async {
      final events = StreamController<ReActEvent>();
      agent.stream = events.stream;
      final n = await withCharacter();
      final sending = n.sendMessage('说点什么');
      await Future<void>.delayed(Duration.zero);
      expect(n.state.isSending, isTrue);

      n.cancel();
      events
        ..add(const ReActEvent(type: ReActEventType.finalAnswerReplace, content: '迟到的回答'))
        ..add(const ReActEvent(type: ReActEventType.complete));
      await events.close();
      await sending;
      expect(n.state.isSending, isFalse);
      expect(n.state.messages.last.content, '[ROLEPLAY_CANCELED]');
      expect(File(storePath).existsSync(), isFalse);
    });

    test('retry sends the last message again in place of the last pair',
        () async {
      agent.failWith = StateError('timeout');
      final n = await withCharacter();
      await n.sendMessage('再说一遍');
      agent
        ..failWith = null
        ..script = [
          const ReActEvent(type: ReActEventType.finalAnswerReplace, content: '好的。'),
          const ReActEvent(type: ReActEventType.complete),
        ];
      await n.retryLast();
      expect(n.state.messages.map((m) => m.content), ['再说一遍', '好的。']);
    });

    test('nothing is sent without a character', () async {
      final n = notifier();
      await n.sendMessage('你好');
      expect(n.state.messages, isEmpty);
      expect(agent.replyCalls, 0);
    });
  });

  group('the saved conversation', () {
    Future<void> saveOne() async {
      agent.script = [
        const ReActEvent(type: ReActEventType.finalAnswerReplace, content: '在。'),
        const ReActEvent(type: ReActEventType.complete),
      ];
      final n = await withCharacter();
      await n.sendMessage('在吗');
    }

    test('is offered on start and picked up again', () async {
      await saveOne();
      final n = notifier();
      // The constructor looks for the file in the background.
      for (var i = 0; i < 100 && !n.state.hasSavedSession; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(n.state.hasSavedSession, isTrue);
      expect(n.state.character, isNull);

      await n.continueSavedSession();
      expect(n.state.character?.entityId, 'char_x');
      expect(n.state.scene, '甲板上');
      expect(n.state.messages.map((m) => m.content), ['在吗', '在。']);
      expect(n.state.messages.first.role, MessageRole.user);
    });

    test('a damaged file is dropped', () async {
      await store.save({'version': 1, 'character': 'not a map'});
      final n = notifier();
      await n.continueSavedSession();
      expect(n.state.character, isNull);
      expect(await store.load(), isNull);
    });

    test('restart forgets it', () async {
      await saveOne();
      final n = notifier();
      await n.continueSavedSession();
      await n.restart();
      expect(n.state.character, isNull);
      expect(n.state.messages, isEmpty);
      expect(await store.load(), isNull);
    });
  });
}

/// A roleplay agent whose lookups and replies are set by the test.
class _Agent extends RoleplayAgent {
  _Agent() : super(llmClient: ScriptedLLM(['unused']));

  CharacterResolution resolution =
      const CharacterResolution(CharacterResolutionStatus.notFound);
  Object? resolveError;
  int resolveCalls = 0;

  List<ReActEvent> script = const [];
  Stream<ReActEvent>? stream;
  Object? failWith;
  int replyCalls = 0;
  bool? lastFirstTurn;
  String? lastScene;
  List<Message> lastHistory = const [];

  @override
  Future<CharacterResolution> resolveCharacter(String query) async {
    resolveCalls++;
    if (resolveError != null) throw resolveError!;
    return resolution;
  }

  @override
  Stream<ReActEvent> reply({
    required GameDataEntityCandidate character,
    required String userMessage,
    String scene = '',
    List<Message> history = const [],
    bool isFirstTurn = false,
  }) async* {
    replyCalls++;
    lastFirstTurn = isFirstTurn;
    lastScene = scene;
    lastHistory = history;
    if (failWith != null) throw failWith!;
    if (stream != null) {
      yield* stream!;
      return;
    }
    yield* Stream.fromIterable(script);
  }
}

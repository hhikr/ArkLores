import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arklores/core/agent/react_loop.dart';
import 'package:arklores/core/agent/tools/cite_source.dart';
import 'package:arklores/core/agent/tools/search_wiki.dart';
import 'package:arklores/core/agent/tools/tool_registry.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/core/rag/chunker.dart';
import 'package:arklores/core/rag/embedder.dart';
import 'package:arklores/core/rag/embedding_client.dart';
import 'package:arklores/core/rag/vector_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  PathProviderPlatform? previousPathProvider;
  late sqflite.DatabaseFactory? previousDatabaseFactory;
  late VectorStore vectorStore;

  setUp(() async {
    sqfliteFfiInit();
    try {
      previousDatabaseFactory = sqflite.databaseFactory;
    } catch (_) {
      previousDatabaseFactory = null;
    }
    sqflite.databaseFactory = databaseFactoryFfi;

    tempDir = await Directory.systemTemp.createTemp('arklores_agent_test_');
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);

    vectorStore = VectorStore();
    await vectorStore.initialize();
  });

  tearDown(() async {
    vectorStore.dispose();
    if (previousPathProvider != null) {
      PathProviderPlatform.instance = previousPathProvider!;
    }
    if (previousDatabaseFactory != null) {
      sqflite.databaseFactory = previousDatabaseFactory!;
    }
    await tempDir.delete(recursive: true);
  });

  group('Agent Tools Tests', () {
    test('SearchWikiTool searches vector store successfully', () async {
      final embedder = Embedder(_MockEmbeddingClient());
      final tool = SearchWikiTool(
        embedder: embedder,
        vectorStore: vectorStore,
        profileId: 'test-profile',
      );

      // Seed a chunk
      await vectorStore.insertChunk(
        Chunk(
          id: 'chunk-123',
          content: 'Amiya is the leader of Rhodes Island.',
          pageTitle: 'Amiya',
          section: 'Profile',
          seqIndex: 0,
          tokenCount: 10,
        ),
        [1.0, 0.0, 0.0],
        sourceType: 'wiki',
        wiki: 'prts',
        profileId: 'test-profile',
      );

      final result = await tool.execute({'query': 'Amiya', 'top_k': 1});
      expect(result, contains('Amiya is the leader of Rhodes Island.'));
      expect(result, contains('chunk-123'));
      expect(result, contains('Source Type: wiki'));
    });

    test('CiteSourceTool retrieves chunk by ID', () async {
      final tool = CiteSourceTool(vectorStore: vectorStore);

      // Seed a chunk
      await vectorStore.insertChunk(
        Chunk(
          id: 'chunk-456',
          content: 'Kal\'tsit is a doctor.',
          pageTitle: 'Kal\'tsit',
          section: 'Overview',
          seqIndex: 0,
          tokenCount: 8,
        ),
        [0.0, 1.0, 0.0],
        sourceType: 'book',
        bookId: 'book-abc',
        profileId: 'test-profile',
      );

      final result = await tool.execute({'chunk_id': 'chunk-456'});
      expect(result, contains('Kal\'tsit is a doctor.'));
      expect(result, contains('Book ID: book-abc'));
      expect(result, contains('Source Type: book'));
    });
  });

  group('ReAct Loop Tests', () {
    test('ReActLoop runs, executes tools, and yields final answer', () async {
      final registry = ToolRegistry();
      final mockLlm = _MockLLMClient();
      final embedder = Embedder(_MockEmbeddingClient());

      registry.register(SearchWikiTool(
        embedder: embedder,
        vectorStore: vectorStore,
        profileId: 'test-profile',
      ));
      registry.register(CiteSourceTool(vectorStore: vectorStore));

      // Seed database with a chunk
      await vectorStore.insertChunk(
        Chunk(
          id: 'chunk-123',
          content: 'W is a mercenary.',
          pageTitle: 'W',
          section: 'Overview',
          seqIndex: 0,
          tokenCount: 6,
        ),
        [1.0, 0.0, 0.0],
        sourceType: 'wiki',
        wiki: 'prts',
        profileId: 'test-profile',
      );

      final reactLoop = ReActLoop(
        llmClient: mockLlm,
        toolRegistry: registry,
        maxIterations: 3,
      );

      final eventStream = reactLoop.run(
        systemPrompt: 'You are a helper.',
        chatHistory: [],
        userQuery: 'Who is W?',
      );

      final events = await eventStream.toList();

      // Verify ReAct event progression
      final eventTypes = events.map((e) => e.type).toList();
      
      expect(eventTypes, contains(ReActEventType.thought));
      expect(eventTypes, contains(ReActEventType.toolCall));
      expect(eventTypes, contains(ReActEventType.toolObservation));
      expect(eventTypes, contains(ReActEventType.finalAnswerToken));
      expect(eventTypes, contains(ReActEventType.complete));

      // Verify specific outputs
      final finalAnswerEvent = events.firstWhere((e) => e.type == ReActEventType.finalAnswerToken);
      expect(finalAnswerEvent.content, contains('W is a mercenary [chunk-123]'));
    });
  });
}

class _FakePathProvider extends PathProviderPlatform {
  final String path;

  _FakePathProvider(this.path);

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

class _MockEmbeddingClient implements EmbeddingClient {
  _MockEmbeddingClient();

  @override
  String get providerId => 'mock-embed';

  @override
  int get dimension => 3;

  @override
  Future<List<double>> embed(String text) async {
    return [1.0, 0.0, 0.0];
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    return List.generate(texts.length, (_) => [1.0, 0.0, 0.0]);
  }

  @override
  void dispose() {}
}

class _MockLLMClient extends LLMClient {
  int callCount = 0;

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
  }) async {
    callCount++;
    if (callCount == 1) {
      return '''
Thought: I need to look up W in the wiki database.
Action: search_wiki
Action Input: {"query": "W"}
''';
    } else if (callCount == 2) {
      return '''
Thought: I need to retrieve details for the chunk using cite_source.
Action: cite_source
Action Input: {"chunk_id": "chunk-123"}
''';
    } else {
      return '''
Thought: I have enough information to write the final answer.
Final Answer: W is a mercenary [chunk-123].
''';
    }
  }

  @override
  Future<String> chatStream(
    List<Message> messages, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 2048,
  }) async {
    return chat(messages, temperature: temperature, maxTokens: maxTokens);
  }

  @override
  Future<List<double>> embed(String text) async => [1.0, 0.0, 0.0];

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async =>
      List.generate(texts.length, (_) => [1.0, 0.0, 0.0]);
}

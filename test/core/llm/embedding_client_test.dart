// The embedding endpoint used for story vectors: the request, batching,
// order, usage, the per-session cache and errors.
import 'dart:convert';

import 'package:arklores/core/llm/embedding_client.dart';
import 'package:arklores/core/llm/llm_client.dart' show LLMException;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _config = EmbeddingConfig(
  baseUrl: 'https://e.example.com/v1/',
  apiKey: 'k',
  model: 'emb',
  dimensions: 4,
);

/// Answers with vector [i, i, i, i] for input i, in reverse order (the
/// client must sort by `index`), and counts one token per input.
http.Response _vectors(http.Request request) {
  final input = (jsonDecode(request.body) as Map)['input'] as List;
  return http.Response(
    jsonEncode({
      'data': [
        for (var i = input.length - 1; i >= 0; i--)
          {
            'index': i,
            'embedding': List.filled(4, double.parse('${input[i]}')),
          },
      ],
      'usage': {'total_tokens': input.length},
    }),
    200,
  );
}

void main() {
  test('the endpoint and when a config is usable', () {
    expect(_config.endpoint, 'https://e.example.com/v1/embeddings');
    expect(_config.copyWith(baseUrl: 'https://x/v1').endpoint, 'https://x/v1/embeddings');
    expect(_config.isValid, isTrue);
    expect(_config.copyWith(apiKey: ' ').isValid, isFalse);
    expect(defaultEmbeddingConfig.isValid, isFalse); // no key
  });

  test('sends model, input and size; batches of 20 come back in order',
      () async {
    final bodies = <Map<String, dynamic>>[];
    final client = OpenAICompatibleEmbeddingClient(
      config: _config,
      httpClient: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer k');
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return _vectors(request);
      }),
    );
    final texts = [for (var i = 0; i < 45; i++) '$i'];
    final vectors = await client.embed(texts);
    expect(vectors.map((v) => v.first), [for (var i = 0; i < 45; i++) i.toDouble()]);
    expect(bodies.map((b) => (b['input'] as List).length), [20, 20, 5]);
    expect(bodies.first['model'], 'emb');
    expect(bodies.first['dimensions'], 4);
    expect(bodies.first['encoding_format'], 'float');
    expect(client.tokensUsed, 45);
    expect(await client.embed(const []), isEmpty);
  });

  test('a repeated single query is answered from the cache', () async {
    var calls = 0;
    final client = OpenAICompatibleEmbeddingClient(
      config: _config,
      httpClient: MockClient((request) async {
        calls++;
        return _vectors(request);
      }),
    );
    await client.embed(['7']);
    expect((await client.embed(['7'])).single.first, 7);
    expect(calls, 1);
  });

  test('a client error is reported at once; a busy server is retried',
      () async {
    var calls = 0;
    final refused = OpenAICompatibleEmbeddingClient(
      config: _config,
      httpClient: MockClient((request) async {
        calls++;
        return http.Response('{"error":"bad key"}', 401);
      }),
    );
    await expectLater(
      refused.embed(['1']),
      throwsA(isA<LLMException>().having((e) => e.statusCode, 'status', 401)),
    );
    expect(calls, 1);

    calls = 0;
    final busy = OpenAICompatibleEmbeddingClient(
      config: _config,
      maxRetries: 1,
      httpClient: MockClient((request) async {
        calls++;
        return calls == 1 ? http.Response('busy', 429) : _vectors(request);
      }),
    );
    expect((await busy.embed(['2'])).single.first, 2);
    expect(calls, 2);
  });

  test('a response with the wrong number of vectors is an error', () async {
    final client = OpenAICompatibleEmbeddingClient(
      config: _config,
      httpClient: MockClient((request) async => http.Response(
            jsonEncode({
              'data': [
                {'index': 0, 'embedding': [1, 1, 1, 1]},
              ],
            }),
            200,
          ),),
    );
    await expectLater(client.embed(['a', 'b']), throwsA(isA<LLMException>()));
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:http/http.dart' as http;

import 'llm_client.dart';

// ── Top-level helper for compute() isolate ──────────────────────────────────
// Must be top-level (not a class member) so Flutter's isolate spawner can
// locate it without capturing any mutable class state.

/// Parses an OpenAI-compatible embedding batch JSON response string.
///
/// Sorts items by the `index` field to guarantee the original request order.
/// Uses `(v as num).toDouble()` rather than `.cast<double>()` to handle
/// providers that encode zero-valued floats as JSON integers.
List<List<double>> _parseEmbeddingBatchResponse(String responseBody) {
  final data = jsonDecode(responseBody) as Map<String, dynamic>;
  final dataList = data['data'] as List<dynamic>;
  dataList.sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));
  return dataList.map((item) {
    final raw = item['embedding'] as List<dynamic>;
    return raw.map((v) => (v as num).toDouble()).toList();
  }).toList();
}

// ─────────────────────────────────────────────────────────────────────────────

/// OpenAI-compatible implementation of [LLMClient].
///
/// Supports custom Base URL (for domestic/transit APIs),
/// configurable chat and embedding models.
class OpenAICompatibleClient implements LLMClient {
  final LLMConfig config;
  final http.Client _httpClient;
  final Duration _timeout;

  OpenAICompatibleClient({
    required this.config,
    http.Client? httpClient,
    Duration? timeout,
  })  : _httpClient = httpClient ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 30);

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
  }) async {
    _requireChatConfig();

    final body = <String, dynamic>{
      'model': config.chatModel,
      'messages': messages.map((m) => m.toJson()).toList(),
      'temperature': temperature,
      'max_tokens': maxTokens,
    };

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools;
    }

    try {
      final response = await _httpClient
          .post(
            Uri.parse(config.chatEndpoint),
            headers: _headers(config.chatApiKey),
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw LLMException(
          'Chat completion failed',
          statusCode: response.statusCode,
          body: response.body,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>;
      if (choices.isEmpty) {
        throw const LLMException('Empty response from chat completion');
      }

      final message = choices[0]['message'] as Map<String, dynamic>;
      return (message['content'] as String?) ?? '';
    } on SocketException catch (e) {
      throw LLMException('Network error: ${e.message}');
    } on TimeoutException {
      throw const LLMException('Request timed out');
    }
  }

  @override
  Future<String> chatStream(
    List<Message> messages, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 2048,
  }) async {
    _requireChatConfig();

    final body = <String, dynamic>{
      'model': config.chatModel,
      'messages': messages.map((m) => m.toJson()).toList(),
      'temperature': temperature,
      'max_tokens': maxTokens,
      'stream': true,
    };

    try {
      final request = http.Request('POST', Uri.parse(config.chatEndpoint))
        ..headers.addAll(_headers(config.chatApiKey))
        ..body = jsonEncode(body);

      final streamedResponse = await _httpClient
          .send(request)
          .timeout(_timeout);

      if (streamedResponse.statusCode != 200) {
        final body = await streamedResponse.stream.bytesToString();
        throw LLMException(
          'Chat stream failed',
          statusCode: streamedResponse.statusCode,
          body: body,
        );
      }

      final buffer = StringBuffer();
      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        final lines = chunk.split('\n');
        for (final line in lines) {
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6);
          if (data == '[DONE]') continue;

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final choices = json['choices'] as List<dynamic>?;
            if (choices == null || choices.isEmpty) continue;

            final delta = choices[0]['delta'] as Map<String, dynamic>?;
            final content = delta?['content'] as String?;
            if (content != null && content.isNotEmpty) {
              buffer.write(content);
              onToken?.call(content);
            }
          } catch (_) {
            // Skip malformed JSON lines in the stream.
          }
        }
      }

      return buffer.toString();
    } on SocketException catch (e) {
      throw LLMException('Network error: ${e.message}');
    } on TimeoutException {
      throw const LLMException('Request timed out');
    }
  }

  @override
  Future<List<double>> embed(String text) async {
    _requireEmbedConfig();

    try {
      final response = await _httpClient
          .post(
            Uri.parse(config.embeddingEndpoint),
            headers: _headers(_embedApiKey),
            body: jsonEncode({
              'model': config.embedModel,
              'input': text,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw LLMException(
          'Embedding failed',
          statusCode: response.statusCode,
          body: response.body,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final dataList = data['data'] as List<dynamic>;
      if (dataList.isEmpty) {
        throw const LLMException('Empty response from embedding');
      }

      final embedding = dataList[0]['embedding'] as List<dynamic>;
      return embedding.cast<double>();
    } on SocketException catch (e) {
      throw LLMException('Network error: ${e.message}');
    } on TimeoutException {
      throw const LLMException('Request timed out');
    }
  }

  String get _embedApiKey =>
      config.embedApiKey.isNotEmpty ? config.embedApiKey : config.chatApiKey;

  // ── Constants for the resilient embed pipeline ────────────────────────────

  /// Maximum number of retries for network / rate-limit errors.
  static const int _maxEmbedRetries = 3;

  /// Maximum character count for a single text sent to the API.
  /// Texts exceeding this are truncated before the final retry attempt.
  /// ~4 000 chars ≈ 2 200 tokens (Chinese-heavy) — safely under most limits.
  static const int _embedTruncationLimit = 4000;

  /// Default embedding dimension used when no successful embedding has been
  /// made yet (e.g. for the zero-vector fallback).
  static const int _embedDefaultDim = 1536;

  // ── Public embedBatch ─────────────────────────────────────────────────────

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    _requireEmbedConfig();
    if (texts.isEmpty) return [];

    // Nullable slots — null means "not yet embedded".
    final slots = List<List<double>?>.filled(texts.length, null);

    // Process in groups of 16 to stay within typical API token / payload limits
    // (16 chunks * ~500 tokens = ~8,000 tokens, which is the safe upper limit
    // for most embedding engines like OpenAI's text-embedding-3-small).
    const batchSize = 16;
    for (var offset = 0; offset < texts.length; offset += batchSize) {
      final end = (offset + batchSize).clamp(0, texts.length);
      final indices = List<int>.generate(end - offset, (i) => offset + i);
      await _embedGroup(texts, indices, slots);
    }

    // Determine dimension from any successful result; fall back to 1536.
    final dim = slots.firstWhere((r) => r != null && r.isNotEmpty,
            orElse: () => null)
        ?.length ??
        _embedDefaultDim;

    // Replace any remaining nulls (irrecoverable items) with zero vectors.
    // Zero vectors have negligible cosine similarity against real queries, so
    // they effectively never surface in search — but the chunk's text IS stored
    // and can still be found via exact-match / keyword search later.
    return [for (final s in slots) s ?? List<double>.filled(dim, 0.0)];
  }

  // ── Private: resilient recursive embedding ────────────────────────────────

  /// Embeds the texts at [indices] and writes results into [slots].
  ///
  /// Retry / degradation ladder (applied per sub-group, not globally):
  ///
  /// 1. **Network / timeout** — linear back-off, up to [_maxEmbedRetries].
  /// 2. **HTTP 429 (rate-limited)** — exponential back-off (5 → 10 → 20 → 40 s).
  /// 3. **HTTP 400 + batch > 1** — binary split; recurse on each half.
  ///    This isolates the bad item without discarding its neighbours.
  /// 4. **HTTP 400 + single item** — truncate to [_embedTruncationLimit] chars
  ///    and retry once.  Still 400 after truncation → leave slot null (zero vec).
  /// 5. **Other non-200** — linear back-off, up to [_maxEmbedRetries].
  Future<void> _embedGroup(
    List<String> texts,
    List<int> indices,
    List<List<double>?> slots, {
    int attempt = 0,
  }) async {
    if (indices.isEmpty) return;

    final batch = [for (final i in indices) texts[i]];
    final batchTimeout = Duration(
      seconds: _timeout.inSeconds + (batch.length ~/ 10).clamp(0, 60),
    );

    // ── Send the HTTP request ────────────────────────────────────────────────
    http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse(config.embeddingEndpoint),
            headers: _headers(_embedApiKey),
            body: jsonEncode({'model': config.embedModel, 'input': batch}),
          )
          .timeout(batchTimeout);
    } on SocketException catch (e) {
      if (attempt < _maxEmbedRetries) {
        final delay = Duration(seconds: 2 * (attempt + 1));
        debugPrint('[Embed] SocketException (attempt ${attempt + 1}/${_maxEmbedRetries}): '
            '${e.message}. Retrying in ${delay.inSeconds}s.');
        await Future.delayed(delay);
        return _embedGroup(texts, indices, slots, attempt: attempt + 1);
      }
      debugPrint('[Embed] Giving up on ${indices.length} item(s) after repeated SocketException.');
      return; // slots stay null → zero vectors
    } on TimeoutException {
      if (attempt < _maxEmbedRetries) {
        final delay = Duration(seconds: 2 * (attempt + 1));
        debugPrint('[Embed] Timeout (attempt ${attempt + 1}/${_maxEmbedRetries}). '
            'Retrying in ${delay.inSeconds}s.');
        await Future.delayed(delay);
        return _embedGroup(texts, indices, slots, attempt: attempt + 1);
      }
      debugPrint('[Embed] Giving up on ${indices.length} item(s) after repeated timeouts.');
      return;
    }

    // ── Handle non-200 responses ─────────────────────────────────────────────
    if (response.statusCode == 429) {
      if (attempt < _maxEmbedRetries) {
        final delay = Duration(seconds: 5 * (1 << attempt)); // 5, 10, 20, 40 s
        debugPrint('[Embed] Rate-limited 429 for ${indices.length} item(s) '
            '(attempt ${attempt + 1}). Waiting ${delay.inSeconds}s.');
        await Future.delayed(delay);
        return _embedGroup(texts, indices, slots, attempt: attempt + 1);
      }
      debugPrint('[Embed] Giving up on ${indices.length} item(s) after repeated 429.');
      return;
    }

    if (response.statusCode == 400) {
      if (indices.length > 1) {
        // Binary split — one of the items is likely too long or malformed.
        // Splitting isolates it so the rest of the batch can succeed.
        debugPrint('[Embed] 400 on batch of ${indices.length}, binary-splitting. Response: ${response.body}');
        final mid = indices.length ~/ 2;
        await _embedGroup(texts, indices.sublist(0, mid), slots);
        await _embedGroup(texts, indices.sublist(mid), slots);
        return;
      }

      // Single-item 400: the text itself is rejected (usually too long).
      // Truncate and retry once.
      final idx = indices.first;
      final text = texts[idx];
      if (text.length > _embedTruncationLimit) {
        debugPrint('[Embed] Single-item 400: truncating text[$idx] '
            '(${text.length} → $_embedTruncationLimit chars) and retrying.');
        final truncated = text.substring(0, _embedTruncationLimit);
        try {
          final r = await _httpClient
              .post(
                Uri.parse(config.embeddingEndpoint),
                headers: _headers(_embedApiKey),
                body: jsonEncode(
                    {'model': config.embedModel, 'input': [truncated]}),
              )
              .timeout(_timeout);
          if (r.statusCode == 200) {
            final parsed = await compute(_parseEmbeddingBatchResponse, r.body);
            if (parsed.isNotEmpty) {
              slots[idx] = parsed.first;
              debugPrint('[Embed] Truncated text[$idx] embedded successfully.');
              return;
            }
          }
        } catch (_) {}
        debugPrint('[Embed] Truncated text[$idx] still failed. Using zero vector.');
      } else {
        debugPrint('[Embed] text[$idx] (${text.length} chars) returned 400 '
            'but is already short — using zero vector.');
      }
      return; // slot stays null → zero vector
    }

    if (response.statusCode != 200) {
      if (attempt < _maxEmbedRetries) {
        final delay = Duration(seconds: 2 * (attempt + 1));
        debugPrint('[Embed] HTTP ${response.statusCode} for ${indices.length} item(s) '
            '(attempt ${attempt + 1}). Retrying in ${delay.inSeconds}s.');
        await Future.delayed(delay);
        return _embedGroup(texts, indices, slots, attempt: attempt + 1);
      }
      debugPrint('[Embed] Giving up on ${indices.length} item(s) after '
          'repeated HTTP ${response.statusCode}.');
      return;
    }

    // ── Parse successful response ────────────────────────────────────────────
    // Run jsonDecode in a background isolate: response bodies for even small
    // batches are ~100–500 KB and block the Flutter rendering pipeline if
    // decoded synchronously on the main thread.
    final parsed = await compute(_parseEmbeddingBatchResponse, response.body);
    for (var j = 0; j < indices.length; j++) {
      if (j < parsed.length) slots[indices[j]] = parsed[j];
    }
  }

  Map<String, String> _headers(String apiKey) => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      };

  void _requireChatConfig() {
    if (config.chatApiKey.isEmpty) {
      throw const LLMException(
        'Chat API Key not configured. Please set up your Chat API in Settings.',
      );
    }
  }

  void _requireEmbedConfig() {
    if (config.chatApiKey.isEmpty && config.embedApiKey.isEmpty) {
      throw const LLMException(
        'Embedding API not configured. Configure an Embedding API in '
        'Settings, or ensure your Chat API provider supports embeddings.',
      );
    }
  }

  /// Releases the underlying HTTP client resources.
  void dispose() {
    _httpClient.close();
  }
}

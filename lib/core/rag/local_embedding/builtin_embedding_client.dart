import 'dart:math';
import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import 'builtin_embedding_model.dart';
import '../embedding_client.dart';
import 'wordpiece_tokenizer.dart';

/// Exception thrown by the built-in embedding spike client.
class BuiltinEmbeddingException implements Exception {
  final String message;
  const BuiltinEmbeddingException(this.message);

  @override
  String toString() => 'BuiltinEmbeddingException: $message';
}

/// TFLite-backed local embedding client for validating the fixed built-in model.
///
/// This is intentionally isolated from the production RAG provider until the
/// fixed model asset is committed and verified on Android/iOS devices.
class BuiltinEmbeddingClient implements EmbeddingClient {
  final Interpreter _interpreter;
  final WordPieceTokenizer _tokenizer;
  @override
  final String providerId;
  @override
  final int dimension;

  BuiltinEmbeddingClient._({
    required Interpreter interpreter,
    required WordPieceTokenizer tokenizer,
    required this.providerId,
    required this.dimension,
  })  : _interpreter = interpreter,
        _tokenizer = tokenizer;

  static Future<BuiltinEmbeddingClient> load({
    String modelAsset = BuiltinEmbeddingModel.modelAsset,
    String vocabAsset = BuiltinEmbeddingModel.vocabAsset,
    int maxSequenceLength = BuiltinEmbeddingModel.maxSequenceLength,
    String providerId = BuiltinEmbeddingModel.providerId,
    int expectedDimension = BuiltinEmbeddingModel.expectedDimension,
  }) async {
    try {
      final interpreter = await Interpreter.fromAsset(modelAsset);
      final tokenizer = await WordPieceTokenizer.fromAsset(
        vocabAsset: vocabAsset,
        maxSequenceLength: maxSequenceLength,
      );
      return BuiltinEmbeddingClient._(
        interpreter: interpreter,
        tokenizer: tokenizer,
        providerId: providerId,
        dimension: expectedDimension,
      );
    } catch (e) {
      throw BuiltinEmbeddingException(
        'Failed to load built-in embedding assets. '
        'Expected $modelAsset and $vocabAsset. Original error: $e',
      );
    }
  }

  @override
  Future<List<double>> embed(String text) async {
    final vectors = await embedBatch([text]);
    return vectors.first;
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    final vectors = <List<double>>[];
    for (final text in texts) {
      vectors.add(_embedOne(text));
      await Future<void>.delayed(Duration.zero);
    }
    return vectors;
  }

  @override
  void dispose() => _interpreter.close();

  void close() => dispose();

  List<double> _embedOne(String text) {
    final tokenized = _tokenizer.encode(text);
    final inputs = _buildInputs(tokenized);
    _interpreter.runInference(inputs);

    final outputTensor = _interpreter.getOutputTensors().first;
    if (outputTensor.type != TensorType.float32) {
      throw BuiltinEmbeddingException(
        'Unsupported output tensor type: ${outputTensor.type}. Expected float32.',
      );
    }

    final floats = _float32TensorData(outputTensor.data);
    final shape = outputTensor.shape;
    final vector = _poolOutput(floats, shape, tokenized.attentionMask);

    if (vector.length != dimension) {
      throw BuiltinEmbeddingException(
        'Unexpected embedding dimension ${vector.length}; expected $dimension.',
      );
    }
    return _l2Normalize(vector);
  }

  List<Object> _buildInputs(TokenizedText tokenized) {
    final inputs = _interpreter.getInputTensors();
    if (inputs.length == 1) {
      return [_batch(tokenized.inputIds)];
    }

    final ordered = <Object>[];
    for (final tensor in inputs) {
      final name = tensor.name.toLowerCase();
      if (name.contains('mask')) {
        ordered.add(_batch(tokenized.attentionMask));
      } else if (name.contains('type') || name.contains('segment')) {
        ordered.add(_batch(tokenized.tokenTypeIds));
      } else {
        ordered.add(_batch(tokenized.inputIds));
      }
    }
    return ordered;
  }

  List<List<int>> _batch(List<int> values) => [values];

  List<double> _float32TensorData(Uint8List bytes) {
    final view = ByteData.sublistView(bytes);
    return List<double>.generate(
      bytes.length ~/ 4,
      (i) => view.getFloat32(i * 4, Endian.little),
      growable: false,
    );
  }

  List<double> _poolOutput(
      List<double> values, List<int> shape, List<int> attentionMask) {
    if (shape.length == 2) {
      return values;
    }
    if (shape.length != 3) {
      throw BuiltinEmbeddingException(
          'Unsupported output tensor shape: $shape');
    }

    final seqLength = shape[1];
    final hiddenSize = shape[2];
    final pooled = List<double>.filled(hiddenSize, 0.0);
    var tokenCount = 0;
    for (var token = 0;
        token < seqLength && token < attentionMask.length;
        token++) {
      if (attentionMask[token] == 0) continue;
      tokenCount++;
      final offset = token * hiddenSize;
      for (var i = 0; i < hiddenSize; i++) {
        pooled[i] += values[offset + i];
      }
    }

    if (tokenCount == 0) return pooled;
    for (var i = 0; i < pooled.length; i++) {
      pooled[i] /= tokenCount;
    }
    return pooled;
  }

  List<double> _l2Normalize(List<double> vector) {
    var norm = 0.0;
    for (final value in vector) {
      norm += value * value;
    }
    norm = sqrt(norm);
    if (norm == 0) return vector;
    return vector.map((value) => value / norm).toList(growable: false);
  }
}

class LazyBuiltinEmbeddingClient implements EmbeddingClient {
  final String _modelAsset;
  final String _vocabAsset;
  final int _maxSequenceLength;
  @override
  final String providerId;
  @override
  final int dimension;

  Future<BuiltinEmbeddingClient>? _clientFuture;

  LazyBuiltinEmbeddingClient({
    required this.providerId,
    required this.dimension,
    String modelAsset = BuiltinEmbeddingModel.modelAsset,
    String vocabAsset = BuiltinEmbeddingModel.vocabAsset,
    int maxSequenceLength = BuiltinEmbeddingModel.maxSequenceLength,
  })  : _modelAsset = modelAsset,
        _vocabAsset = vocabAsset,
        _maxSequenceLength = maxSequenceLength;

  Future<BuiltinEmbeddingClient> get _client {
    return _clientFuture ??= BuiltinEmbeddingClient.load(
      modelAsset: _modelAsset,
      vocabAsset: _vocabAsset,
      maxSequenceLength: _maxSequenceLength,
      providerId: providerId,
      expectedDimension: dimension,
    );
  }

  @override
  Future<List<double>> embed(String text) async {
    return (await _client).embed(text);
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    return (await _client).embedBatch(texts);
  }

  @override
  void dispose() {
    final future = _clientFuture;
    if (future != null) {
      future.then((client) => client.dispose());
    }
  }
}

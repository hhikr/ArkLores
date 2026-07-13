/// Built-in embedding model backed by a TFLite model.
///
/// The current model is a small synthetic embedding model (~750 KB) for
/// pipeline testing. Replace with a production-quality model when available.
class BuiltinEmbeddingModel {
  const BuiltinEmbeddingModel._();

  static const String id = 'builtin-embedding';
  static const String displayName = 'Built-in Embedding';
  static const String modelAsset = 'assets/models/embedding/model.tflite';
  static const String vocabAsset = 'assets/models/embedding/vocab.txt';
  static const int maxSequenceLength = 128;
  static const int expectedDimension = 384;

  static const String providerId = 'builtin:$id';
}

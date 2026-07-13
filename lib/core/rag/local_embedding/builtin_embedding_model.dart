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
  static const int maxSequenceLength = 512;
  static const int expectedDimension = 512;

  static const String providerId = 'builtin:$id';
}

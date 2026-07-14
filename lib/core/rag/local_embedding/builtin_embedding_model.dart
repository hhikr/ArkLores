/// Built-in embedding model backed by a TFLite model.
///
/// The current bundled model is a fixed 512-dimensional TFLite embedding model
/// used for offline seed generation and on-device fallback embedding.
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

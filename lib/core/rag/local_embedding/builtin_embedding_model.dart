/// Fixed built-in embedding model contract for the v0.3 local embedding spike.
///
/// The binary model and vocabulary are intentionally not committed in this
/// spike. When the fixed model is selected, these assets must be present and
/// packaged with the application.
class BuiltinEmbeddingModel {
  const BuiltinEmbeddingModel._();

  static const String id = 'multilingual-e5-small-tflite';
  static const String displayName = 'Multilingual E5 Small';
  static const String modelAsset = 'assets/models/embedding/model.tflite';
  static const String vocabAsset = 'assets/models/embedding/vocab.txt';
  static const int maxSequenceLength = 256;
  static const int expectedDimension = 384;

  static const String providerId = 'builtin:$id';
}

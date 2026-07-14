abstract class EmbeddingClient {
  String get providerId;

  int get dimension;

  Future<List<double>> embed(String text);

  Future<List<List<double>>> embedBatch(List<String> texts);

  void dispose();
}

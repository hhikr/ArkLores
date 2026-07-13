import '../llm/llm_client.dart';
import '../llm/openai_client.dart';
import 'embedding_client.dart';

class ApiEmbeddingClient implements EmbeddingClient {
  final OpenAICompatibleClient _client;
  @override
  final String providerId;

  ApiEmbeddingClient({required LLMConfig config, required this.providerId})
      : _client = OpenAICompatibleClient(config: config);

  @override
  int get dimension => 0;

  @override
  Future<List<double>> embed(String text) => _client.embed(text);

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) =>
      _client.embedBatch(texts);

  @override
  void dispose() => _client.dispose();
}

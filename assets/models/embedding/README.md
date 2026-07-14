# Built-in Embedding Model Assets

Current model: bundled TFLite embedding model (about 26 MB, 512 dim,
512 seq len).

Files:
- `model.tflite` - TFLite embedding model (int32 input_ids + attention_mask -> float32[512])
- `vocab.txt` - tokenizer vocabulary used by the built-in embedding client

To replace with a production model:
1. Replace `model.tflite` and `vocab.txt`
2. Update `BuiltinEmbeddingModel` constants as needed

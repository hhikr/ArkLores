# Built-in Embedding Model Assets

Current model: synthetic embedding model (754 KB, 384 dim, 128 seq len)
Created with TensorFlow 2.21.0 for pipeline testing.

Files:
- `model.tflite` - TFLite embedding model (int32 input_ids + attention_mask → float32[384])
- `vocab.txt` - WordPiece vocabulary (1000 tokens)

To replace with a production model:
1. Replace `model.tflite` and `vocab.txt`
2. Update `BuiltinEmbeddingModel` constants as needed

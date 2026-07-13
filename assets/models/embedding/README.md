# Built-in Embedding Model Assets

This directory is reserved for the fixed local embedding model selected for the
v0.3 built-in embedding spike.

Expected files:

- `model.tflite` - the fixed multilingual embedding model converted to TFLite
- `vocab.txt` - WordPiece vocabulary matching the model tokenizer

The model binary is not committed in this spike. Add it only after license,
package size, and Android/iOS runtime verification are complete.

#!/usr/bin/env python3
"""Embed ArkLores seed database chunks with the bundled TFLite model.

This runner intentionally does not use Dart or Flutter. It reproduces the
runtime tokenizer, pooling, L2 normalization, and SQLite BLOB format used by
the Flutter app so the prebuilt DB can be bundled with vectors already filled.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import math
import sqlite3
import struct
import sys
import unicodedata
from pathlib import Path


PROFILE_ID = "builtin:builtin-embedding"
EXPECTED_DIMENSION = 512
MAX_SEQUENCE_LENGTH = 512


def _load_interpreter_class():
    try:
        from ai_edge_litert.interpreter import Interpreter  # type: ignore

        return Interpreter, "ai-edge-litert"
    except ImportError:
        pass

    try:
        from tflite_runtime.interpreter import Interpreter  # type: ignore

        return Interpreter, "tflite-runtime"
    except ImportError:
        pass

    try:
        import tensorflow as tf  # type: ignore

        return tf.lite.Interpreter, "tensorflow"
    except ImportError:
        pass

    raise RuntimeError(
        "No TFLite runtime found. Install one of:\n"
        "  pip install ai-edge-litert\n"
        "  pip install tflite-runtime\n"
        "  pip install tensorflow"
    )


def _import_numpy():
    try:
        import numpy as np  # type: ignore

        return np
    except ImportError as exc:
        raise RuntimeError(
            "NumPy is required by the TFLite runtime. Install it with: pip install numpy"
        ) from exc


class WordPieceTokenizer:
    def __init__(self, vocab: dict[str, int], max_sequence_length: int):
        self.vocab = vocab
        self.max_sequence_length = max_sequence_length
        self.pad_id = self._token_id("[PAD]")
        self.unk_id = self._token_id("[UNK]")
        self.cls_id = self._token_id("[CLS]")
        self.sep_id = self._token_id("[SEP]")

    @staticmethod
    def parse_vocab(raw: str) -> dict[str, int]:
        vocab: dict[str, int] = {}
        for i, line in enumerate(raw.splitlines()):
            token = line.strip()
            if token:
                vocab[token] = i
        return vocab

    def encode(self, text: str) -> tuple[list[int], list[int], list[int]]:
        if self.max_sequence_length < 2:
            raise ValueError("max_sequence_length must be at least 2")

        ids = [self.cls_id]
        for token in self._basic_tokenize(text):
            ids.extend(self._word_piece(token))
            if len(ids) >= self.max_sequence_length - 1:
                break
        ids.append(self.sep_id)

        truncated = ids[: self.max_sequence_length]
        if truncated[-1] != self.sep_id:
            truncated[self.max_sequence_length - 1] = self.sep_id

        attention_mask = [0] * self.max_sequence_length
        input_ids = [self.pad_id] * self.max_sequence_length
        for i, token_id in enumerate(truncated):
            input_ids[i] = token_id
            attention_mask[i] = 1
        token_type_ids = [0] * self.max_sequence_length
        return input_ids, attention_mask, token_type_ids

    def _token_id(self, token: str) -> int:
        if token not in self.vocab:
            raise ValueError(f"Vocabulary is missing required token: {token}")
        return self.vocab[token]

    def _basic_tokenize(self, text: str):
        normalized = text.lower().strip()
        buf: list[str] = []

        def flush():
            if buf:
                token = "".join(buf)
                buf.clear()
                return token
            return None

        for char in normalized:
            code = ord(char)
            if char.isspace():
                token = flush()
                if token:
                    yield token
            elif self._is_cjk(code) or self._is_punctuation_or_symbol(char):
                token = flush()
                if token:
                    yield token
                yield char
            else:
                buf.append(char)

        token = flush()
        if token:
            yield token

    def _word_piece(self, token: str) -> list[int]:
        if token in self.vocab:
            return [self.vocab[token]]

        pieces: list[int] = []
        start = 0
        while start < len(token):
            end = len(token)
            current = None
            while start < end:
                sub = token[start:end]
                candidate = sub if start == 0 else f"##{sub}"
                if candidate in self.vocab:
                    current = self.vocab[candidate]
                    break
                end -= 1
            if current is None:
                return [self.unk_id]
            pieces.append(current)
            start = end
        return pieces

    @staticmethod
    def _is_punctuation_or_symbol(char: str) -> bool:
        category = unicodedata.category(char)
        return category.startswith("P") or category.startswith("S")

    @staticmethod
    def _is_cjk(code: int) -> bool:
        return (
            0x4E00 <= code <= 0x9FFF
            or 0x3400 <= code <= 0x4DBF
            or 0x20000 <= code <= 0x2A6DF
            or 0x2A700 <= code <= 0x2B73F
            or 0x2B740 <= code <= 0x2B81F
            or 0x2B820 <= code <= 0x2CEAF
        )


class TfliteEmbedder:
    def __init__(self, model_path: Path, vocab_path: Path):
        Interpreter, runner_name = _load_interpreter_class()
        self.runner_name = runner_name
        self.np = _import_numpy()
        self.interpreter = Interpreter(model_path=str(model_path))
        self.interpreter.allocate_tensors()
        self.input_details = self.interpreter.get_input_details()
        self.output_details = self.interpreter.get_output_details()
        vocab = WordPieceTokenizer.parse_vocab(vocab_path.read_text(encoding="utf-8"))
        self.tokenizer = WordPieceTokenizer(vocab, MAX_SEQUENCE_LENGTH)

    def embed(self, text: str) -> list[float]:
        input_ids, attention_mask, token_type_ids = self.tokenizer.encode(text)
        tensors = {
            "input_ids": input_ids,
            "attention_mask": attention_mask,
            "token_type_ids": token_type_ids,
        }

        for detail in self.input_details:
            name = str(detail.get("name", "")).lower()
            if "mask" in name:
                values = tensors["attention_mask"]
            elif "type" in name or "segment" in name:
                values = tensors["token_type_ids"]
            else:
                values = tensors["input_ids"]
            arr = self.np.array([values], dtype=detail["dtype"])
            self.interpreter.set_tensor(detail["index"], arr)

        self.interpreter.invoke()
        output = self.interpreter.get_tensor(self.output_details[0]["index"])
        vector = self._pool_output(output, attention_mask)
        if len(vector) != EXPECTED_DIMENSION:
            raise ValueError(
                f"Unexpected embedding dimension: {len(vector)}, expected {EXPECTED_DIMENSION}"
            )
        return self._l2_normalize(vector)

    def _pool_output(self, output, attention_mask: list[int]) -> list[float]:
        shape = list(output.shape)
        if len(shape) == 2:
            return [float(v) for v in output[0].tolist()]
        if len(shape) != 3:
            raise ValueError(f"Unsupported output tensor shape: {shape}")

        seq_length = shape[1]
        hidden_size = shape[2]
        pooled = [0.0] * hidden_size
        token_count = 0
        for token in range(min(seq_length, len(attention_mask))):
            if attention_mask[token] == 0:
                continue
            token_count += 1
            values = output[0][token]
            for i in range(hidden_size):
                pooled[i] += float(values[i])
        if token_count == 0:
            return pooled
        return [v / token_count for v in pooled]

    @staticmethod
    def _l2_normalize(vector: list[float]) -> list[float]:
        norm = math.sqrt(sum(v * v for v in vector))
        if norm == 0:
            return vector
        return [v / norm for v in vector]


def _vector_blob(vector: list[float]) -> bytes:
    return struct.pack(">" + "d" * len(vector), *vector)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", required=True, type=Path)
    parser.add_argument("--model", default=Path("assets/models/embedding/model.tflite"), type=Path)
    parser.add_argument("--vocab", default=Path("assets/models/embedding/vocab.txt"), type=Path)
    parser.add_argument("--batch-size", default=32, type=int)
    parser.add_argument("--profile-id", default=PROFILE_ID)
    parser.add_argument("--limit", default=0, type=int)
    parser.add_argument("--allow-zero-vector", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    if not args.db.exists():
        raise FileNotFoundError(args.db)
    if not args.model.exists():
        raise FileNotFoundError(args.model)
    if not args.vocab.exists():
        raise FileNotFoundError(args.vocab)

    embedder = TfliteEmbedder(args.model, args.vocab)
    print(f"Embedding runner: {embedder.runner_name}")

    conn = sqlite3.connect(args.db)
    try:
        conn.execute("PRAGMA foreign_keys = ON")
        rows = conn.execute(
            """
            SELECT id, content FROM chunks
            WHERE embedding_status = 'pending_embedding'
              AND profile_id = ?
            ORDER BY rowid
            """,
            (args.profile_id,),
        ).fetchall()
        if args.limit > 0:
            rows = rows[: args.limit]

        total = len(rows)
        print(f"Pending chunks: {total}")
        if total == 0:
            _write_metadata(conn, embedder.runner_name, 0)
            return 0

        embedded = 0
        for start in range(0, total, args.batch_size):
            batch = rows[start : start + args.batch_size]
            with conn:
                for chunk_id, content in batch:
                    vector = embedder.embed(content or "")
                    if all(v == 0.0 for v in vector):
                        if not args.allow_zero_vector:
                            raise ValueError(f"Zero vector generated for chunk {chunk_id}")
                        conn.execute(
                            "UPDATE chunks SET embedding_status = 'zero_vector' WHERE id = ?",
                            (chunk_id,),
                        )
                        continue

                    conn.execute(
                        """
                        INSERT OR REPLACE INTO chunk_embeddings(chunk_id, embedding)
                        VALUES (?, ?)
                        """,
                        (chunk_id, sqlite3.Binary(_vector_blob(vector))),
                    )
                    conn.execute(
                        "UPDATE chunks SET embedding_status = 'ok' WHERE id = ?",
                        (chunk_id,),
                    )
                    embedded += 1
            print(f"Embedded {min(start + len(batch), total)}/{total}")

        _write_metadata(conn, embedder.runner_name, embedded)
        print(f"Embedding complete: {embedded}/{total}")
        return 0
    finally:
        conn.close()


def _write_metadata(conn: sqlite3.Connection, runner_name: str, vector_count: int) -> None:
    now = _dt.datetime.now(_dt.timezone.utc).isoformat()
    metadata = {
        "embedding_status": "complete",
        "embedding_runner": f"python-tflite:{runner_name}",
        "embedding_completed_at": now,
        "embedding_vector_count": str(vector_count),
        "embedding_dimension": str(EXPECTED_DIMENSION),
    }
    with conn:
        for key, value in metadata.items():
            conn.execute(
                "INSERT OR REPLACE INTO seed_metadata(key, value) VALUES (?, ?)",
                (key, value),
            )


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001 - CLI should print clear failure.
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)

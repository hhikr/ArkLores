#!/usr/bin/env python3
"""Embed ArkLores GameData lore_chunks with the bundled TFLite model."""

from __future__ import annotations

import argparse
import datetime as _dt
import sqlite3
import sys
from pathlib import Path

from embed_seed_database import (  # type: ignore
    EXPECTED_DIMENSION,
    PROFILE_ID,
    TfliteEmbedder,
    _vector_blob,
)


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
            SELECT lc.id, lc.content
            FROM lore_chunks lc
            LEFT JOIN chunk_embeddings ce
              ON ce.chunk_id = lc.id AND ce.profile_id = ?
            WHERE ce.chunk_id IS NULL
            ORDER BY lc.rowid
            """,
            (args.profile_id,),
        ).fetchall()
        if args.limit > 0:
            rows = rows[: args.limit]

        total = len(rows)
        print(f"Pending lore chunks: {total}")
        if total == 0:
            _write_metadata(conn, embedder.runner_name, args.profile_id, 0)
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
                        continue

                    conn.execute(
                        """
                        INSERT OR REPLACE INTO chunk_embeddings(
                          chunk_id, profile_id, dimension, embedding
                        )
                        VALUES (?, ?, ?, ?)
                        """,
                        (
                            chunk_id,
                            args.profile_id,
                            EXPECTED_DIMENSION,
                            sqlite3.Binary(_vector_blob(vector)),
                        ),
                    )
                    embedded += 1
            print(f"Embedded {min(start + len(batch), total)}/{total}")

        _write_metadata(conn, embedder.runner_name, args.profile_id, embedded)
        print(f"Embedding complete: {embedded}/{total}")
        return 0
    finally:
        conn.close()


def _write_metadata(
    conn: sqlite3.Connection,
    runner_name: str,
    profile_id: str,
    vector_count: int,
) -> None:
    now = _dt.datetime.now(_dt.timezone.utc).isoformat()
    metadata = {
        "embedding_status": "complete",
        "embedding_profile_id": profile_id,
        "embedding_runner": f"python-tflite:{runner_name}",
        "embedding_completed_at": now,
        "embedding_vector_count": str(vector_count),
        "embedding_dimension": str(EXPECTED_DIMENSION),
    }
    with conn:
        for key, value in metadata.items():
            conn.execute(
                "INSERT OR REPLACE INTO gamedata_manifest(key, value) VALUES (?, ?)",
                (key, value),
            )


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001 - CLI should print clear failure.
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)

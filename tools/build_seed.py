#!/usr/bin/env python3
"""Build a fully embedded ArkLores seed bundle.

This orchestrates:
1. Dart seed builder: crawl/format/chunk/cache/SQLite chunks
2. Python TFLite embedder: fill chunk_embeddings and mark chunks ok
3. Verification and copying to assets/seeds/
"""

from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
import subprocess
import sys
from pathlib import Path


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", default="endfield,prts")
    parser.add_argument("--prts-categories", default=None)
    parser.add_argument("--limit", default=0, type=int)
    parser.add_argument("--embed-batch-size", default=32, type=int)
    parser.add_argument("--crawl-delay-ms", default=500, type=int)
    parser.add_argument("--max-chunks-per-page", default=120, type=int)
    parser.add_argument("--output", default=Path("build/seeds"), type=Path)
    parser.add_argument("--model", default=Path("assets/models/embedding/model.tflite"), type=Path)
    parser.add_argument("--vocab", default=Path("assets/models/embedding/vocab.txt"), type=Path)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--allow-large-pages", action="store_true")
    parser.add_argument("--no-copy-assets", action="store_true")
    return parser.parse_args()


def _run(cmd: list[str]) -> None:
    print("$ " + " ".join(str(c) for c in cmd))
    subprocess.run(cmd, check=True)


def main() -> int:
    args = _parse_args()
    output = args.output
    if args.force and args.resume:
        raise SystemExit("Cannot use --force and --resume together.")

    dart_cmd = [
        "dart",
        "run",
        "tools/build_seed_database.dart",
        f"--sources={args.sources}",
        f"--limit={args.limit}",
        f"--crawl-delay-ms={args.crawl_delay_ms}",
        f"--max-chunks-per-page={args.max_chunks_per_page}",
        f"--output={output}",
        "--no-copy-assets",
    ]
    if args.prts_categories:
        dart_cmd.append(f"--prts-categories={args.prts_categories}")
    if args.force:
        dart_cmd.append("--force")
    if args.resume:
        dart_cmd.append("--resume")
    if args.allow_large_pages:
        dart_cmd.append("--allow-large-pages")
    _run(dart_cmd)

    db_path = output / "arklores_knowledge.db"
    embed_cmd = [
        sys.executable,
        "tools/embed_seed_database.py",
        "--db",
        str(db_path),
        "--model",
        str(args.model),
        "--vocab",
        str(args.vocab),
        "--batch-size",
        str(args.embed_batch_size),
    ]
    _run(embed_cmd)

    _verify(db_path)
    _update_manifest(output / "seed_manifest.json", db_path)

    if not args.no_copy_assets:
        assets = Path("assets/seeds")
        assets.mkdir(parents=True, exist_ok=True)
        for name in ("arklores_knowledge.db", "wiki_cache.zip", "seed_manifest.json"):
            shutil.copy2(output / name, assets / name)
        print(f"Copied embedded seed assets to {assets}/")

    return 0


def _verify(db_path: Path) -> None:
    conn = sqlite3.connect(db_path)
    try:
        chunks = conn.execute("SELECT COUNT(*) FROM chunks").fetchone()[0]
        embeddings = conn.execute("SELECT COUNT(*) FROM chunk_embeddings").fetchone()[0]
        statuses = dict(
            conn.execute(
                "SELECT embedding_status, COUNT(*) FROM chunks GROUP BY embedding_status"
            ).fetchall()
        )
        print(f"chunks={chunks}, embeddings={embeddings}, statuses={statuses}")
        if chunks == 0:
            raise RuntimeError("Seed database contains no chunks")
        if chunks != embeddings:
            raise RuntimeError(f"Chunk/embedding count mismatch: {chunks} != {embeddings}")
        if set(statuses.keys()) != {"ok"}:
            raise RuntimeError(f"Unexpected embedding statuses: {statuses}")
    finally:
        conn.close()


def _update_manifest(manifest_path: Path, db_path: Path) -> None:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    conn = sqlite3.connect(db_path)
    try:
        metadata = dict(conn.execute("SELECT key, value FROM seed_metadata").fetchall())
    finally:
        conn.close()

    embedding = manifest.setdefault("embedding", {})
    embedding["status"] = metadata.get("embedding_status", "complete")
    embedding["runner"] = metadata.get("embedding_runner", "python-tflite")
    embedding["completedAt"] = metadata.get("embedding_completed_at")
    embedding["vectorCount"] = int(metadata.get("embedding_vector_count", "0"))
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Inspect Chinese ArknightsGameData content for lore-related sources.

This is a discovery tool, not the final importer. It scans a community unpack
repo and prints a Markdown inventory of text-heavy files and story directories.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--top-json", default=40, type=int)
    parser.add_argument("--max-story-dirs", default=220, type=int)
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    root = args.source / "zh_CN" / "gamedata"
    if not root.exists():
        raise FileNotFoundError(root)

    print("# Arknights GameData Content Inventory")
    print()
    print(f"- Source: `{args.source}`")
    print(f"- GameData root: `{root}`")
    print()

    _print_top_level(root)
    _print_story_inventory(root / "story", args.max_story_dirs)
    _print_excel_inventory(root / "excel", args.top_json)
    _print_story_table_coverage(root)
    return 0


def _print_top_level(root: Path) -> None:
    print("## Top-Level Inventory")
    print()
    print("| Path | Files | Bytes |")
    print("|---|---:|---:|")
    for child in sorted(root.iterdir(), key=lambda p: p.name.lower()):
        if child.is_dir():
            files = [p for p in child.rglob("*") if p.is_file()]
            size = sum(p.stat().st_size for p in files)
            print(f"| `{child.name}/` | {len(files)} | {size} |")
        else:
            print(f"| `{child.name}` | 1 | {child.stat().st_size} |")
    print()


def _print_story_inventory(story_root: Path, max_rows: int) -> None:
    print("## Story Text Directories")
    print()
    if not story_root.exists():
        print("_No story directory found._")
        print()
        return

    total = len(list(story_root.rglob("*.txt")))
    print(f"- Total `.txt` files: **{total}**")
    print()
    print("| Directory | Direct txt | Subtree txt |")
    print("|---|---:|---:|")

    rows: list[tuple[str, int, int]] = []
    for directory in sorted(p for p in story_root.rglob("*") if p.is_dir()):
        direct = len(list(directory.glob("*.txt")))
        subtree = len(list(directory.rglob("*.txt")))
        if direct or subtree:
            rel = directory.relative_to(story_root).as_posix()
            rows.append((rel, direct, subtree))

    for rel, direct, subtree in rows[:max_rows]:
        print(f"| `{rel}` | {direct} | {subtree} |")
    if len(rows) > max_rows:
        print(f"| _truncated_ |  | {len(rows) - max_rows} more directories |")
    print()


def _print_excel_inventory(excel_root: Path, top_json: int) -> None:
    print("## Text-Heavy Excel JSON Files")
    print()
    if not excel_root.exists():
        print("_No excel directory found._")
        print()
        return

    rows: list[tuple[str, str, int, int, str]] = []
    for file in sorted(excel_root.glob("*.json")):
        try:
            data = json.loads(file.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001 - inventory should keep going.
            rows.append((file.name, "error", 0, 0, str(exc)[:80]))
            continue
        top_keys = ",".join(list(data.keys())[:8]) if isinstance(data, dict) else ""
        rows.append(
            (
                file.name,
                type(data).__name__,
                len(data) if hasattr(data, "__len__") else 0,
                _count_chinese_text_values(data),
                top_keys,
            )
        )

    rows.sort(key=lambda row: row[3], reverse=True)
    print("| File | JSON type | Top count | Chinese text values | Top keys |")
    print("|---|---|---:|---:|---|")
    for name, json_type, count, text_values, top_keys in rows[:top_json]:
        print(f"| `{name}` | {json_type} | {count} | {text_values} | `{top_keys}` |")
    print()


def _print_story_table_coverage(root: Path) -> None:
    print("## Story Table Coverage")
    print()
    story_root = root / "story"
    story_table = root / "excel" / "story_table.json"
    if not story_root.exists() or not story_table.exists():
        print("_Cannot check coverage._")
        print()
        return

    files = {p.relative_to(story_root).as_posix().lower() for p in story_root.rglob("*.txt")}
    data = json.loads(story_table.read_text(encoding="utf-8"))
    missing = []
    for key in data.keys():
        if f"{key}.txt".lower() not in files:
            missing.append(key)

    print(f"- `story_table.json` entries: **{len(data)}**")
    print(f"- Missing `.txt` after case-insensitive match: **{len(missing)}**")
    if missing:
        print("- Missing sample:")
        for item in missing[:20]:
            print(f"  - `{item}`")
    print()


def _count_chinese_text_values(value: Any) -> int:
    if isinstance(value, str):
        stripped = value.strip()
        if len(stripped) >= 4 and any("\u4e00" <= char <= "\u9fff" for char in stripped):
            return 1
        return 0
    if isinstance(value, dict):
        return sum(_count_chinese_text_values(item) for item in value.values())
    if isinstance(value, list):
        return sum(_count_chinese_text_values(item) for item in value)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

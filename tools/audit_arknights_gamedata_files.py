#!/usr/bin/env python3
"""Audit every file in ArknightsGameData zh_CN/gamedata.

The goal is to classify source files before writing importers. The report is
heuristic and intentionally conservative: files are candidates until manually
reviewed by category.
"""

from __future__ import annotations

import argparse
import csv
import json
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any


TEXT_KEYS = {
    "name",
    "description",
    "desc",
    "usage",
    "storyText",
    "voiceText",
    "voiceTitle",
    "title",
    "subtitle",
    "content",
    "text",
    "itemDesc",
    "itemUsage",
    "teamDes",
    "teamFlavorDesc",
    "endingDescription",
    "changeEndingDesc",
    "eliteDesc",
    "taskDes",
    "unlockCondDesc",
    "obtainApproach",
}


@dataclass
class FileAudit:
    path: str
    directory: str
    extension: str
    bytes: int
    text_values: int
    text_chars: int
    text_keys: str
    suggested_category: str
    suggested_relevance: str
    sample: str


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--sample-limit", default=120, type=int)
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    root = args.source / "zh_CN" / "gamedata"
    if not root.exists():
        raise FileNotFoundError(root)

    audits = [_audit_file(root, file) for file in sorted(p for p in root.rglob("*") if p.is_file())]
    args.out.parent.mkdir(parents=True, exist_ok=True)
    _write_csv(args.out.with_suffix(".csv"), audits)
    _write_markdown(args.out, audits, args.sample_limit)
    print(f"Wrote {args.out}")
    print(f"Wrote {args.out.with_suffix('.csv')}")
    return 0


def _audit_file(root: Path, file: Path) -> FileAudit:
    rel = file.relative_to(root).as_posix()
    suffix = file.suffix.lower()
    text_values = 0
    text_chars = 0
    key_counter: Counter[str] = Counter()
    sample = ""

    if suffix == ".json":
        try:
            data = json.loads(file.read_text(encoding="utf-8"))
            stats = _scan_json_text(data)
            text_values = stats[0]
            text_chars = stats[1]
            key_counter = stats[2]
            sample = stats[3]
        except Exception as exc:  # noqa: BLE001
            sample = f"JSON_ERROR: {exc}"
    elif suffix in {".txt", ".lua"}:
        try:
            content = file.read_text(encoding="utf-8", errors="ignore")
            snippets = _extract_text_snippets(content)
            text_values = len(snippets)
            text_chars = sum(len(s) for s in snippets)
            sample = snippets[0][:160] if snippets else ""
        except Exception as exc:  # noqa: BLE001
            sample = f"TEXT_ERROR: {exc}"

    category = _suggest_category(rel)
    relevance = _suggest_relevance(rel, suffix, text_values, text_chars)
    return FileAudit(
        path=rel,
        directory=_review_directory(rel),
        extension=suffix or "(none)",
        bytes=file.stat().st_size,
        text_values=text_values,
        text_chars=text_chars,
        text_keys=",".join(k for k, _ in key_counter.most_common(12)),
        suggested_category=category,
        suggested_relevance=relevance,
        sample=sample.replace("\n", " ")[:240],
    )


def _scan_json_text(value: Any, key: str = "") -> tuple[int, int, Counter[str], str]:
    values = 0
    chars = 0
    keys: Counter[str] = Counter()
    sample = ""

    if isinstance(value, str):
        text = value.strip()
        if _contains_chinese(text) and len(text) >= 2:
            values = 1
            chars = len(text)
            if key:
                keys[key] += 1
            sample = text
        return values, chars, keys, sample

    if isinstance(value, dict):
        for child_key, child in value.items():
            child_values, child_chars, child_keys, child_sample = _scan_json_text(
                child,
                str(child_key),
            )
            values += child_values
            chars += child_chars
            keys.update(child_keys)
            if not sample and child_sample:
                sample = child_sample
        return values, chars, keys, sample

    if isinstance(value, list):
        for child in value:
            child_values, child_chars, child_keys, child_sample = _scan_json_text(child, key)
            values += child_values
            chars += child_chars
            keys.update(child_keys)
            if not sample and child_sample:
                sample = child_sample
        return values, chars, keys, sample

    return values, chars, keys, sample


def _extract_text_snippets(content: str) -> list[str]:
    snippets: list[str] = []
    for line in content.splitlines():
        text = line.strip()
        if len(text) < 2 or not _contains_chinese(text):
            continue
        snippets.append(text)
    return snippets


def _contains_chinese(text: str) -> bool:
    return any("\u4e00" <= char <= "\u9fff" for char in text)


def _suggest_category(path: str) -> str:
    lower = path.lower()
    if lower.startswith("story/"):
        if "/rogue/" in lower or "/roguelike/" in lower:
            return "roguelike_story"
        if "/memory/" in lower:
            return "operator_record_story"
        if "/sandbox" in lower:
            return "sandbox_story"
        if lower.startswith("story/activities/"):
            return "activity_story"
        if "/main" in lower:
            return "main_story"
        return "story"
    if lower.startswith("excel/"):
        name = Path(path).name
        if name in {"character_table.json", "handbook_info_table.json", "charword_table.json"}:
            return "operator"
        if "roguelike" in name:
            return "roguelike"
        if name in {"item_table.json", "uniequip_table.json", "battle_equip_table.json", "medal_table.json", "skin_table.json"}:
            return "world_item"
        if name == "enemy_handbook_table.json":
            return "enemy"
        if name in {"stage_table.json", "zone_table.json", "campaign_table.json"}:
            return "stage"
        if "sandbox" in name:
            return "sandbox"
        if name in {"activity_table.json", "retro_table.json", "mission_table.json"}:
            return "activity"
        return "excel_other"
    if lower.startswith("levels/"):
        if "rogue" in lower:
            return "roguelike_level"
        if "sandbox" in lower:
            return "sandbox_level"
        return "level"
    if lower.startswith("bakemuzzledata/enemy/"):
        return "enemy_level_data"
    if lower.startswith("building/") or Path(path).name == "building_data.json":
        return "building"
    if lower.startswith("[uc]lua/"):
        return "lua"
    return "other"


def _suggest_relevance(path: str, suffix: str, text_values: int, text_chars: int) -> str:
    lower = path.lower()
    if text_values == 0:
        return "exclude_no_text"
    if lower.startswith("story/"):
        return "core_story"
    if lower.startswith("excel/"):
        if text_values >= 1000:
            return "core_structured_text"
        if text_values >= 50:
            return "candidate_structured_text"
        return "low_volume_structured_text"
    if lower.startswith("levels/") or lower.startswith("bakemuzzledata/"):
        if text_values >= 20:
            return "candidate_level_text"
        return "low_volume_level_text"
    if suffix == ".lua":
        return "manual_review_lua_text"
    return "candidate_text"


def _write_csv(path: Path, audits: list[FileAudit]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(FileAudit.__dataclass_fields__.keys()))
        writer.writeheader()
        for audit in audits:
            writer.writerow(audit.__dict__)


def _write_markdown(path: Path, audits: list[FileAudit], sample_limit: int) -> None:
    by_category: defaultdict[str, list[FileAudit]] = defaultdict(list)
    by_relevance: Counter[str] = Counter()
    for audit in audits:
        by_category[audit.suggested_category].append(audit)
        by_relevance[audit.suggested_relevance] += 1

    with path.open("w", encoding="utf-8") as handle:
        handle.write("# Arknights GameData File Audit\n\n")
        handle.write(f"- Total files: **{len(audits)}**\n")
        handle.write(f"- Files with Chinese text: **{sum(1 for a in audits if a.text_values > 0)}**\n\n")

        handle.write("## Relevance Summary\n\n")
        handle.write("| Relevance | Files |\n|---|---:|\n")
        for key, count in by_relevance.most_common():
            handle.write(f"| `{key}` | {count} |\n")
        handle.write("\n")

        handle.write("## Category Summary\n\n")
        handle.write("| Category | Files | Chinese text values | Bytes |\n|---|---:|---:|---:|\n")
        for category, files in sorted(by_category.items()):
            handle.write(
                f"| `{category}` | {len(files)} | {sum(f.text_values for f in files)} | {sum(f.bytes for f in files)} |\n"
            )
        handle.write("\n")

        handle.write("## Category Directory Distribution\n\n")
        handle.write(
            "Use this section for manual review: it shows where each suggested "
            "category actually lives in the unpacked tree.\n\n"
        )
        for category, files in sorted(by_category.items()):
            handle.write(f"### `{category}`\n\n")
            handle.write("| Directory | Files | Files with Chinese text | Text values | Bytes |\n")
            handle.write("|---|---:|---:|---:|---:|\n")
            dir_rows = _directory_rows(files)
            for directory, row_files in dir_rows[:40]:
                handle.write(
                    f"| `{directory}` | {len(row_files)} | "
                    f"{sum(1 for f in row_files if f.text_values > 0)} | "
                    f"{sum(f.text_values for f in row_files)} | "
                    f"{sum(f.bytes for f in row_files)} |\n"
                )
            if len(dir_rows) > 40:
                handle.write(f"| _truncated_ | {len(dir_rows) - 40} more directories |  |  |  |\n")
            handle.write("\n")

        handle.write("## Category Review Packets\n\n")
        handle.write(
            "For each category, review the highest-text files first. These are "
            "the files most likely to need a dedicated importer adapter.\n\n"
        )
        for category, files in sorted(by_category.items()):
            candidates = [file for file in files if file.text_values > 0]
            if not candidates:
                continue
            handle.write(f"### `{category}`\n\n")
            handle.write("| File | Directory | Relevance | Text values | Keys | Sample |\n")
            handle.write("|---|---|---|---:|---|---|\n")
            ranked = sorted(candidates, key=lambda a: (a.text_values, a.text_chars), reverse=True)
            for audit in ranked[:20]:
                sample = audit.sample.replace("|", "\\|")
                handle.write(
                    f"| `{audit.path}` | `{audit.directory}` | `{audit.suggested_relevance}` | "
                    f"{audit.text_values} | `{audit.text_keys}` | {sample} |\n"
                )
            handle.write("\n")

        handle.write("## Top Text Files\n\n")
        handle.write("| File | Category | Relevance | Text values | Text chars | Keys | Sample |\n")
        handle.write("|---|---|---|---:|---:|---|---|\n")
        top = sorted(audits, key=lambda a: (a.text_values, a.text_chars), reverse=True)
        for audit in top[:sample_limit]:
            sample = audit.sample.replace("|", "\\|")
            handle.write(
                f"| `{audit.path}` | `{audit.suggested_category}` | `{audit.suggested_relevance}` | "
                f"{audit.text_values} | {audit.text_chars} | `{audit.text_keys}` | {sample} |\n"
            )


def _review_directory(path: str) -> str:
    parts = Path(path).parts
    if len(parts) <= 1:
        return "."
    if parts[0] == "story":
        if len(parts) >= 5:
            return "/".join(parts[:4])
        return "/".join(parts[:-1])
    if parts[0] == "levels":
        if len(parts) >= 5:
            return "/".join(parts[:4])
        return "/".join(parts[:-1])
    if parts[0] == "excel":
        return "excel"
    if parts[0] == "bakemuzzledata":
        if len(parts) >= 2:
            return "/".join(parts[:2])
        return "/".join(parts[:-1])
    if parts[0] == "[uc]lua":
        if len(parts) >= 5:
            return "/".join(parts[:4])
        return "/".join(parts[:-1])
    return "/".join(parts[:-1])


def _directory_rows(files: list[FileAudit]) -> list[tuple[str, list[FileAudit]]]:
    by_dir: defaultdict[str, list[FileAudit]] = defaultdict(list)
    for file in files:
        by_dir[file.directory].append(file)
    return sorted(
        by_dir.items(),
        key=lambda item: (
            sum(file.text_values for file in item[1]),
            sum(file.bytes for file in item[1]),
        ),
        reverse=True,
    )


if __name__ == "__main__":
    raise SystemExit(main())

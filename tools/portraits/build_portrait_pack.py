"""Build a base-and-patch SQLite pack. Requires standard library + Pillow 12.3.

Run with the bundled Python using -I; no other dependencies are needed.
"""

import argparse
from contextlib import closing
from collections import defaultdict, deque
from concurrent.futures import ProcessPoolExecutor
from datetime import datetime, timezone
import io
import json
from pathlib import Path
import sqlite3
import sys

from PIL import Image, ImageChops

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fetch_arkwaifu import png_path, readonly, sprite_rows

SCHEMA = """
CREATE TABLE portrait_bases (
  base_id TEXT PRIMARY KEY,           -- '<group_id>$<body>'，如 'avg_4137_udflow_1$1'
  width   INTEGER NOT NULL,           -- 底图像素
  height  INTEGER NOT NULL,
  sprite  TEXT NOT NULL,              -- 底图本身是哪张差分（这套里句数最多的）
  webp    BLOB NOT NULL
);
CREATE TABLE portrait_images (
  sprite  TEXT PRIMARY KEY,           -- 规范写法
  base_id TEXT,                       -- NULL = 整张存在 webp 里
  x INTEGER, y INTEGER,               -- 补丁在底图上的左上角（像素）；与底图相同时 x/y/webp 都为 NULL
  width INTEGER NOT NULL, height INTEGER NOT NULL,   -- 补丁或整张图的像素
  blank   INTEGER NOT NULL,           -- 1 = 整张透明（如 char_empty#1$1），什么都不画
  webp    BLOB
);
CREATE TABLE pack_manifest (key TEXT PRIMARY KEY, value TEXT NOT NULL);
"""


def load_group(cache, rows, height):
    images = {}
    bounds = []
    for sprite, *_ in rows:
        with Image.open(png_path(cache, sprite)) as image:
            images[sprite] = image.convert('RGBA')
        box = images[sprite].getchannel('A').getbbox()
        if box:
            bounds.append(box)
    if not bounds:
        return images, set(images)
    box = (min(b[0] for b in bounds), min(b[1] for b in bounds), max(b[2] for b in bounds), max(b[3] for b in bounds))
    blank = {s for s, image in images.items() if image.getchannel('A').getbbox() is None}
    width, old_height = box[2] - box[0], box[3] - box[1]
    size = (max(1, int(width * height / old_height + 0.5)), height) if old_height > height else (width, old_height)
    for sprite, image in images.items():
        cropped = image.crop(box)
        images[sprite] = cropped.resize(size, Image.Resampling.LANCZOS) if cropped.size != size else cropped
    return images, blank


def encode(image, quality):
    output = io.BytesIO()
    image.save(output, 'WEBP', quality=quality, method=6)
    return output.getvalue()


def difference_box(image, base):
    channels = ImageChops.difference(image, base).split()
    mask = channels[0].point(lambda v: 255 if v > 6 else 0)
    for channel in channels[1:]:
        mask = ImageChops.lighter(mask, channel.point(lambda v: 255 if v > 6 else 0))
    box = mask.getbbox()
    if box is None:
        return None
    return (max(0, box[0] - 4), max(0, box[1] - 4), min(base.width, box[2] + 4), min(base.height, box[3] + 4))


def prepare_group(cache, key, members, height):
    group, body = key
    images, blank = load_group(cache, members, height)
    base_sprite = min(members, key=lambda row: (-row[3], row[0]))[0]
    base = images[base_sprite]
    base_id = f'{group}${body}'
    base_row = None
    if len(blank) < len(members):
        base_row = (base_id, base.width, base.height, base_sprite, encode(base, 80))
    image_rows = []
    for sprite, *_ in members:
        image = images[sprite]
        data, x, y, link = None, None, None, base_id
        width, h = image.size
        if sprite in blank:
            kind, link, width, h = 'blank', None, 0, 0
        else:
            box = difference_box(image, base)
            if box is None:
                kind = 'same'
            elif (box[2] - box[0]) * (box[3] - box[1]) <= base.width * base.height * 0.5:
                kind = 'patches'
                x, y = box[:2]
                patch = image.crop(box)
                width, h = patch.size
                data = encode(patch, 85)
            else:
                kind, link = 'full', None
                data = encode(image, 80)
        image_rows.append((kind, (sprite, link, x, y, width, h, int(kind == 'blank'), data)))
    return base_row, image_rows


def prepared_groups(cache, grouped, height):
    # Bound decoded-image memory and consume results in deterministic group order.
    items = iter(sorted(grouped.items()))
    pending = deque()
    with ProcessPoolExecutor(max_workers=4) as pool:
        def submit_next():
            item = next(items, None)
            if item is not None:
                key, members = item
                pending.append(pool.submit(prepare_group, cache, key, members, height))

        for _ in range(4):
            submit_next()
        while pending:
            yield pending.popleft().result()
            submit_next()


def build(kb, cache, out, groups=None, height=800):
    if height <= 0:
        raise ValueError('height must be positive')
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.unlink(missing_ok=True)
    part = out.with_name(out.name + '.part')
    part.unlink(missing_ok=True)
    rows = sprite_rows(kb, groups)
    grouped = defaultdict(list)
    missing = []
    for row in rows:
        if png_path(cache, row[0]).is_file():
            grouped[(row[1], row[2])].append(row)
        else:
            missing.append(row[0])
    index = json.loads((Path(cache) / 'index.json').read_text(encoding='utf-8'))
    with closing(readonly(kb)) as source:
        commit = source.execute("SELECT value FROM gamedata_manifest WHERE key='source_arknights_commit'").fetchone()[0]
    stats = {'groups': len(grouped), 'bases': 0, 'base_bytes': 0, 'patches': 0, 'patch_bytes': 0, 'full': 0, 'full_bytes': 0, 'same': 0, 'blank': 0, 'missing': len(missing)}
    largest = []
    db = sqlite3.connect(part)
    try:
        db.executescript(SCHEMA)
        for number, (base_row, image_rows) in enumerate(prepared_groups(cache, grouped, height), 1):
            if base_row:
                db.execute('INSERT INTO portrait_bases VALUES (?, ?, ?, ?, ?)', base_row)
                stats['bases'] += 1
                stats['base_bytes'] += len(base_row[-1])
            for kind, row in image_rows:
                sprite, *_, data = row
                db.execute('INSERT INTO portrait_images VALUES (?, ?, ?, ?, ?, ?, ?, ?)', row)
                stats[kind] += 1
                if data:
                    stats['patch_bytes' if kind == 'patches' else 'full_bytes'] += len(data)
                largest.append({'sprite': sprite, 'type': kind, 'bytes': len(data) if data else 0})
            db.commit()
            if number % 50 == 0 or number == len(grouped):
                print(f'groups={number}/{len(grouped)}', flush=True)
        manifest = {'pack_version': 1, 'source': 'arkwaifu', 'source_artwork_version': index['artwork_version'], 'kb_commit': commit, 'sprite_count': len(rows) - len(missing), 'missing_count': len(missing), 'max_height': height, 'built_at': datetime.now(timezone.utc).isoformat()}
        db.executemany('INSERT INTO pack_manifest VALUES (?, ?)', [(k, str(v)) for k, v in manifest.items()])
        db.commit()
        db.execute('VACUUM')
    finally:
        db.close()
    part.replace(out)
    stats['file_bytes'] = out.stat().st_size
    stats['largest_images'] = sorted(largest, key=lambda row: (-row['bytes'], row['sprite']))[:10]
    stats['missing_sprites'] = missing
    Path(str(out) + '.report.json').write_text(json.dumps(stats, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(stats, ensure_ascii=False, indent=2), flush=True)
    return stats


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('kb', 'cache', 'out'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--groups')
    parser.add_argument('--height', type=int, default=800)
    args = parser.parse_args()
    if args.height <= 0:
        parser.error('--height must be positive')
    build(**vars(args))


if __name__ == '__main__':
    main()

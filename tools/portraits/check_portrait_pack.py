"""Reconstruct and inspect a portrait pack. Requires standard library + Pillow 12.3."""

import argparse
from contextlib import closing
from collections import defaultdict
import io
import json
from pathlib import Path
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageStat

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_portrait_pack import load_group
from fetch_arkwaifu import readonly


def decode(data):
    with Image.open(io.BytesIO(data)) as image:
        return image.convert('RGBA')


def reconstruct(db, row):
    sprite, base_id, x, y, width, height, blank, data = row
    if blank:
        return Image.new('RGBA', (max(1, width), max(1, height)))
    if base_id is None:
        return decode(data)
    image = decode(db.execute('SELECT webp FROM portrait_bases WHERE base_id=?', (base_id,)).fetchone()[0])
    if data is not None:
        image.paste(decode(data), (x, y))
    return image


def image_kind(row):
    if row[6]:
        return 'blank'
    return 'full' if row[1] is None else ('patch' if row[7] is not None else 'same')


def check(pack, cache, sample=60, seed=20261025, sheet=None):
    rng = random.Random(seed)
    with closing(readonly(pack)) as db:
        rows = db.execute('SELECT * FROM portrait_images ORDER BY sprite').fetchall()
        max_height = int(db.execute("SELECT value FROM pack_manifest WHERE key='max_height'").fetchone()[0])
        categories = defaultdict(list)
        members = defaultdict(list)
        for row in rows:
            categories[image_kind(row)].append(row)
            group, suffix = row[0].split('#', 1)
            body = int(suffix.split('$', 1)[1])
            members[(group, body)].append((row[0], group, body, 0))
        selected = []
        for kind in ('patch', 'full', 'same'):
            selected.extend(rng.sample(categories[kind], min(10, len(categories[kind]))))
        chosen = {row[0] for row in selected}
        rest = [row for row in rows if row[0] not in chosen and not row[6]]
        selected.extend(rng.sample(rest, min(max(0, sample - len(selected)), len(rest))))
        references = {}
        metrics = defaultdict(list)
        previews = defaultdict(list)
        for row in selected:
            sprite = row[0]
            group, suffix = sprite.split('#', 1)
            key = (group, int(suffix.split('$', 1)[1]))
            if key not in references:
                references[key] = load_group(cache, members[key], max_height)[0]
            reference = references[key][sprite]
            actual = reconstruct(db, row)
            if reference.size != actual.size:
                raise ValueError(f'{sprite}: reconstructed size {actual.size} != reference {reference.size}')
            diff = ImageChops.difference(reference, actual)
            stat = ImageStat.Stat(diff)
            result = {'sprite': sprite, 'rgb_mae': sum(stat.mean[:3]) / 3, 'rgb_max': max(high for _, high in diff.getextrema()[:3]), 'alpha_mae': stat.mean[3]}
            kind = image_kind(row)
            metrics[kind].append(result)
            if len(previews[kind]) < 4:
                previews[kind].append((sprite, reference.copy(), actual))
        report = {}
        for kind in ('patch', 'full', 'same'):
            values = metrics[kind]
            report[kind] = {'count': len(values), 'rgb_mae': sum(v['rgb_mae'] for v in values) / len(values) if values else 0, 'rgb_max_mean': sum(v['rgb_max'] for v in values) / len(values) if values else 0, 'alpha_mae': sum(v['alpha_mae'] for v in values) / len(values) if values else 0, 'worst_five': sorted(values, key=lambda v: (-v['rgb_mae'], v['sprite']))[:5]}
        if sheet:
            tiles = []
            for kind in ('patch', 'full', 'same'):
                for sprite, reference, actual in previews[kind]:
                    width = max(1, round(reference.width * 300 / reference.height))
                    tile = Image.new('RGB', (max(460, width * 2), 330), 'white')
                    ImageDraw.Draw(tile).text((4, 4), f'{kind}: {sprite} | reference / restored', fill='black')
                    for offset, image in ((0, reference), (width, actual)):
                        image = image.resize((width, 300), Image.Resampling.LANCZOS)
                        tile.paste(image, (offset, 30), image)
                    tiles.append(tile)
            if tiles:
                cell_width = max(tile.width for tile in tiles)
                canvas = Image.new('RGB', (cell_width * 3, ((len(tiles) + 2) // 3) * 330), 'white')
                for i, tile in enumerate(tiles):
                    canvas.paste(tile, ((i % 3) * cell_width, (i // 3) * 330))
                Path(sheet).parent.mkdir(parents=True, exist_ok=True)
                canvas.save(sheet)
    output = json.dumps(report, indent=2)
    print(output, flush=True)
    Path(str(pack) + '.check.json').write_text(output + '\n', encoding='utf-8')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pack', required=True)
    parser.add_argument('--cache', required=True)
    parser.add_argument('--sample', type=int, default=60)
    parser.add_argument('--seed', type=int, default=20261025)
    parser.add_argument('--sheet', required=True)
    check(**vars(parser.parse_args()))


if __name__ == '__main__':
    main()

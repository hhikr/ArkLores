"""Story art processing for the portrait pack."""
from collections import Counter, deque
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
import json
from pathlib import Path
from PIL import Image, ImageStat
from fetch_arkwaifu import art_path, art_key, readonly


def resize_art(image, category):
    w, h = image.size
    if category == 'illustration' and h <= w * 1.3:
        scale = min(1, 1600 / max(w, h))
    else:
        scale = min(1, 1280 / w)
    rgba = image.convert('RGBA')
    image = rgba if rgba.getchannel('A').getextrema()[0] < 255 else rgba.convert('RGB')
    if scale < 1:
        image = image.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.Resampling.LANCZOS)
    return image


def solid(image):
    image = image.convert('RGBA')
    image = image.resize((64, max(1, round(image.height * 64 / image.width))), Image.Resampling.LANCZOS)
    means = ImageStat.Stat(image).mean
    return int(all(all(abs(pixel[i] - means[i]) <= 6 for i in range(4)) for pixel in image.get_flattened_data()))


def compose(images, layout):
    if layout == 'row': positions = [(i, 0) for i in range(len(images))]
    elif layout == 'column': positions = [(0, i) for i in range(len(images))]
    elif layout == 'grid2': positions = [(i % 2, i // 2) for i in range(len(images))]
    else: raise ValueError(f'Unknown composite layout: {layout}')
    columns = [max((im.width for im, (x, _) in zip(images, positions) if x == col), default=0) for col in range(max(x for x, _ in positions) + 1)]
    rows = [max((im.height for im, (_, y) in zip(images, positions) if y == row), default=0) for row in range(max(y for _, y in positions) + 1)]
    result = Image.new('RGBA', (sum(columns), sum(rows)))
    for im, (x, y) in zip(images, positions): result.paste(im, (sum(columns[:x]), sum(rows[:y])))
    return result


def titles(source):
    result = {}
    with closing(readonly(source)) as db:
        rows = db.execute("""SELECT r.asset_id, g.name, g.description, g.gallery_id, g.group_id, g.position
          FROM gallery_narrative_asset_references r JOIN gallery_groups g USING(locale, gallery_id, group_id)
          WHERE r.locale='CN' ORDER BY g.position, g.gallery_id, g.group_id, r.position""")
        for asset, name, description, gallery, group, _ in rows:
            asset = ''.join(asset.split()).lower()
            for part in [asset, *asset.split('/')]:
                result.setdefault(part, (name, description, gallery + '/' + group))
    return result


def add_art(db, old, old_signatures, kb, cache, source, encode):
    index = json.loads((Path(cache) / 'index.json').read_text(encoding='utf-8'))
    assets, images = index['assets'], index['images']
    with closing(readonly(kb)) as kbdb:
        kbdb.execute('SELECT 1 FROM story_art_events LIMIT 1')
    title_map = titles(source)
    counts = Counter()
    missing_file = Path(cache) / 'missing.txt'
    counts['art_missing_count'] = len(missing_file.read_text(encoding='utf-8').splitlines()) if missing_file.exists() else 0
    titled = set()
    def prepare(category, image, parts, layout):
        source_images = []
        for part in parts:
            with Image.open(art_path(cache, category, part)) as im: source_images.append(im.convert('RGBA'))
        artwork = compose(source_images, layout) if len(source_images) > 1 else source_images[0]
        artwork = resize_art(artwork, category)
        return (category, image, artwork.width, artwork.height, solid(artwork), encode(artwork, 80))

    items = iter(sorted(images.items()))
    pending = deque()
    with ThreadPoolExecutor(max_workers=4) as pool:
        def submit():
            while (item := next(items, None)) is not None:
                key, entry = item
                category, image, parts, layout = (entry[k] for k in ('category', 'image_id', 'parts', 'layout'))
                part_keys = [art_key(category, p) for p in parts]
                if any(k not in assets or not art_path(cache, category, p).is_file() for k, p in zip(part_keys, parts)):
                    counts['art_missing_count'] += 1
                    continue
                signature = json.dumps({'category': category, 'sources': [[p, assets[k]['object_key'], art_path(cache, category, p).stat().st_size] for k, p in zip(part_keys, parts)], 'layout': layout if len(parts) > 1 else None, 'spec': 3}, sort_keys=True)
                group_key = 'art:' + key
                row = None
                if old is not None and old_signatures.get(group_key) == signature:
                    row = old.execute('SELECT * FROM art_images WHERE category=? AND image_id=?', (category, image)).fetchone()
                pending.append((group_key, signature, category, image, row, None if row is not None else pool.submit(prepare, category, image, parts, layout)))
                return
        for _ in range(4): submit()
        number = 0
        while pending:
            group_key, signature, category, image, row, future = pending.popleft()
            if row is None: row = future.result()
            db.execute('INSERT INTO art_images VALUES (?, ?, ?, ?, ?, ?)', row)
            db.execute('INSERT INTO pack_groups VALUES (?, ?)', (group_key, signature))
            if image in title_map and image not in titled:
                db.execute('INSERT INTO art_titles VALUES (?, ?, ?, ?)', (image, *title_map[image]))
                titled.add(image)
                counts['title_count'] += 1
            counts['art_count'] += 1
            counts[category + '_count'] += 1
            counts['solid_count'] += row[4]
            number += 1
            if number % 50 == 0 or number == len(images): print(f'art={number}/{len(images)}', flush=True)
            submit()
    return {key: counts[key] for key in ('art_count', 'background_count', 'illustration_count', 'item_count', 'solid_count', 'title_count', 'art_missing_count')}

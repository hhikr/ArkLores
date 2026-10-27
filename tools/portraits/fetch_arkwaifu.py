"""Fetch composed portraits once. Requires Python 3.12 standard library only."""

import argparse
from contextlib import closing
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import http.client
from pathlib import Path
import shutil
import sqlite3
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

ORIGIN = 'https://arkwaifu.sgp1.cdn.digitaloceanspaces.com/'
USER_AGENT = 'ArkLores portrait pack builder (https://github.com/hhikr/ArkLores)'


def readonly(path):
    return sqlite3.connect(Path(path).resolve().as_uri() + '?mode=ro', uri=True)


def asset_url(key):
    return ORIGIN + urllib.parse.quote(key, safe='/')


def png_path(cache, sprite):
    return Path(cache) / 'png' / (urllib.parse.quote(sprite, safe='') + '.png')


def sprite_rows(kb, groups=None, limit=None):
    with closing(readonly(kb)) as db:
        query = 'SELECT sprite, group_id, body, lines FROM portrait_sprites'
        args = []
        if groups:
            args = groups.split(',')
            query += ' WHERE group_id IN (' + ','.join('?' for _ in args) + ')'
        query += ' ORDER BY sprite'
        if limit is not None:
            query += ' LIMIT ?'
            args.append(limit)
        return db.execute(query, args).fetchall()


class Downloader:
    def __init__(self):
        self.lock = threading.Lock()
        self.paused_until = 0.0

    def wait(self):
        while True:
            with self.lock:
                delay = self.paused_until - time.monotonic()
            if delay <= 0:
                return
            time.sleep(delay)

    def download(self, url, dest, size=None):
        part = dest.with_name(dest.name + '.part')
        dest.parent.mkdir(parents=True, exist_ok=True)
        for attempt in range(4):
            self.wait()
            try:
                offset = part.stat().st_size if part.exists() else 0
                if size is not None and offset >= size:
                    part.unlink(missing_ok=True)
                    offset = 0
                headers = {'User-Agent': USER_AGENT}
                if offset:
                    headers['Range'] = f'bytes={offset}-'
                request = urllib.request.Request(url, headers=headers)
                with urllib.request.urlopen(request, timeout=120) as response:
                    resumed = offset and getattr(response, 'status', None) == 206
                    with part.open('ab' if resumed else 'wb') as output:
                        shutil.copyfileobj(response, output)
                if size is not None and part.stat().st_size != size:
                    raise OSError(f'Wrong size: {part.stat().st_size} != {size}')
                part.replace(dest)
                return True
            except (OSError, urllib.error.URLError, http.client.HTTPException) as error:
                if isinstance(error, urllib.error.HTTPError) and error.code in (429, 503):
                    with self.lock:
                        self.paused_until = max(self.paused_until, time.monotonic() + 60)
                print(f'Request failed ({attempt + 1}/4): {url}: {error}', flush=True)
                if attempt < 3:
                    time.sleep((5, 15, 45)[attempt])
        return False


def fetch(kb, cache, arkwaifu_db=None, workers=4, limit=None, groups=None):
    cache = Path(cache)
    cache.mkdir(parents=True, exist_ok=True)
    downloader = Downloader()
    source = Path(arkwaifu_db) if arkwaifu_db else cache / 'arkwaifu.sqlite3'
    if not source.exists():
        if arkwaifu_db:
            raise FileNotFoundError(source)
        if not downloader.download(ORIGIN + 'arkwaifu.sqlite3', source):
            raise RuntimeError('Could not download Arkwaifu database')
    rows = sprite_rows(kb, groups, limit)
    assets, missing = {}, []
    with closing(readonly(source)) as db:
        version = db.execute("SELECT res_version FROM unit_versions WHERE unit = 'artwork'").fetchone()[0]
        print(f'artwork_version={version}', flush=True)
        # Arkwaifu keeps the script's spelling (avg_1029_Yato2_1, AVG_char_…);
        # the knowledge base's names are canonical: no whitespace, lower case.
        by_name = {}
        for asset_id, *row in db.execute("SELECT asset_id, object_key, size, width, height FROM narrative_image_assets WHERE category = 'character' ORDER BY asset_id"):
            by_name.setdefault(''.join(asset_id.split()).lower(), row)
        for sprite, *_ in rows:
            row = by_name.get(sprite)
            if row is None:
                missing.append(sprite)
            else:
                assets[sprite] = dict(zip(('object_key', 'size', 'width', 'height'), row))
    index_path = cache / 'index.json'
    old = json.loads(index_path.read_text(encoding='utf-8')) if index_path.exists() else {}
    completed = dict(old.get('sprites', {}))
    failed = []
    counts = {'total': len(rows), 'downloaded': 0, 'skipped': 0, 'missing': len(missing), 'failed': 0, 'downloaded_bytes': 0}
    start = time.monotonic()

    def one(sprite, metadata):
        path = png_path(cache, sprite)
        if path.exists():
            previous = completed.get(sprite)
            if path.stat().st_size == metadata['size'] and (previous is None or previous['object_key'] == metadata['object_key']):
                return sprite, 'skipped'
            path.unlink()
        previous = completed.get(sprite)
        if previous is not None and previous['object_key'] != metadata['object_key']:
            path.with_name(path.name + '.part').unlink(missing_ok=True)
        ok = downloader.download(asset_url(metadata['object_key']), path, metadata['size'])
        return sprite, 'downloaded' if ok else 'failed'

    def save():
        # Keep completed entries across filtered and interrupted runs.
        temp = index_path.with_suffix('.json.part')
        temp.write_text(json.dumps({'artwork_version': version, 'sprites': dict(sorted(completed.items()))}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        temp.replace(index_path)

    try:
        with ThreadPoolExecutor(max_workers=max(1, min(4, workers))) as pool:
            futures = [pool.submit(one, sprite, metadata) for sprite, metadata in assets.items()]
            for done, future in enumerate(as_completed(futures), 1):
                sprite, result = future.result()
                counts[result] += 1
                if result == 'failed':
                    failed.append(sprite)
                    completed.pop(sprite, None)
                else:
                    completed[sprite] = assets[sprite]
                    if result == 'downloaded':
                        counts['downloaded_bytes'] += assets[sprite]['size']
                if done % 200 == 0 or done == len(futures):
                    elapsed = time.monotonic() - start
                    print(f'{done}/{len(assets)} bytes={counts["downloaded_bytes"]} eta_seconds={elapsed / done * (len(assets) - done):.0f}', flush=True)
                    save()
    finally:
        save()
        for filename, values in [('missing.txt', missing), ('failed.txt', failed)]:
            (cache / filename).write_text(''.join(s + '\n' for s in sorted(values)), encoding='utf-8')
    counts['elapsed_seconds'] = time.monotonic() - start
    counts['cached_bytes'] = sum(m['size'] for s, m in assets.items() if s in completed)
    print(json.dumps(counts, indent=2), flush=True)
    (cache / 'fetch.report.json').write_text(json.dumps(counts, indent=2) + '\n', encoding='utf-8')
    return counts




def art_key(category, name):
    return category + ':' + name


def art_path(cache, category, name):
    return png_path(Path(cache) / category, name)


def art_requests(kb, source, limit=None):
    with closing(readonly(kb)) as db:
        rows = db.execute("SELECT image, kind, layout, count(*) FROM story_art_events WHERE image IS NOT NULL GROUP BY image, kind, layout ORDER BY image").fetchall()
    layouts, kinds = {}, {}
    for image, kind, layout, count in rows:
        layouts.setdefault(image, {})[layout] = layouts.setdefault(image, {}).get(layout, 0) + count
        kinds.setdefault(image, set()).add(kind)
    with closing(readonly(source)) as db:
        assets = {}
        for asset_id, category, key, size, width, height in db.execute("SELECT asset_id, category, object_key, size, width, height FROM narrative_image_assets WHERE category != 'character' ORDER BY asset_id"):
            assets.setdefault((category, ''.join(asset_id.split()).lower()), dict(asset_id=asset_id, category=category, object_key=key, size=size, width=width, height=height))
    preferences = {'background': ('background', 'illustration', 'item'), 'cg': ('illustration', 'background', 'item'), 'item': ('item', 'illustration', 'background')}
    requests, missing, images = {}, [], {}
    for image in sorted(layouts)[:limit]:
        options = sorted(layouts[image].items(), key=lambda x: (-x[1], x[0] or ''))
        if len(options) > 1: print(f'Layout conflict: {image}: {options}', flush=True)
        layout = options[0][0]
        for kind in sorted(kinds[image]):
            if kind not in preferences: continue
            selected = None
            for category in preferences[kind]:
                parts = [image] if (category, image) in assets else image.split('/')
                if all((category, part) in assets for part in parts):
                    selected = (category, parts)
                    break
            if selected is None:
                missing.append(kind + ':' + image)
                continue
            category, parts = selected
            images[art_key(category, image)] = {'category': category, 'image_id': image, 'parts': parts, 'layout': layout}
            for part in parts:
                requests[art_key(category, part)] = assets[(category, part)]
    return requests, missing, images


def fetch_art(kb, cache, arkwaifu_db, workers=4, limit=None):
    cache = Path(cache)
    cache.mkdir(parents=True, exist_ok=True)
    assets, missing, images = art_requests(kb, arkwaifu_db, limit)
    index_path = cache / 'index.json'
    old = json.loads(index_path.read_text(encoding='utf-8')) if index_path.exists() else {}
    old_assets = old.get('assets', {})
    completed = {k: v for k, v in old_assets.items() if ':' in k}
    legacy_assets = {k: v for k, v in old_assets.items() if ':' not in k}
    downloader = Downloader()
    counts = dict(total=len(assets), downloaded=0, skipped=0, failed=0, missing=len(missing), downloaded_bytes=0)
    failed = []
    start = time.monotonic()
    def one(item):
        key, metadata = item
        category, name = key.split(':', 1)
        path = art_path(cache, category, name)
        previous = completed.get(key)
        if path.exists() and path.stat().st_size == metadata['size'] and previous and previous['object_key'] == metadata['object_key']:
            return key, 'skipped'
        # Migrate the original single-category cache only when its object key matches.
        legacy = old_assets.get(name)
        legacy_path = png_path(cache, name)
        if legacy and legacy['object_key'] == metadata['object_key'] and legacy_path.is_file() and legacy_path.stat().st_size == metadata['size']:
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(legacy_path, path)
            return key, 'skipped'
        if previous and previous['object_key'] != metadata['object_key']:
            path.with_name(path.name + '.part').unlink(missing_ok=True)
        return key, 'downloaded' if downloader.download(asset_url(metadata['object_key']), path, metadata['size']) else 'failed'
    def save():
        temp = index_path.with_suffix('.json.part')
        temp.write_text(json.dumps({'assets': dict(sorted((legacy_assets | completed).items())), 'images': images}, ensure_ascii=False, indent=2), encoding='utf-8')
        temp.replace(index_path)
    try:
        with ThreadPoolExecutor(max_workers=max(1, min(4, workers))) as pool:
            futures = [pool.submit(one, item) for item in assets.items()]
            for done, future in enumerate(as_completed(futures), 1):
                key, result = future.result()
                counts[result] += 1
                if result == 'failed':
                    failed.append(key)
                    completed.pop(key, None)
                else:
                    completed[key] = assets[key]
                    if result == 'downloaded': counts['downloaded_bytes'] += assets[key]['size']
                if done % 100 == 0 or done == len(futures):
                    print(f'art={done}/{len(assets)} bytes={counts["downloaded_bytes"]}', flush=True)
                    save()
    finally:
        save()
        for filename, values in [('missing.txt', missing), ('failed.txt', failed)]:
            (cache / filename).write_text(''.join(s + '\n' for s in sorted(values)), encoding='utf-8')
    counts['elapsed_seconds'] = time.monotonic() - start
    (cache / 'fetch.report.json').write_text(json.dumps(counts, indent=2), encoding='utf-8')
    print(json.dumps(counts, indent=2), flush=True)
    return counts

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kb', required=True)
    parser.add_argument('--cache', required=True)
    parser.add_argument('--arkwaifu-db')
    parser.add_argument('--workers', type=int, default=4)
    parser.add_argument('--limit', type=int)
    parser.add_argument('--groups')
    parser.add_argument('--art-cache', default='build/story_art_src')
    args = parser.parse_args()
    if args.limit is not None and args.limit < 0:
        parser.error('--limit must be nonnegative')
    fetch(args.kb, args.cache, args.arkwaifu_db, args.workers, args.limit, args.groups)
    if args.arkwaifu_db:
        fetch_art(args.kb, args.art_cache, args.arkwaifu_db, args.workers, args.limit)


if __name__ == '__main__':
    main()

"""Offline portrait pipeline tests. Requires standard library + Pillow 12.3.

Run: python -I -m unittest discover -s tools/portraits -p test_portrait_pack.py
"""

import contextlib
from contextlib import closing
from concurrent.futures import ThreadPoolExecutor
import io
import http.client
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
import urllib.error
from unittest.mock import patch

from PIL import Image, ImageDraw, ImageChops

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_portrait_pack import build, difference_box
from check_portrait_pack import reconstruct, check
from fetch_arkwaifu import Downloader, asset_url, fetch, png_path


class PortraitPackTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cache = self.root / 'cache'
        (self.cache / 'png').mkdir(parents=True)
        (self.cache / 'index.json').write_text(json.dumps({'artwork_version': 'fixture', 'sprites': {}}))
        self.kb = self.root / 'kb.db'
        with closing(sqlite3.connect(self.kb)) as db:
            db.executescript("""
                CREATE TABLE portrait_sprites (
                  sprite TEXT PRIMARY KEY,
                  group_id TEXT NOT NULL,
                  face INTEGER NOT NULL,
                  body INTEGER NOT NULL,
                  lines INTEGER NOT NULL
                ) WITHOUT ROWID;
                CREATE INDEX portrait_sprites_group ON portrait_sprites(group_id);
                CREATE TABLE gamedata_manifest(key TEXT PRIMARY KEY, value TEXT NOT NULL);
                INSERT INTO gamedata_manifest VALUES ('source_arknights_commit', 'fixture-commit');
            """)

    def add(self, sprite, image, lines=1):
        group, suffix = sprite.split('#')
        with closing(sqlite3.connect(self.kb)) as db:
            face, body = map(int, suffix.split('$'))
            db.execute('INSERT INTO portrait_sprites VALUES (?, ?, ?, ?, ?)', (sprite, group, face, body, lines))
            db.commit()
        if image is not None:
            image.save(png_path(self.cache, sprite))

    def run_build(self, name='pack.db', **kwargs):
        out = self.root / name
        with contextlib.redirect_stdout(io.StringIO()):
            build(self.kb, self.cache, out, **kwargs)
        return out

    def test_small_patches_coordinates_and_reconstruction(self):
        base = Image.new('RGBA', (100, 100), (0, 0, 0, 255))
        self.add('unit#1$1', base, 20)
        for face, x in ((2, 20), (3, 60)):
            image = base.copy()
            ImageDraw.Draw(image).rectangle((x, 30, x + 9, 39), fill=(255, 255, 255, 255))
            self.add(f'unit#{face}$1', image)
        with closing(sqlite3.connect(self.run_build())) as db:
            self.assertEqual(db.execute('SELECT count(*) FROM portrait_bases').fetchone()[0], 1)
            rows = db.execute('SELECT * FROM portrait_images ORDER BY sprite').fetchall()
            self.assertIsNone(rows[0][7])
            for row, x in zip(rows[1:], (20, 60)):
                self.assertEqual(row[2:6], (x - 4, 26, 18, 18))
                reference = base.copy()
                ImageDraw.Draw(reference).rectangle((x, 30, x + 9, 39), fill=(255, 255, 255, 255))
                diff = ImageChops.difference(reconstruct(db, row), reference)
                self.assertLessEqual(max(high for _, high in diff.getextrema()), 3)

    def test_full_blank_tie_and_determinism(self):
        self.add('unit#2$1', Image.new('RGBA', (80, 120), 'white'))
        self.add('unit#1$1', Image.new('RGBA', (80, 120), 'black'))
        self.add('unit#3$1', Image.new('RGBA', (80, 120)))
        self.add('empty#1$1', Image.new('RGBA', (80, 120)))
        self.add('missing#1$1', None)
        outputs = [self.run_build(name, height=60) for name in ('a.db', 'b.db')]
        with closing(sqlite3.connect(outputs[0])) as a, closing(sqlite3.connect(outputs[1])) as b:
            for table in ('portrait_bases', 'portrait_images'):
                self.assertEqual(a.execute(f'SELECT * FROM {table} ORDER BY 1').fetchall(), b.execute(f'SELECT * FROM {table} ORDER BY 1').fetchall())
            self.assertEqual(a.execute('SELECT sprite FROM portrait_bases').fetchone()[0], 'unit#1$1')
            self.assertIsNone(a.execute("SELECT base_id FROM portrait_images WHERE sprite='unit#2$1'").fetchone()[0])
            for sprite in ('unit#3$1', 'empty#1$1'):
                row = a.execute('SELECT * FROM portrait_images WHERE sprite=?', (sprite,)).fetchone()
                self.assertEqual(row[1:], (None, None, None, 0, 0, 1, None))
            self.assertEqual(a.execute("SELECT value FROM pack_manifest WHERE key='missing_count'").fetchone()[0], '1')

    def test_unchanged_sets_are_copied_from_the_previous_pack(self):
        base = Image.new('RGBA', (60, 60), (0, 0, 0, 255))
        self.add('keep#1$1', base, 5)
        self.add('keep#2$1', Image.new('RGBA', (60, 60), (255, 0, 0, 255)))
        self.add('grow#1$1', base, 5)
        first = self.run_build('pack.db')
        with closing(sqlite3.connect(first)) as db:
            before = {t: db.execute(f'SELECT * FROM {t} ORDER BY 1').fetchall() for t in ('portrait_bases', 'portrait_images')}
        self.add('grow#2$1', Image.new('RGBA', (60, 60), (0, 0, 255, 255)))
        with patch('build_portrait_pack.prepare_group', wraps=__import__('build_portrait_pack').prepare_group) as encode:
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                # A thread pool so the patched function is the one called.
                with patch('build_portrait_pack.ProcessPoolExecutor', ThreadPoolExecutor):
                    stats = build(self.kb, self.cache, first)
        self.assertEqual([call.args[1] for call in encode.call_args_list], [('grow', 1)])
        self.assertEqual(stats['reused_groups'], 1)
        with closing(sqlite3.connect(first)) as db:
            for table in ('portrait_bases', 'portrait_images'):
                rows = db.execute(f"SELECT * FROM {table} WHERE {'base_id' if table == 'portrait_bases' else 'sprite'} LIKE 'keep%' ORDER BY 1").fetchall()
                self.assertEqual(rows, [r for r in before[table] if r[0].startswith('keep')])
            self.assertEqual(db.execute("SELECT count(*) FROM portrait_images WHERE sprite LIKE 'grow%'").fetchone()[0], 2)
        # The same result as building from nothing.
        fresh = self.run_build('fresh.db', previous=self.root / 'none.db')
        with closing(sqlite3.connect(first)) as a, closing(sqlite3.connect(fresh)) as b:
            for table in ('portrait_bases', 'portrait_images', 'pack_groups'):
                self.assertEqual(a.execute(f'SELECT * FROM {table} ORDER BY 1').fetchall(), b.execute(f'SELECT * FROM {table} ORDER BY 1').fetchall())

    def test_rgb_difference_without_alpha_difference(self):
        base = Image.new('RGBA', (100, 100), (10, 10, 10, 255))
        image = base.copy()
        image.putpixel((50, 50), (17, 10, 10, 255))
        self.assertEqual(difference_box(image, base), (46, 46, 55, 55))
        image.putpixel((50, 50), (16, 10, 10, 255))
        self.assertIsNone(difference_box(image, base))

    def test_resize_width_rounds_half_up(self):
        self.add('unit#1$1', Image.new('RGBA', (5, 4), 'white'))
        with closing(sqlite3.connect(self.run_build(height=2))) as db:
            self.assertEqual(db.execute('SELECT width, height FROM portrait_bases').fetchone(), (3, 2))

    def test_paste_replaces_transparent_patch(self):
        from build_portrait_pack import encode
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        db.execute('CREATE TABLE portrait_bases(base_id TEXT, webp BLOB)')
        db.execute('INSERT INTO portrait_bases VALUES (?, ?)', ('unit$1', encode(Image.new('RGBA', (10, 10), 'white'), 80)))
        row = ('unit#2$1', 'unit$1', 3, 4, 2, 2, 0, encode(Image.new('RGBA', (2, 2)), 85))
        self.assertEqual(reconstruct(db, row).getpixel((3, 4))[3], 0)

    def test_check_reference_uses_group_union(self):
        base = Image.new('RGBA', (100, 100))
        ImageDraw.Draw(base).rectangle((10, 10, 60, 90), fill='white')
        self.add('unit#1$1', base, 10)
        image = base.copy()
        ImageDraw.Draw(image).rectangle((80, 10, 90, 90), fill='white')
        self.add('unit#2$1', image)
        out = self.run_build(height=60)
        with contextlib.redirect_stdout(io.StringIO()):
            result = check(out, self.cache, sheet=self.root / 'sheet.png')
        self.assertEqual(result['same']['count'], 1)
        self.assertTrue((self.root / 'sheet.png').is_file())

    def test_url_double_encoding(self):
        self.assertEqual(asset_url('ART/x/composition/character/avg_1_1%231%241.png'), 'https://arkwaifu.sgp1.cdn.digitaloceanspaces.com/ART/x/composition/character/avg_1_1%25231%25241.png')

    def test_retry_intervals_and_global_throttle(self):
        downloader = Downloader()
        error = urllib.error.HTTPError('https://example.invalid', 503, 'busy', {}, None)
        with patch('fetch_arkwaifu.urllib.request.urlopen', side_effect=error) as request, patch('fetch_arkwaifu.time.sleep') as sleep, patch.object(downloader, 'wait'), contextlib.redirect_stdout(io.StringIO()):
            self.assertFalse(downloader.download('https://example.invalid', self.root / 'asset.png', 3))
        self.assertEqual(request.call_count, 4)
        self.assertEqual([call.args[0] for call in sleep.call_args_list], [5, 15, 45])
        self.assertGreater(downloader.paused_until, 0)
        request_headers = request.call_args.args[0].headers
        self.assertIn('ArkLores portrait pack builder', request_headers['User-agent'])

    def test_download_validates_size_and_replaces_part(self):
        downloader = Downloader()
        destination = self.root / 'asset.png'
        with patch('fetch_arkwaifu.urllib.request.urlopen', side_effect=lambda *args, **kwargs: io.BytesIO(b'png')), patch('fetch_arkwaifu.time.sleep') as sleep, contextlib.redirect_stdout(io.StringIO()):
            self.assertFalse(downloader.download('https://example.invalid', destination, 4))
            self.assertFalse(destination.exists())
            self.assertTrue(downloader.download('https://example.invalid', destination, 3))
        self.assertEqual(destination.read_bytes(), b'png')
        self.assertFalse(Path(str(destination) + '.part').exists())
        self.assertEqual(sleep.call_count, 3)

    def test_download_resumes_partial_response(self):
        destination = self.root / 'asset.png'
        Path(str(destination) + '.part').write_bytes(b'ab')
        response = io.BytesIO(b'cd')
        response.status = 206
        with patch('fetch_arkwaifu.urllib.request.urlopen', return_value=response) as request:
            self.assertTrue(Downloader().download('https://example.invalid', destination, 4))
        self.assertEqual(destination.read_bytes(), b'abcd')
        self.assertEqual(request.call_args.args[0].get_header('Range'), 'bytes=2-')

    def test_truncated_http_response_is_retried(self):
        downloader = Downloader()
        destination = self.root / 'asset.png'
        with patch('fetch_arkwaifu.urllib.request.urlopen', side_effect=[http.client.IncompleteRead(b'p', 2), io.BytesIO(b'png')]), patch('fetch_arkwaifu.time.sleep') as sleep, contextlib.redirect_stdout(io.StringIO()):
            self.assertTrue(downloader.download('https://example.invalid', destination, 3))
        sleep.assert_called_once_with(5)

    def test_fetch_resume_and_missing(self):
        self.add('unit#1$1', Image.new('RGBA', (10, 10), 'white'))
        self.add('absent#1$1', None)
        size = png_path(self.cache, 'unit#1$1').stat().st_size
        source = self.root / 'source.db'
        with closing(sqlite3.connect(source)) as db:
            db.executescript("CREATE TABLE unit_versions(unit TEXT, res_version TEXT); INSERT INTO unit_versions VALUES ('artwork', 'fixture'); CREATE TABLE narrative_image_assets(category TEXT, asset_id TEXT, object_key TEXT, size INTEGER, width INTEGER, height INTEGER);")
            # Arkwaifu keeps the script's spelling; the knowledge base's is canonical.
            db.execute("INSERT INTO narrative_image_assets VALUES ('character', 'Unit #1$1', 'key', ?, 10, 10)", (size,))
            db.commit()
        with patch('fetch_arkwaifu.Downloader.download') as download, patch('fetch_arkwaifu.ThreadPoolExecutor', wraps=ThreadPoolExecutor) as pool, contextlib.redirect_stdout(io.StringIO()):
            result = fetch(self.kb, self.cache, source, workers=10)
        download.assert_not_called()
        pool.assert_called_once_with(max_workers=4)
        self.assertEqual(result['skipped'], 1)
        self.assertEqual(result['missing'], 1)
        self.assertEqual((self.cache / 'missing.txt').read_text(), 'absent#1$1\n')
        index = json.loads((self.cache / 'index.json').read_text())
        self.assertEqual(list(index['sprites']), ['unit#1$1'])

        def replacement(url, destination, expected):
            destination.write_bytes(b'x' * expected)
            return True

        png_path(self.cache, 'unit#1$1').write_bytes(b'bad')
        with patch('fetch_arkwaifu.Downloader.download', side_effect=replacement) as download, contextlib.redirect_stdout(io.StringIO()):
            result = fetch(self.kb, self.cache, source)
        self.assertEqual(result['downloaded'], 1)
        download.assert_called_once()

        index['sprites']['unit#1$1']['object_key'] = 'old-key'
        (self.cache / 'index.json').write_text(json.dumps(index))
        with patch('fetch_arkwaifu.Downloader.download', side_effect=replacement) as download, contextlib.redirect_stdout(io.StringIO()):
            result = fetch(self.kb, self.cache, source)
        self.assertEqual(result['downloaded'], 1)
        download.assert_called_once()



class StoryArtTest(unittest.TestCase):
    def test_sizes_and_transparency(self):
        from story_art import resize_art
        for category in ('background', 'item'):
            image = resize_art(Image.new('RGBA', (2560, 1000)), category)
            self.assertEqual(image.size, (2560, 1000) if category == 'item' else (1280, 500))
            self.assertEqual(image.mode, 'RGBA')
            self.assertEqual(resize_art(Image.new('RGBA', (3, 3), 'white'), category).mode, 'RGB')
        self.assertEqual(resize_art(Image.new('RGB', (2000, 1000)), 'illustration').size, (1600, 800))
        self.assertEqual(resize_art(Image.new('RGB', (1600, 4000)), 'illustration').size, (1280, 3200))
        self.assertEqual(resize_art(Image.new('RGB', (20, 30)), 'illustration').size, (20, 30))

    def test_transparency_threshold_for_all_categories(self):
        from story_art import resize_art
        for category in ('background', 'illustration', 'item'):
            with self.subTest(category=category):
                noise = Image.new('RGBA', (100, 100), (20, 30, 40, 254))
                self.assertEqual(resize_art(noise, category).mode, 'RGB')
                corner = noise.copy()
                for i in range(99): corner.putpixel((i, 0), (20, 30, 40, 0))
                self.assertEqual(resize_art(corner, category).mode, 'RGB')
                corner.putpixel((99, 0), (20, 30, 40, 0))
                self.assertEqual(resize_art(corner, category).mode, 'RGB')
                corner.putpixel((0, 1), (20, 30, 40, 249))
                self.assertEqual(resize_art(corner, category).mode, 'RGBA')
                overlay = Image.new('RGBA', (100, 100), (20, 30, 40, 0))
                self.assertEqual(resize_art(overlay, category).mode, 'RGBA')
                half = Image.new('RGBA', (100, 100), (0, 0, 0, 77))
                self.assertEqual(resize_art(half, category).mode, 'RGBA')
                threshold = Image.new('RGBA', (100, 100), (0, 0, 0, 250))
                self.assertEqual(resize_art(threshold, category).mode, 'RGB')

    def test_layouts(self):
        from story_art import compose
        images = [Image.new('RGBA', (5, 5), color) for color in ('red', 'green', 'blue', 'white')]
        self.assertEqual(compose(images[:2], 'row').size, (10, 5))
        self.assertEqual(compose(images[:2], 'column').size, (5, 10))
        grid = compose(images, 'grid2')
        self.assertEqual([grid.getpixel(p)[:3] for p in ((0, 0), (5, 0), (0, 5), (5, 5))], [(255, 0, 0), (0, 128, 0), (0, 0, 255), (255, 255, 255)])

    def test_solid(self):
        from story_art import solid
        image = Image.new('RGBA', (64, 64), (100, 100, 100, 255))
        self.assertEqual(solid(image), 1)
        image.putpixel((0, 0), (104, 100, 100, 255))
        self.assertEqual(solid(image), 1)
        ImageDraw.Draw(image).rectangle((0, 0, 31, 63), fill='black')
        self.assertEqual(solid(image), 0)

    def test_art_requests_prefers_composite_and_reports_missing(self):
        from fetch_arkwaifu import art_requests
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            kb, source = root / 'kb', root / 'source'
            with closing(sqlite3.connect(kb)) as db:
                db.executescript("CREATE TABLE story_art_events(image, layout, kind); INSERT INTO story_art_events(image,layout) VALUES ('a/b','row'),('c/d','column'),('c/d','row'),('c/d','row'),('absent',NULL);")
            with closing(sqlite3.connect(kb)) as db:
                db.execute("UPDATE story_art_events SET kind='background'")
                db.commit()
            with closing(sqlite3.connect(source)) as db:
                db.executescript("CREATE TABLE narrative_image_assets(asset_id, category, object_key, size, width, height); INSERT INTO narrative_image_assets VALUES (' A / B ','background','composite',1,1,1),('C','background','c',1,1,1),('D','background','d',1,1,1);")
            with contextlib.redirect_stdout(io.StringIO()):
                assets, missing, layouts = art_requests(kb, source)
            self.assertEqual(set(assets), {'background:a/b', 'background:c', 'background:d'})
            self.assertEqual(assets['background:a/b']['asset_id'], ' A / B ')
            self.assertEqual(missing, ['background:absent'])
            self.assertEqual(layouts['background:c/d']['layout'], 'row')

    def test_categories_follow_event_and_fallback(self):
        from fetch_arkwaifu import art_requests
        with tempfile.TemporaryDirectory() as temp:
            kb, source = Path(temp) / 'kb', Path(temp) / 'source'
            with closing(sqlite3.connect(kb)) as db:
                db.executescript("CREATE TABLE story_art_events(image, layout, kind); INSERT INTO story_art_events VALUES ('scene',NULL,'background'),('scene',NULL,'cg'),('scene',NULL,'item'),('fallback',NULL,'cg');")
            with closing(sqlite3.connect(source)) as db:
                db.executescript("CREATE TABLE narrative_image_assets(asset_id, category, object_key, size, width, height); INSERT INTO narrative_image_assets VALUES ('scene','background','bg',1,1,1),('scene','illustration','cg',1,1,1),('fallback','item','item',1,1,1);")
            assets, missing, images = art_requests(kb, source)
            self.assertEqual(set(assets), {'background:scene', 'illustration:scene', 'item:fallback'})
            self.assertEqual(set(images), {'background:scene', 'illustration:scene', 'item:fallback'})
            self.assertEqual(missing, [])

    def test_art_incremental_matches_fresh(self):
        from story_art import add_art
        from build_portrait_pack import encode
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            kb, source, cache = root / 'kb', root / 'source', root / 'cache'
            from fetch_arkwaifu import art_path
            art_path(cache, 'background', 'scene').parent.mkdir(parents=True)
            Image.new('RGBA', (16, 8), 'black').save(art_path(cache, 'background', 'scene'))
            (cache / 'index.json').write_text(json.dumps({'assets': {'background:scene': {'category': 'background', 'object_key': 'x'}}, 'images': {'background:scene': {'category': 'background', 'image_id': 'scene', 'parts': ['scene'], 'layout': None}}}), encoding='utf-8')
            with closing(sqlite3.connect(kb)) as db:
                db.execute('CREATE TABLE story_art_events(image, layout)')
                db.execute("INSERT INTO story_art_events VALUES ('scene', NULL)")
                db.commit()
            with closing(sqlite3.connect(source)) as db:
                db.executescript('CREATE TABLE gallery_groups(locale, gallery_id, group_id, position, name, description); CREATE TABLE gallery_narrative_asset_references(locale, gallery_id, group_id, position, asset_id);')
            def output():
                db = sqlite3.connect(':memory:')
                db.executescript('CREATE TABLE art_images(category, image_id, width, height, solid, webp); CREATE TABLE art_titles(image_id, title, description, group_key); CREATE TABLE pack_groups(base_id, signature);')
                return db
            first, incremental, fresh = output(), output(), output()
            self.addCleanup(first.close); self.addCleanup(incremental.close); self.addCleanup(fresh.close)
            add_art(first, None, {}, kb, cache, source, encode)
            signatures = dict(first.execute('SELECT * FROM pack_groups'))
            with patch('story_art.resize_art', side_effect=AssertionError('should reuse')):
                add_art(incremental, first, signatures, kb, cache, source, encode)
            add_art(fresh, None, {}, kb, cache, source, encode)
            legacy = {key: value.replace('\"spec\": 5', '\"spec\": 4') for key, value in signatures.items()}
            self.assertNotEqual(legacy, signatures)
            changed = output()
            self.addCleanup(changed.close)
            with patch('story_art.resize_art', wraps=__import__('story_art').resize_art) as resize:
                add_art(changed, first, legacy, kb, cache, source, encode)
                self.assertEqual(resize.call_count, 1)
            for table in ('art_images', 'art_titles', 'pack_groups'):
                self.assertEqual(incremental.execute(f'SELECT * FROM {table}').fetchall(), fresh.execute(f'SELECT * FROM {table}').fetchall())

    def test_two_categories_keep_distinct_images_and_alpha(self):
        from fetch_arkwaifu import art_path
        from story_art import add_art
        from build_portrait_pack import encode
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); kb, source, cache = root / 'kb', root / 'source', root / 'cache'
            assets, images = {}, {}
            for category, color in [('background', 'white'), ('illustration', (255, 0, 0, 0))]:
                path = art_path(cache, category, 'scene'); path.parent.mkdir(parents=True, exist_ok=True)
                Image.new('RGBA', (8, 8), color).save(path)
                key = category + ':scene'
                assets[key] = {'object_key': key}
                images[key] = {'category': category, 'image_id': 'scene', 'parts': ['scene'], 'layout': None}
            (cache / 'index.json').write_text(json.dumps({'assets': assets, 'images': images}), encoding='utf-8')
            with closing(sqlite3.connect(kb)) as db:
                db.execute('CREATE TABLE story_art_events(image, kind, layout)')
            with closing(sqlite3.connect(source)) as db:
                db.executescript("CREATE TABLE gallery_groups(locale, gallery_id, group_id, position, name, description); CREATE TABLE gallery_narrative_asset_references(locale, gallery_id, group_id, position, asset_id); INSERT INTO gallery_groups VALUES('CN','g','a',0,'title','desc'); INSERT INTO gallery_narrative_asset_references VALUES('CN','g','a',0,'scene');")
            db = sqlite3.connect(':memory:'); self.addCleanup(db.close)
            db.executescript('CREATE TABLE art_images(category, image_id, width, height, solid, webp, PRIMARY KEY(category,image_id)); CREATE TABLE art_titles(image_id PRIMARY KEY, title, description, group_key); CREATE TABLE pack_groups(base_id PRIMARY KEY, signature);')
            add_art(db, None, {}, kb, cache, source, encode)
            rows = db.execute('SELECT category, webp FROM art_images ORDER BY category').fetchall()
            self.assertEqual([row[0] for row in rows], ['background', 'illustration'])
            with Image.open(io.BytesIO(rows[1][1])) as image:
                self.assertLess(image.convert('RGBA').getchannel('A').getextrema()[0], 255)
            self.assertEqual(db.execute('SELECT count(*) FROM art_titles').fetchone()[0], 1)

    def test_titles_split_and_lowest_position(self):
        from story_art import titles
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'db'
            with closing(sqlite3.connect(path)) as db:
                db.executescript("""CREATE TABLE gallery_groups(locale, gallery_id, group_id, position, name, description);
                    CREATE TABLE gallery_narrative_asset_references(locale, gallery_id, group_id, position, asset_id);
                    INSERT INTO gallery_groups VALUES ('CN','a','one',3,'late','late desc'), ('CN','b','two',1,'early','desc');
                    INSERT INTO gallery_narrative_asset_references VALUES ('CN','a','one',0,'A/B'), ('CN','b','two',0,'A/B');""")
                db.commit()
            result = titles(path)
            for key in ('a', 'b', 'a/b'):
                self.assertEqual(result[key], ('early', 'desc', 'b/two'))

class StoryArtLayersTest(unittest.TestCase):
    def test_item_keeps_original_pixels_and_alpha(self):
        from story_art import resize_art
        image = Image.new('RGBA', (1851, 900), (0, 0, 0, 77))
        result = resize_art(image, 'item')
        self.assertEqual(result.size, image.size)
        self.assertEqual(result.mode, 'RGBA')
        self.assertEqual(result.getpixel((0, 0)), (0, 0, 0, 77))
        self.assertEqual(resize_art(image, 'background').width, 1280)

if __name__ == '__main__':
    unittest.main()

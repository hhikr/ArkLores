"""Tests of what decides whether an update goes out. Standard library only.

fcntl does not exist on Windows; a stand-in lets the tests run there too.
"""
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import types
import unittest

sys.modules.setdefault('fcntl', types.ModuleType('fcntl'))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import kb_bot


def make_db(path, lines=(('a', 0, 'x'),), kinds=('main',), types_=('story',), sprites=('s1',), images=('i1',)):
    db = sqlite3.connect(path)
    db.executescript("""
      CREATE TABLE story_lines (id INTEGER PRIMARY KEY, story_id TEXT, line_index INTEGER, content TEXT);
      CREATE TABLE collections (id TEXT PRIMARY KEY, kind TEXT, updated_at TEXT);
      CREATE TABLE entries (id TEXT PRIMARY KEY, type TEXT);
      CREATE TABLE portrait_sprites (sprite TEXT PRIMARY KEY);
      CREATE TABLE story_art_events (image TEXT);
    """)
    db.executemany('INSERT INTO story_lines (story_id, line_index, content) VALUES (?, ?, ?)', lines)
    db.executemany('INSERT INTO collections VALUES (?, ?, ?)', [(k, k, path) for k in kinds])
    db.executemany('INSERT INTO entries VALUES (?, ?)', [(t, t) for t in types_])
    db.executemany('INSERT INTO portrait_sprites VALUES (?)', [(s,) for s in sprites])
    db.executemany('INSERT INTO story_art_events VALUES (?)', [(i,) for i in images] + [(None,)])
    db.commit()
    db.close()
    return path


class ChecksTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)

    def db(self, name, **kwargs):
        return make_db(str(Path(self.dir.name) / name), **kwargs)

    def test_same_rows_in_another_order_are_no_change(self):
        old = self.db('old.db', lines=[('a', 0, 'x'), ('a', 1, 'y')])
        new = self.db('new.db', lines=[('a', 1, 'y'), ('a', 0, 'x')])
        self.assertEqual(kb_bot.changed_tables(old, new), [])

    def test_a_changed_line_is_a_change(self):
        old = self.db('old.db', lines=[('a', 0, 'x')])
        new = self.db('new.db', lines=[('a', 0, 'z')])
        self.assertEqual(kb_bot.changed_tables(old, new), ['story_lines'])

    def test_lost_rows_are_a_problem(self):
        old = self.db('old.db', lines=[('a', i, 'x') for i in range(200)])
        new = self.db('new.db', lines=[('a', i, 'x') for i in range(190)])
        problems, counts = kb_bot.check_update(old, new)
        self.assertEqual(len(problems), 1)
        self.assertIn('story_lines', problems[0])
        self.assertEqual(counts['after']['story_lines'], 190)

    def test_a_few_lost_rows_are_not(self):
        old = self.db('old.db', lines=[('a', i, 'x') for i in range(1000)])
        new = self.db('new.db', lines=[('a', i, 'x') for i in range(995)])
        self.assertEqual(kb_bot.check_update(old, new)[0], [])

    def test_a_new_kind_is_a_problem(self):
        old = self.db('old.db')
        new = self.db('new.db', kinds=('main', 'brand_new'))
        problems, _ = kb_bot.check_update(old, new)
        self.assertIn('brand_new', problems[0])

    def test_art_needed_counts_only_new_names(self):
        old = self.db('old.db', sprites=('s1', 's2'), images=('i1',))
        new = self.db('new.db', sprites=('s2', 's3', 's4'), images=('i1', 'i2'))
        self.assertEqual(kb_bot.art_needed(old, new), (2, 1))


class PublishTest(unittest.TestCase):
    def test_a_pack_goes_out_only_when_it_shows_more(self):
        before = {'sprite_count': 10, 'art_count': 5, 'title_count': 1, 'missing_count': 0, 'art_missing_count': 0}
        self.assertFalse(kb_bot.pack_gained(before, dict(before)))
        self.assertTrue(kb_bot.pack_gained(before, {**before, 'art_count': 6}))

    def test_the_channel_keeps_what_was_not_updated(self):
        channel = {'arknights': {'url': 'u', 'sha256': 'a', 'commit': 'c', 'schema_version': 5, 'min_app_build': 37},
                   'endfield': {'url': 'e', 'sha256': 'b'},
                   'arknights_story_art': {'url': 'p', 'sha256': 'd', 'pack_version': 2}}
        result = kb_bot.next_channel(channel, {'sha256': 'n', 'commit': 'm', 'commit_date': 'z'})
        self.assertEqual(result['endfield'], channel['endfield'])
        self.assertEqual(result['arknights_story_art'], channel['arknights_story_art'])
        self.assertEqual(result['arknights']['min_app_build'], 37)
        self.assertEqual(result['arknights']['sha256'], 'n')
        self.assertEqual(channel['arknights']['sha256'], 'a')

    def test_the_hd_pack_follows_the_standard_one(self):
        channel = {'arknights': {'sha256': 'a'}, 'arknights_story_art': {'sha256': 's1'}}
        self.assertFalse(kb_bot.hd_behind(channel))  # none published yet
        channel['arknights_story_art_hd'] = {'sha256': 'h', 'size': 700 << 20, 'follows': 's1'}
        self.assertFalse(kb_bot.hd_behind(channel))
        result = kb_bot.next_channel(channel, pack={'sha256': 's2'})
        self.assertTrue(kb_bot.hd_behind(result))
        result = kb_bot.next_channel(result, hd={'sha256': 'h2', 'follows': 's2'})
        self.assertFalse(kb_bot.hd_behind(result))
        self.assertEqual(result['arknights_story_art_hd']['size'], 700 << 20)
        self.assertEqual(kb_bot.asset_key(kb_bot.PACK_HD), 'arknights_story_art_hd')

    def test_the_hd_pack_needs_room_for_two(self):
        channel = {'arknights_story_art_hd': {'size': 700 << 20}}
        self.assertEqual(kb_bot.room_for_hd(2 << 30, channel), (False, (1400 << 20) + (1 << 30)))
        self.assertTrue(kb_bot.room_for_hd(3 << 30, channel)[0])

    def test_the_release_body_follows(self):
        old_sha, end_sha = 'a' * 64, 'b' * 64
        body = (f'当前版本（2026-10-27）：\n| `arklores_gamedata_zh.db.gz` | 库，游戏数据：上游 `17759cc`（2026-10-08）；别的 | `{old_sha}` |\n'
                f'| `arklores_endfield_zh.db.gz` | 终末地 | `{end_sha}` |\n\n更新记录：2026-10-27 旧的；')
        new_sha = 'c' * 64
        result = kb_bot.release_body(body, '2026-11-02', '63c7cec000', '2026-11-01T02:17:15Z', new_sha, None)
        self.assertIn('当前版本（2026-11-02）', result)
        self.assertIn('上游 `63c7cec`（2026-11-01）', result)
        self.assertIn(new_sha, result)
        self.assertNotIn(old_sha, result)
        self.assertIn(end_sha, result)
        self.assertIn('更新记录：2026-11-02 明日方舟知识库自动更新到上游 `63c7cec`；2026-10-27 旧的', result)


class RedactTest(unittest.TestCase):
    def test_tokens_never_reach_the_status_file(self):
        with tempfile.TemporaryDirectory() as root:
            (Path(root) / 'status').mkdir()
            bot = kb_bot.Bot(root)
            bot.token = 'sekret-token'
            self.assertEqual(bot.redact('401 for sekret-token'), '401 for ***')


class StatusTest(unittest.TestCase):
    def test_a_failure_is_counted_and_shown_and_the_work_is_gone(self):
        with tempfile.TemporaryDirectory() as root:
            (Path(root) / 'status').mkdir()
            bot = kb_bot.Bot(root)
            (bot.work).mkdir()
            (bot.work / 'x').write_text('x')

            def boom():
                bot.state['building'] = 'abc'
                raise RuntimeError('network')
            bot.check = boom
            bot.sync_hd = lambda: self.fail('the HD pack waits for a run that went through')
            self.assertEqual(bot.main(), 1)
            self.assertFalse(bot.work.exists())
            status = json.loads(bot.status_path.read_text(encoding='utf-8'))
            self.assertEqual(status['last_outcome'], 'failed')
            self.assertFalse(status['running'])
            self.assertEqual(json.loads(bot.state_path.read_text(encoding='utf-8'))['failure'], {'sha': 'abc', 'count': 1})

    def test_an_hd_failure_is_its_own(self):
        with tempfile.TemporaryDirectory() as root:
            (Path(root) / 'status').mkdir()
            bot = kb_bot.Bot(root)
            bot.check = lambda: bot.finish('idle', '没有新内容')

            def boom():
                bot.state['hd_building'] = 's2'
                bot.work.mkdir()
                raise RuntimeError('network')
            bot.sync_hd = boom
            self.assertEqual(bot.main(), 1)
            self.assertFalse(bot.work.exists())
            status = json.loads(bot.status_path.read_text(encoding='utf-8'))
            self.assertEqual(status['hd']['state'], 'failed')
            state = json.loads(bot.state_path.read_text(encoding='utf-8'))
            self.assertEqual(state['hd_failure'], {'follows': 's2', 'count': 1})
            self.assertNotIn('failure', state)


if __name__ == '__main__':
    unittest.main()

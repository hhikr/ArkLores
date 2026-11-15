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
            bot.sync_endfield = lambda: None
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
            bot.sync_endfield = lambda: None
            self.assertEqual(bot.main(), 1)
            self.assertFalse(bot.work.exists())
            status = json.loads(bot.status_path.read_text(encoding='utf-8'))
            self.assertEqual(status['hd']['state'], 'failed')
            state = json.loads(bot.state_path.read_text(encoding='utf-8'))
            self.assertEqual(state['hd_failure'], {'follows': 's2', 'count': 1})
            self.assertNotIn('failure', state)

    def test_endfield_runs_after_an_arknights_failure_and_fails_on_its_own(self):
        with tempfile.TemporaryDirectory() as root:
            (Path(root) / 'status').mkdir()
            bot = kb_bot.Bot(root)
            ran = []

            def arknights():
                bot.state['building'] = 'abc'
                raise RuntimeError('network')

            def endfield():
                ran.append(True)
                bot.state['ef_building'] = 'c0ffee'
                bot.work.mkdir()
                raise RuntimeError('site down')
            bot.check = arknights
            bot.sync_hd = lambda: self.fail('the HD pack waits for a run that went through')
            bot.sync_endfield = endfield
            self.assertEqual(bot.main(), 1)
            self.assertEqual(ran, [True])
            self.assertFalse(bot.work.exists())
            state = json.loads(bot.state_path.read_text(encoding='utf-8'))
            self.assertEqual(state['failure'], {'sha': 'abc', 'count': 1})
            self.assertEqual(state['ef_failure'], {'version': 'c0ffee', 'count': 1})
            status = json.loads(bot.status_path.read_text(encoding='utf-8'))
            self.assertEqual(status['endfield']['state'], 'failed')


class EndfieldTest(unittest.TestCase):
    def test_behind_only_for_a_newer_commit_than_the_published_data(self):
        channel = {'endfield': {'url': 'u', 'sha256': 's'}}
        self.assertTrue(kb_bot.endfield_behind(channel, 'c1', '2026-11-05T04:47:32Z'))
        # Published from data of 11-14 (the first, from another source): an
        # older commit of the repository does not replace it.
        channel['endfield']['data_date'] = '2026-11-14T02:02:38Z'
        self.assertFalse(kb_bot.endfield_behind(channel, 'c1', '2026-11-05T04:47:32Z'))
        self.assertTrue(kb_bot.endfield_behind(channel, 'c2', '2026-11-20T01:00:00Z'))
        channel['endfield']['data_commit'] = 'c2'
        self.assertFalse(kb_bot.endfield_behind(channel, 'c2', '2026-11-20T01:00:00Z'))

    def test_the_channel_keeps_arknights_and_no_commit_is_written(self):
        channel = {'arknights': {'sha256': 'a', 'commit': 'c'}, 'endfield': {'url': 'u', 'sha256': 'old', 'min_app_build': 37}}
        out = kb_bot.next_channel(channel, ef={'sha256': 'new', 'data_commit': 'c2'})
        self.assertEqual(out['arknights'], channel['arknights'])
        self.assertEqual(out['endfield'], {'url': 'u', 'sha256': 'new', 'min_app_build': 37, 'data_commit': 'c2'})
        self.assertNotIn('commit', out['endfield'])
        self.assertEqual(channel['endfield']['sha256'], 'old')

    def test_the_backup_kind_of_the_endfield_asset(self):
        self.assertEqual(kb_bot.asset_key(kb_bot.EF_GZ), 'endfield')


class TimelineTest(unittest.TestCase):
    """The Terra timeline: asked for once a day; a new revision of the page goes
    out in the published knowledge base, game data unchanged."""

    def setUp(self):
        self.root = tempfile.TemporaryDirectory()
        self.addCleanup(self.root.cleanup)
        (Path(self.root.name) / 'status').mkdir()
        self.bot = kb_bot.Bot(self.root.name)
        self.asked = []
        self.real = kb_bot.timeline_revision
        self.addCleanup(setattr, kb_bot, 'timeline_revision', self.real)

        def revision():
            self.asked.append(True)
            return '500'
        kb_bot.timeline_revision = revision
        self.channel = {'arknights': {'url': 'u', 'sha256': 'a', 'commit': 'c', 'timeline_revision': '500'}}

    def test_the_same_revision_takes_no_run_and_waits_a_day(self):
        self.assertFalse(self.bot.sync_timeline(self.channel))
        self.assertEqual(len(self.asked), 1)
        self.assertEqual(self.bot.status['timeline']['state'], 'current')
        # Checked just now: not asked again within the day.
        self.assertFalse(self.bot.sync_timeline(self.channel))
        self.assertEqual(len(self.asked), 1)

    def test_a_new_revision_takes_the_run_and_a_failure_is_counted(self):
        self.channel['arknights']['timeline_revision'] = '499'
        self.bot.fresh_work = lambda: (_ for _ in ()).throw(RuntimeError('disk'))
        self.assertTrue(self.bot.sync_timeline(self.channel))
        self.assertEqual(self.bot.state['timeline_failure'], {'revision': '500', 'count': 1})
        self.assertEqual(self.bot.status['last_outcome'], 'failed')
        self.assertNotIn('building', self.bot.state)

    def test_a_revision_that_failed_three_times_is_left_alone(self):
        self.channel['arknights'].pop('timeline_revision')
        self.bot.state['timeline_failure'] = {'revision': '500', 'count': kb_bot.MAX_FAILURES}
        self.bot.fresh_work = lambda: self.fail('not tried again')
        self.assertFalse(self.bot.sync_timeline(self.channel))

    def test_prts_out_of_reach_is_shown_and_takes_no_run(self):
        def down():
            raise OSError('timed out')
        kb_bot.timeline_revision = down
        self.assertFalse(self.bot.sync_timeline(self.channel))
        self.assertEqual(self.bot.status['timeline']['state'], 'failed')

    def test_the_published_file_is_checked_again_while_the_address_serves_the_old_one(self):
        calls = []

        def download(url, path, sha=None, on_progress=None):
            calls.append(url)
            Path(path).write_bytes(b'x')
            if len(calls) < 3:
                raise RuntimeError('SHA-256 与渠道文件不一致')
        real_download, real_sleep, real_fetch = kb_bot.download, kb_bot.time.sleep, kb_bot.fetch_channel
        self.addCleanup(setattr, kb_bot, 'download', real_download)
        self.addCleanup(setattr, kb_bot.time, 'sleep', real_sleep)
        self.addCleanup(setattr, kb_bot, 'fetch_channel', real_fetch)
        kb_bot.download = download
        kb_bot.time.sleep = lambda seconds: None
        channel = {'arknights': {'url': 'u', 'sha256': 'n'}}
        kb_bot.fetch_channel = lambda: channel

        class Hub:
            api = 'api'

            def __init__(self, repo, token):
                pass

            def release(self, tag):
                return {'id': 1, 'body': ''}

            def upload(self, release_id, path, name):
                return {'id': name}

            def replace(self, release_id, asset, name):
                pass

            def json(self, method, url, value):
                pass
        real_hub = kb_bot.GitHub
        self.addCleanup(setattr, kb_bot, 'GitHub', real_hub)
        kb_bot.GitHub = Hub
        self.bot.work.mkdir()
        self.bot.publish({}, channel, 'c', '', 'n', None)
        self.assertEqual(len(calls), 3)
        self.assertFalse((self.bot.work / 'check.gz').exists())

    def test_the_timeline_is_content_and_its_revision_goes_into_the_channel(self):
        self.assertIn('terra_timeline', kb_bot.CONTENT_TABLES)
        out = kb_bot.next_channel(self.channel, {'sha256': 'n', 'timeline_revision': '501'})
        self.assertEqual(out['arknights']['commit'], 'c')
        self.assertEqual(out['arknights']['timeline_revision'], '501')


if __name__ == '__main__':
    unittest.main()

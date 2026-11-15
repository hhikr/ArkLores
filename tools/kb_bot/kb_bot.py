#!/usr/bin/env python3
"""Keeps the official Arknights knowledge base and story art pack up to date.

Runs on a small server from a systemd timer, once an hour. Almost every run only
asks whether upstream moved. When it has, and has been quiet for a while:

  1. download the published knowledge base (nothing is kept between updates),
  2. update it incrementally (tools/update_gamedata.dart, vectors included),
  3. check the result, and stop here when no content changed,
  4. rebuild the story art pack when the knowledge base needs images it lacks,
  5. back the replaced files up to a private repository (only the last version),
  6. publish on the gamedata-channel Release, the channel file last,
  7. delete everything it downloaded and built.

After that the HD story art pack (developer 2026-11-12) follows the standard
one: when the standard pack was replaced since the HD pack was built, and the
disk has room for the old and the new HD pack, it is rebuilt and published
the same way. The first HD pack is published by hand.

Last, the Endfield knowledge base (developer 2026-11-14): when the game-data
repository on GitHub (ef_data.py: rmxlinux/EndfieldData, dialog trees from
555me/beyondGameData) has a commit newer than the data the channel's Endfield
asset was built from, and it has been quiet for a while, the knowledge base is
rebuilt from it and the client supplement (cutscene clips, chapters, older
dialog trees; `endfield_supplement` in the channel file), its vectors carried
over from the published one, checked and published the same way. Only GitHub
is read, never a person's website (developer 2026-11-14).

The Terra timeline (PRTS Wiki "泰拉年表", developer 2026-11-14: fetched from
PRTS directly) rides with the Arknights knowledge base: every update writes the
current page into it (tools/build_terra_timeline.dart), and once a day the
page's revision is asked for (one small API request); when it differs from the
one the published knowledge base was built with (`timeline_revision` in the
channel file), the published knowledge base gets the new timeline and goes out
again, its game data unchanged.

Docs: docs/GAMEDATA_BUILD_PIPELINE.md §7.1 and §10. The state a page shows is in
<root>/status/status.json. Tokens only ever come from the environment.
"""

import argparse
from contextlib import closing
import datetime as dt
import fcntl
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

UPSTREAM = 'https://github.com/Kengxxiao/ArknightsGameData.git'
UPSTREAM_API = 'https://api.github.com/repos/Kengxxiao/ArknightsGameData'
REPO = 'hhikr/ArkLores'
TAG = 'gamedata-channel'
CHANNEL_URL = f'https://github.com/{REPO}/releases/download/{TAG}/gamedata_channel.json'
ARKWAIFU_DB = 'https://arkwaifu.sgp1.cdn.digitaloceanspaces.com/arkwaifu.sqlite3'
BACKUP_TAG = 'arklores-knowledge-base'
KB_GZ = 'arklores_gamedata_zh.db.gz'
KB_DB = 'arklores_gamedata_zh.db'
KB_MANIFEST = 'gamedata_manifest.json'
PACK = 'arklores_story_art_zh.db'
PACK_HD = 'arklores_story_art_hd_zh.db'
HD_KEY = 'arknights_story_art_hd'
# Room left beside the old and the new HD pack (knowledge base, metadata, images).
HD_MARGIN = 1 << 30
CHANNEL = 'gamedata_channel.json'
EF_KEY = 'endfield'
EF_GZ = 'arklores_endfield_zh.db.gz'
EF_DB = 'arklores_endfield_zh.db'
SUPPLEMENT_KEY = 'endfield_supplement'
# Room for the downloaded data, the supplement, the old and the new database
# and the embedding cache.
EF_ROOM = 3 << 30

# Upstream often commits twice within an hour or so for one game update.
QUIET_HOURS = 3
MAX_EMBED_YUAN = 3
MAX_FAILURES = 3
RUNS_KEPT = 30
# A table that loses more than this share of its rows is not published.
MAX_SHRINK = 0.01

CONTENT_TABLES = ['story_lines', 'normalized_records', 'entries', 'entry_links', 'collections', 'entities',
                  'entity_aliases', 'entity_documents', 'story_catalog', 'story_line_portraits', 'story_art_events',
                  'terra_timeline', 'terra_timeline_sources']
VERIFY_ATTEMPTS = 5
VERIFY_WAIT = 60
PRTS_API = 'https://prts.wiki/api.php'
TIMELINE_PAGE = '泰拉年表'
TIMELINE_CHECK = dt.timedelta(hours=24)
# PRTS refuses browser-like agents and asks clients to say who they are.
PRTS_AGENT = 'arklores-kb-bot (knowledge base; +https://github.com/hhikr/ArkLores)'
GUARDED_TABLES = ['story_lines', 'normalized_records', 'entries', 'entry_links', 'collections', 'entity_documents',
                  'story_chunk_vectors', 'record_chunk_vectors', 'story_line_portraits', 'story_art_events']
IGNORED_COLUMNS = {'updated_at', 'built_at'}


class Held(Exception):
    """Not a failure of this run: a person has to look. Not retried for this commit."""


def now():
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0)


def iso(moment):
    return moment.strftime('%Y-%m-%dT%H:%M:%SZ')


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as file:
        while chunk := file.read(1 << 20):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path, value):
    path = Path(path)
    temp = path.with_name(path.name + '.part')
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    temp.chmod(0o644)
    temp.replace(path)


def read_json(path, default):
    try:
        return json.loads(Path(path).read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return default


# ---------- what is checked, without the network ----------

def read_db(path):
    return sqlite3.connect(f'file:{path}?mode=ro', uri=True)


def table_counts(db, tables):
    present = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    return {table: db.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0] for table in tables if table in present}


def table_fingerprint(db, table):
    """A sum over the rows that does not depend on their order or on row ids."""
    info = db.execute(f'PRAGMA table_info("{table}")').fetchall()
    keys = [c for c in info if c[5]]
    surrogate = keys[0][1] if len(keys) == 1 and keys[0][2].upper() == 'INTEGER' else None
    columns = [c[1] for c in info if c[1] != surrogate and c[1] not in IGNORED_COLUMNS]
    names = ', '.join(f'"{c}"' for c in columns)
    total = 0
    for row in db.execute(f'SELECT {names} FROM "{table}"'):
        digest = hashlib.blake2b(repr(row).encode('utf-8', 'surrogatepass'), digest_size=8).digest()
        total = (total + int.from_bytes(digest, 'big')) % (1 << 64)
    return total


def changed_tables(old_path, new_path):
    """The content tables that differ. Empty: nobody needs this update."""
    changed = []
    with closing(read_db(old_path)) as old, closing(read_db(new_path)) as new:
        old_counts, new_counts = table_counts(old, CONTENT_TABLES), table_counts(new, CONTENT_TABLES)
        for table in CONTENT_TABLES:
            if table not in old_counts and table not in new_counts:
                continue
            if old_counts.get(table) != new_counts.get(table) or table_fingerprint(old, table) != table_fingerprint(new, table):
                changed.append(table)
    return changed


def check_update(old_path, new_path):
    """What stops an update from going out by itself: lost rows, and kinds of
    entries nobody has named yet (KNOWLEDGE_BASE_LESSONS.md §2). Returns the
    problems and the row counts of both sides."""
    problems = []
    with closing(read_db(old_path)) as old, closing(read_db(new_path)) as new:
        before, after = table_counts(old, GUARDED_TABLES), table_counts(new, GUARDED_TABLES)
        for table, count in before.items():
            if table not in after:
                problems.append(f'{table} 表不见了')
            elif after[table] < count * (1 - MAX_SHRINK):
                problems.append(f'{table} 从 {count} 行减少到 {after[table]} 行')
        for table, column in (('collections', 'kind'), ('entries', 'type')):
            known = {row[0] for row in old.execute(f'SELECT DISTINCT "{column}" FROM "{table}"')}
            fresh = {row[0] for row in new.execute(f'SELECT DISTINCT "{column}" FROM "{table}"')} - known
            if fresh:
                problems.append(f'{table}.{column} 出现了新的种类：{"、".join(sorted(map(str, fresh)))}')
    return problems, {'before': before, 'after': after}


def art_needed(old_path, new_path):
    """Sprites and images the new knowledge base uses and the old one did not."""
    def names(path):
        with closing(read_db(path)) as db:
            return ({row[0] for row in db.execute('SELECT sprite FROM portrait_sprites')},
                    {row[0] for row in db.execute('SELECT image FROM story_art_events WHERE image IS NOT NULL')})
    old_sprites, old_images = names(old_path)
    new_sprites, new_images = names(new_path)
    return len(new_sprites - old_sprites), len(new_images - old_images)


def pack_counts(path):
    with closing(read_db(path)) as db:
        manifest = dict(db.execute('SELECT key, value FROM pack_manifest'))
    return {key: int(manifest.get(key, 0)) for key in ('sprite_count', 'art_count', 'title_count', 'missing_count', 'art_missing_count')}


def pack_gained(before, after):
    """Worth a 396 MB download only when it shows something it could not before."""
    return any(after[key] > before[key] for key in ('sprite_count', 'art_count', 'title_count'))


def next_channel(channel, kb=None, pack=None, hd=None, ef=None):
    """The channel file with the new assets; everything else stays as it is."""
    result = json.loads(json.dumps(channel))
    if kb:
        result['arknights'].update(kb)
    if pack:
        result['arknights_story_art'].update(pack)
    if hd:
        result[HD_KEY].update(hd)
    if ef:
        result[EF_KEY].update(ef)
    return result


def parse_time(text):
    return dt.datetime.fromisoformat(text.replace('Z', '+00:00')) if text else None


def endfield_behind(channel, commit, commit_date):
    """Whether the data repository's [commit] (made at [commit_date]) is newer
    than the data the channel's Endfield asset was built from. A commit older
    than `data_date` never replaces it: the asset may come from a source that
    was ahead (the first one, 2026-11-14, from AKEDatabase). The asset's
    `commit` stays empty: the app shows a commit's first characters as the
    Arknights upstream commit."""
    ef = channel.get(EF_KEY, {})
    if ef.get('data_commit') == commit:
        return False
    published = parse_time(ef.get('data_date'))
    return published is None or parse_time(commit_date) > published


def hd_behind(channel):
    """Whether the HD pack was built beside a standard pack that has since been
    replaced (its `follows` is that pack's SHA-256). False without an HD pack."""
    hd = channel.get(HD_KEY)
    return bool(hd) and hd.get('follows') != channel.get('arknights_story_art', {}).get('sha256')


def room_for_hd(free, channel):
    """(enough, bytes needed): the old and the new HD pack side by side, and the rest."""
    need = 2 * int(channel[HD_KEY].get('size') or 0) + HD_MARGIN
    return free >= need, need


def release_body(body, stamp, commit, commit_date, kb_sha, pack_sha):
    """The Release's description with this update's date, commit and hashes."""
    body = re.sub(r'当前版本（[^）]*）', f'当前版本（{stamp}）', body, count=1)
    body = re.sub(r'游戏数据：上游 `[0-9a-f]+`（[^）]*）', f'游戏数据：上游 `{commit[:7]}`（{commit_date[:10]}）', body, count=1)
    def replace_sha(name, sha, text):
        return re.sub(rf'(\| `{re.escape(name)}` \|.*\| `)[0-9a-f]{{64}}(` \|)', lambda m: m.group(1) + sha + m.group(2), text, count=1)
    if kb_sha:
        body = replace_sha(KB_GZ, kb_sha, body)
    if pack_sha:
        body = replace_sha(PACK, pack_sha, body)
    note = f'{stamp} 明日方舟知识库自动更新到上游 `{commit[:7]}`' + ('，剧情美术包同时更新' if pack_sha else '') + '；'
    return body.replace('更新记录：', '更新记录：' + note, 1)


# ---------- GitHub ----------

class GitHub:
    def __init__(self, repo, token):
        self.api = f'https://api.github.com/repos/{repo}'
        self.uploads = f'https://uploads.github.com/repos/{repo}'
        self.token = token

    def call(self, method, url, body=None, headers=None, timeout=120):
        request = urllib.request.Request(url, data=body, method=method, headers={
            'Authorization': f'Bearer {self.token}', 'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'arklores-kb-bot', **(headers or {})})
        with urllib.request.urlopen(request, timeout=timeout) as response:
            text = response.read()
        return json.loads(text) if text else None

    def json(self, method, url, value):
        return self.call(method, url, json.dumps(value).encode(), {'Content-Type': 'application/json'})

    def release(self, tag, create=False):
        try:
            return self.call('GET', f'{self.api}/releases/tags/{tag}')
        except urllib.error.HTTPError as error:
            if error.code != 404 or not create:
                raise
        return self.json('POST', f'{self.api}/releases', {
            'tag_name': tag, 'name': tag, 'target_commitish': 'main',
            'body': 'The ArkLores knowledge base and story art pack as they were before the last automatic update.'})

    def assets(self, release_id):
        return self.call('GET', f'{self.api}/releases/{release_id}/assets?per_page=100')

    def upload(self, release_id, path, name):
        """Uploads under [name], replacing a leftover of that name, and checks the hash."""
        for asset in self.assets(release_id):
            if asset['name'] == name:
                self.call('DELETE', f"{self.api}/releases/assets/{asset['id']}")
        size = Path(path).stat().st_size
        with open(path, 'rb') as file:
            asset = self.call('POST', f'{self.uploads}/releases/{release_id}/assets?name={urllib.parse.quote(name)}', file,
                              {'Content-Type': 'application/octet-stream', 'Content-Length': str(size)}, timeout=3600)
        digest = asset.get('digest')
        if asset.get('size') != size or (digest and digest != f'sha256:{sha256_of(path)}'):
            raise RuntimeError(f'{name} 上传后与本地不一致')
        return asset

    def replace(self, release_id, fresh, name):
        """Puts the uploaded asset [fresh] in the place of [name]."""
        for asset in self.assets(release_id):
            if asset['name'] == name:
                self.call('DELETE', f"{self.api}/releases/assets/{asset['id']}")
        self.json('PATCH', f"{self.api}/releases/assets/{fresh['id']}", {'name': name})


def download(url, path, sha=None, on_progress=None):
    request = urllib.request.Request(url, headers={'User-Agent': 'arklores-kb-bot'})
    with urllib.request.urlopen(request, timeout=300) as response, open(path, 'wb') as output:
        total, done, shown = int(response.headers.get('Content-Length') or 0), 0, 0.0
        while chunk := response.read(1 << 20):
            output.write(chunk)
            done += len(chunk)
            if on_progress and time.monotonic() - shown > 3:
                shown = time.monotonic()
                on_progress(done, total)
    if sha and sha256_of(path) != sha:
        raise RuntimeError(f'{Path(path).name} 的 SHA-256 与渠道文件不一致')


def upstream_head():
    output = subprocess.run(['git', 'ls-remote', UPSTREAM, 'refs/heads/master'], capture_output=True, text=True, timeout=120, check=True).stdout
    return output.split()[0]


def commit_date_of(sha, token, api=UPSTREAM_API):
    request = urllib.request.Request(f'{api}/commits/{sha}', headers={
        'Authorization': f'Bearer {token}', 'Accept': 'application/vnd.github+json', 'User-Agent': 'arklores-kb-bot'})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)['commit']['committer']['date']


def prts_get(params, timeout=60):
    query = urllib.parse.urlencode({**params, 'format': 'json', 'formatversion': '2'})
    request = urllib.request.Request(f'{PRTS_API}?{query}', headers={'User-Agent': PRTS_AGENT})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


def timeline_revision():
    """The current revision of the timeline page: one small request."""
    pages = prts_get({'action': 'query', 'prop': 'revisions', 'titles': TIMELINE_PAGE, 'rvprop': 'ids'})['query']['pages']
    return str(pages[0]['revisions'][0]['revid'])


def fetch_timeline(path):
    """Saves the page's wikitext to [path]; returns its revision."""
    parse = prts_get({'action': 'parse', 'page': TIMELINE_PAGE, 'prop': 'wikitext|revid'}, timeout=120)['parse']
    Path(path).write_text(parse['wikitext'], encoding='utf-8')
    return str(parse['revid'])


def fetch_channel():
    request = urllib.request.Request(f'{CHANNEL_URL}?t={int(time.time())}', headers={'User-Agent': 'arklores-kb-bot'})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


# ---------- a run ----------

class Bot:
    def __init__(self, root, dry_run=False, force=False):
        self.root = Path(root)
        self.work = self.root / 'work'
        self.bin = self.root / 'bin'
        self.status_path = self.root / 'status' / 'status.json'
        self.state_path = self.root / 'state.json'
        self.dry_run = dry_run
        self.force = force
        self.token = os.environ.get('GITHUB_TOKEN', '')
        self.backup_repo = os.environ.get('BACKUP_REPO', '')
        self.state = read_json(self.state_path, {})
        self.status = read_json(self.status_path, {})
        self.status.setdefault('runs', [])
        self.shown = 0.0
        self.run_record = None

    def redact(self, text):
        text = str(text)
        for secret in (self.token, os.environ.get('EMBEDDING_API_KEY', '')):
            if secret:
                text = text.replace(secret, '***')
        return text

    def save_state(self):
        write_json(self.state_path, self.state)

    def show(self, force=True, **fields):
        self.status.update(fields)
        self.status['updated_at'] = iso(now())
        if force or time.monotonic() - self.shown > 2:
            self.shown = time.monotonic()
            write_json(self.status_path, self.status)

    def stage(self, name, detail=''):
        print(f'[{iso(now())}] {name} {detail}', flush=True)
        self.show(stage=name, detail=detail, progress=None)
        if self.run_record is not None:
            self.run_record['stages'].append({'name': name, 'at': iso(now())})

    def progress(self, done, total):
        self.show(force=False, progress={'done': done, 'total': total})

    def tool(self, command, **kwargs):
        """Runs a tool, passing each output line on to the status file."""
        print('+', ' '.join(map(str, command)), flush=True)
        # The Dart tools load libsqlite3.so by that name: bin/lib/ links it to the system's .so.0.
        kwargs.setdefault('env', {**os.environ, 'LD_LIBRARY_PATH': str(self.bin / 'lib')})
        process = subprocess.Popen(list(map(str, command)), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace', **kwargs)
        tail = []
        for line in process.stdout:
            line = self.redact(line.rstrip())
            print(line, flush=True)
            tail = (tail + [line])[-12:]
            if line.strip():
                self.show(force=False, detail=line.strip()[:200])
        process.wait()
        return process.returncode, tail

    def finish(self, outcome, summary, **fields):
        if self.run_record is not None:
            self.run_record.update(outcome=outcome, summary=summary, finished_at=iso(now()), **fields)
            self.status['runs'] = [self.run_record] + self.status['runs'][:RUNS_KEPT - 1]
        self.show(running=False, stage=None, detail=None, progress=None, last_check_at=iso(now()), last_outcome=outcome, last_summary=summary)

    def main(self):
        self.show(running=True, stage='检查上游', detail='', progress=None, dry_run=self.dry_run)
        try:
            self.check()
        except Held as held:
            print(f'held: {held}', flush=True)
            self.state['held'] = {'sha': self.state.get('building'), 'why': str(held), 'at': iso(now())}
            self.save_state()
            self.show(held=self.state['held'])
            self.finish('held', str(held))
        except Exception as error:  # Every failure ends up on the page.
            message = self.redact(error)
            print(f'failed: {message}', file=sys.stderr, flush=True)
            sha = self.state.get('building')
            failure = self.state.get('failure') or {}
            count = failure.get('count', 0) + 1 if failure.get('sha') == sha else 1
            self.state['failure'] = {'sha': sha, 'count': count}
            self.save_state()
            self.finish('failed', f"{self.status.get('stage') or '运行'}失败：{message}", failures=count)
            # Endfield does not depend on the Arknights side: it still runs.
            return max(1, self.main_endfield())
        finally:
            shutil.rmtree(self.work, ignore_errors=True)
        return max(self.main_hd(), self.main_endfield())

    def main_hd(self):
        """The HD pack's turn, after the rest has been published and cleaned up.
        Its failures are its own: they never hold the knowledge base back."""
        self.run_record = None
        try:
            self.sync_hd()
        except Exception as error:
            message = self.redact(error)
            print(f'hd failed: {message}', file=sys.stderr, flush=True)
            follows = self.state.get('hd_building')
            failure = self.state.get('hd_failure') or {}
            count = failure.get('count', 0) + 1 if failure.get('follows') == follows else 1
            self.state['hd_failure'] = {'follows': follows, 'count': count}
            self.save_state()
            self.show(hd={'state': 'failed', 'why': message, 'at': iso(now())})
            self.finish('failed', f"高清美术包{self.status.get('stage') or ''}失败：{message}", failures=count)
            return 1
        finally:
            shutil.rmtree(self.work, ignore_errors=True)
        return 0

    def main_endfield(self):
        """The Endfield knowledge base's turn, last. Its failures and holds are
        its own (`ef_*` in the state); the status page shows them under `endfield`."""
        self.run_record = None
        try:
            self.sync_endfield()
        except Held as held:
            print(f'endfield held: {held}', flush=True)
            self.state['ef_held'] = {'version': self.state.get('ef_building'), 'why': str(held), 'at': iso(now())}
            self.save_state()
            self.show(endfield={'state': 'held', 'why': str(held), 'at': iso(now())})
            self.finish('held', f'终末地知识库：{held}')
        except Exception as error:
            message = self.redact(error)
            print(f'endfield failed: {message}', file=sys.stderr, flush=True)
            version = self.state.get('ef_building')
            failure = self.state.get('ef_failure') or {}
            count = failure.get('count', 0) + 1 if failure.get('version') == version else 1
            self.state['ef_failure'] = {'version': version, 'count': count}
            self.save_state()
            self.show(endfield={'state': 'failed', 'why': message, 'at': iso(now())})
            self.finish('failed', f"终末地知识库{self.status.get('stage') or ''}失败：{message}", failures=count)
            return 1
        finally:
            shutil.rmtree(self.work, ignore_errors=True)
        return 0

    def sync_endfield(self):
        import ef_data  # beside this file in bin/
        commit = ef_data.head(ef_data.DATA)
        channel = fetch_channel()
        if EF_KEY not in channel or channel[EF_KEY].get('data_commit') == commit or self.state.get('ef_older') == commit:
            return
        commit_date = commit_date_of(commit, self.token, ef_data.DATA_API)
        if not endfield_behind(channel, commit, commit_date):
            # Older than the data already published: not asked again.
            self.state['ef_older'] = commit
            self.save_state()
            return
        version = commit
        if not self.force:
            if (self.state.get('ef_held') or {}).get('version') == version or self.state.get('ef_no_content') == version:
                return
            failure = self.state.get('ef_failure') or {}
            if failure.get('version') == version and failure.get('count', 0) >= MAX_FAILURES:
                return
            if now() - parse_time(commit_date) < dt.timedelta(hours=QUIET_HOURS):
                self.show(endfield={'state': 'waiting', 'why': f'终末地数据仓库有新提交 {commit[:7]}，等它安静满 {QUIET_HOURS} 小时', 'at': iso(now())})
                return
        supplement = channel.get(SUPPLEMENT_KEY)
        if not supplement:
            raise Held('渠道文件里没有终末地补充文件（endfield_supplement）')
        free = shutil.disk_usage(self.root).free
        if free < EF_ROOM:
            self.show(endfield={'state': 'skipped', 'why': f'磁盘剩余 {free >> 20} MB，更新终末地知识库需要 {EF_ROOM >> 20} MB', 'at': iso(now())})
            return
        self.begin(version, 'endfield')
        self.state['ef_building'] = version
        self.save_state()
        self.fresh_work()
        ef = channel[EF_KEY]

        self.stage('下载终末地游戏数据', commit[:7])
        source = self.work / 'source'
        heads = ef_data.fetch(source)
        data, trees = source / 'data', source / 'trees' / 'dialog' / 'json'
        self.stage('下载终末地补充文件', supplement['sha256'][:12])
        supp_gz, supp = self.work / 'supplement.tar.gz', self.work / 'supplement'
        download(supplement['url'], supp_gz, supplement['sha256'], self.progress)
        supp.mkdir()
        code, tail = self.tool(['tar', '-xzf', supp_gz, '-C', supp])
        if code != 0:
            raise RuntimeError('解压补充文件失败：' + ' / '.join(tail[-3:]))
        supp_gz.unlink()

        self.stage('构建终末地知识库')
        new_dir = self.work / 'new'
        dirs = lambda *names: ';'.join(str(supp / n) for n in names)
        # The supplement's dialog trees first: the repository's are newer and
        # replace the same conversation's.
        code, tail = self.tool([self.bin / 'build_endfield_database', f"--tables={data / 'TableCfg'}", f"--missions={data / 'Json' / 'MissionRuntimeAsset'}",
                                f"--trees={dirs('tree_sa', 'tree_persistent')};{trees}", f"--clips={dirs('clips_sa', 'clips_persistent')}",
                                f"--chapters={dirs('chapters_sa', 'chapters_persistent')}", f"--data={data / 'Json'}", '--step-order=all',
                                f'--version={commit[:12]}', f'--output={new_dir}', '--force'], cwd=self.work)
        if code != 0:
            raise RuntimeError('build_endfield_database 退出码 %s：%s' % (code, ' / '.join(tail[-3:])))
        shutil.rmtree(source, ignore_errors=True)
        shutil.rmtree(supp, ignore_errors=True)
        new_db = new_dir / EF_DB

        self.stage('下载已发布的终末地知识库', ef['sha256'][:12])
        base_gz, base_db = self.work / EF_GZ, self.work / 'base.db'
        download(ef['url'], base_gz, ef['sha256'], self.progress)
        with gzip.open(base_gz, 'rb') as source, open(base_db, 'wb') as output:
            shutil.copyfileobj(source, output, 1 << 20)

        self.stage('补向量')
        code, tail = self.tool([self.bin / 'build_story_embeddings', f'--db={new_db}', f'--migrate-from={base_db}', f'--seed-cache-from={base_db}',
                                f"--cache={self.work / 'cache.db'}", f'--max-yuan={MAX_EMBED_YUAN}'], cwd=self.work)
        if code == 3:
            raise Held(f'向量估算超过 ¥{MAX_EMBED_YUAN}，没有更新；请确认后手动运行')
        if code != 0:
            raise RuntimeError('build_story_embeddings 退出码 %s：%s' % (code, ' / '.join(tail[-3:])))

        self.stage('检查结果')
        tables = changed_tables(base_db, new_db)
        if not tables:
            self.state['ef_no_content'] = version
            self.state.pop('ef_failure', None)
            self.state.pop('ef_building', None)
            self.save_state()
            self.show(endfield={'state': 'no_content', 'version': version, 'at': iso(now())})
            return self.finish('no_content', f'终末地数据 {version[:7]} 没有改变知识库的内容，不发布')
        problems, counts = check_update(base_db, new_db)
        if self.run_record is not None:
            self.run_record.update(tables=tables, counts=counts)
        if problems:
            raise Held('；'.join(problems))

        self.stage('压缩')
        new_gz = new_dir / EF_GZ
        with open(new_db, 'rb') as source, gzip.open(new_gz, 'wb', compresslevel=9) as output:
            shutil.copyfileobj(source, output, 1 << 20)
        meta = {'sha256': sha256_of(new_gz), 'data_commit': heads['data_commit'], 'data_date': commit_date, 'trees_commit': heads['trees_commit'],
                'published_at': iso(now())}
        if self.dry_run:
            return self.finish('dry_run', f'试跑完成，未上传终末地知识库 {new_gz.stat().st_size} 字节（数据 {version[:7]}）')
        self.backup_files(channel, [(base_gz, EF_GZ)])
        fresh = next_channel(channel, ef=meta)
        for key in ('ake_version', 'game_version'):  # the first asset's, from AKEDatabase
            fresh[EF_KEY].pop(key, None)
        self.publish_endfield(new_gz, fresh, commit)
        self.state.pop('ef_failure', None)
        self.state.pop('ef_building', None)
        self.state.pop('ef_held', None)
        self.save_state()
        self.show(endfield={'state': 'published', 'version': version, 'sha256': meta['sha256'], 'at': iso(now())})
        self.finish('published', f'已发布终末地知识库（数据 {version[:7]}）')

    def backup_files(self, channel, files):
        """[(path, kind)] and the channel file to the private repository; one of each kind is kept."""
        self.stage('备份上一版')
        hub = GitHub(self.backup_repo, self.token)
        release = hub.release(BACKUP_TAG, create=True)
        stamp = now().strftime('%Y%m%d%H%M')
        channel_file = self.work / f'channel-{stamp}.json'
        write_json(channel_file, channel)
        for path, kind in [(channel_file, CHANNEL), *files]:
            name = f'{stamp}-{kind}' if kind == CHANNEL else f'{stamp}-{channel[asset_key(kind)]["sha256"][:12]}-{kind}'
            asset = hub.upload(release['id'], path, name)
            for other in hub.assets(release['id']):
                if other['name'].endswith('-' + kind) and other['id'] != asset['id']:
                    hub.call('DELETE', f"{hub.api}/releases/assets/{other['id']}")

    def publish_endfield(self, path, channel, version):
        hub = GitHub(REPO, self.token)
        release = hub.release(TAG)
        self.stage('上传', EF_GZ)
        fresh = {EF_GZ: hub.upload(release['id'], path, EF_GZ + '.new')}
        channel_file = self.work / CHANNEL
        write_json(channel_file, channel)
        fresh[CHANNEL] = hub.upload(release['id'], channel_file, CHANNEL + '.new')
        self.stage('替换')
        for name, asset in fresh.items():
            hub.replace(release['id'], asset, name)
        sha = channel[EF_KEY]['sha256']
        body = re.sub(rf'(\| `{re.escape(EF_GZ)}` \|.*\| `)[0-9a-f]{{64}}(` \|)', lambda m: m.group(1) + sha + m.group(2), release['body'], count=1)
        note = f"{now().strftime('%Y-%m-%d')} 终末地知识库自动更新到数据仓库的 `{version[:7]}`；"
        body = body.replace('更新记录：', '更新记录：' + note, 1)
        if body != release['body']:
            hub.json('PATCH', f"{hub.api}/releases/{release['id']}", {'body': body})
        self.stage('核对公开地址')
        for _ in range(10):
            if fetch_channel() == channel:
                break
            time.sleep(15)
        else:
            raise RuntimeError('公开的渠道文件没有更新')
        # The download address can serve the replaced file for a little while
        # after the rename (2026-11-14: the first check failed, the file was
        # right a minute later).
        check = self.work / 'check.gz'
        for attempt in range(8):
            try:
                download(channel[EF_KEY]['url'], check, sha, self.progress)
                break
            except RuntimeError:
                if attempt == 7:
                    raise
                time.sleep(20)
        check.unlink()

    def sync_hd(self):
        channel = fetch_channel()
        if not hd_behind(channel):
            return
        standard, hd = channel['arknights_story_art'], channel[HD_KEY]
        failure = self.state.get('hd_failure') or {}
        if failure.get('follows') == standard['sha256'] and failure.get('count', 0) >= MAX_FAILURES and not self.force:
            return
        free = shutil.disk_usage(self.root).free
        enough, need = room_for_hd(free, channel)
        if not enough:
            self.show(hd={'state': 'skipped', 'why': f'磁盘剩余 {free >> 20} MB，更新高清美术包需要 {need >> 20} MB', 'at': iso(now())})
            return
        kb = channel['arknights']
        self.begin(kb.get('commit'), 'hd')
        self.state['hd_building'] = standard['sha256']
        self.save_state()
        self.fresh_work()
        self.stage('下载已发布的知识库', '高清美术包')
        base_gz, base_db = self.work / KB_GZ, self.work / KB_DB
        download(kb['url'], base_gz, kb['sha256'], self.progress)
        with gzip.open(base_gz, 'rb') as source, open(base_db, 'wb') as output:
            shutil.copyfileobj(source, output, 1 << 20)
        base_gz.unlink()
        self.stage('下载美术元数据与已发布的高清美术包')
        art_db = self.work / 'arkwaifu.sqlite3'
        download(ARKWAIFU_DB, art_db, None, self.progress)
        previous = self.work / 'previous' / PACK_HD
        previous.parent.mkdir(exist_ok=True)
        download(hd['url'], previous, hd['sha256'], self.progress)
        out = self.work / 'pack' / PACK_HD
        out.parent.mkdir(exist_ok=True)
        self.stage('打包高清剧情美术')
        code, tail = self.tool([sys.executable, self.bin / 'portraits' / 'build_portrait_pack.py', '--variant=hd', f'--kb={base_db}', f'--cache={self.work / "sprites"}',
                                f'--art-cache={self.work / "art"}', f'--arkwaifu-db={art_db}', f'--out={out}', f'--previous={previous}', '--on-demand', '--workers=1'], cwd=self.work)
        if code != 0:
            raise RuntimeError('打包退出码 %s：%s' % (code, ' / '.join(tail[-3:])))
        for name in ('sprites', 'art'):
            shutil.rmtree(self.work / name, ignore_errors=True)
        base_db.unlink()
        meta = {'sha256': sha256_of(out), 'size': out.stat().st_size, 'kb_commit': kb.get('commit'), 'follows': standard['sha256']}
        if self.dry_run:
            return self.finish('dry_run', f'试跑完成，未上传高清美术包 {meta["size"]} 字节')
        self.backup(channel, None, None, previous)
        self.publish_hd(out, next_channel(channel, hd=meta))
        self.state.pop('hd_building', None)
        self.state.pop('hd_failure', None)
        self.save_state()
        self.show(hd={'state': 'published', 'sha256': meta['sha256'], 'size': meta['size'], 'at': iso(now())})
        self.finish('published', '已发布新的高清剧情美术包')

    def publish_hd(self, path, channel):
        hub = GitHub(REPO, self.token)
        release = hub.release(TAG)
        self.stage('上传', PACK_HD)
        fresh = {PACK_HD: hub.upload(release['id'], path, PACK_HD + '.new')}
        channel_file = self.work / CHANNEL
        write_json(channel_file, channel)
        fresh[CHANNEL] = hub.upload(release['id'], channel_file, CHANNEL + '.new')
        self.stage('替换')
        for name, asset in fresh.items():
            hub.replace(release['id'], asset, name)
        body = re.sub(rf'(\| `{re.escape(PACK_HD)}` \|.*\| `)[0-9a-f]{{64}}(` \|)',
                      lambda m: m.group(1) + channel[HD_KEY]['sha256'] + m.group(2), release['body'], count=1)
        if body != release['body']:
            hub.json('PATCH', f"{hub.api}/releases/{release['id']}", {'body': body})
        self.stage('核对公开地址')
        for _ in range(10):
            if fetch_channel() == channel:
                return
            time.sleep(15)
        raise RuntimeError('公开的渠道文件没有更新')

    def check(self):
        head = upstream_head()
        channel = fetch_channel()
        kb = channel['arknights']
        self.show(upstream=head, published={'commit': kb.get('commit'), 'commit_date': kb.get('commit_date'), 'sha256': kb.get('sha256'),
                                            'pack_commit': channel.get('arknights_story_art', {}).get('kb_commit'),
                                            'pack_sha256': channel.get('arknights_story_art', {}).get('sha256')})
        if not self.force:
            held = self.state.get('held')
            if held and held.get('sha') == head:
                return self.finish('held', held['why'])
            failure = self.state.get('failure') or {}
            if failure.get('sha') == head and failure.get('count', 0) >= MAX_FAILURES:
                return self.finish('held', f'这个提交连续失败了 {MAX_FAILURES} 次，不再重试')
        self.state.pop('held', None)
        self.status.pop('held', None)

        if head == kb.get('commit') or (head == self.state.get('no_content') and not self.force):
            return self.retry_pack(channel) or self.sync_timeline(channel) or self.finish('idle', '没有新内容')
        date = commit_date_of(head, self.token)
        age = now() - dt.datetime.fromisoformat(date.replace('Z', '+00:00'))
        if age < dt.timedelta(hours=QUIET_HOURS) and not self.force:
            return self.finish('waiting', f'上游有新提交 {head[:7]}，等它安静满 {QUIET_HOURS} 小时')
        self.build(head, date, channel)

    def begin(self, commit, kind):
        self.run_record = {'started_at': iso(now()), 'commit': commit, 'kind': kind, 'stages': []}
        self.state['building'] = commit
        self.save_state()

    def fresh_work(self):
        shutil.rmtree(self.work, ignore_errors=True)
        self.work.mkdir(parents=True)

    def build(self, head, date, channel):
        self.begin(head, 'update')
        self.fresh_work()
        kb = channel['arknights']
        base_gz, base_db = self.work / KB_GZ, self.work / 'base.db'
        new_dir = self.work / 'new'
        new_dir.mkdir()
        new_db = new_dir / KB_DB

        self.stage('下载已发布的知识库', kb['sha256'][:12])
        download(kb['url'], base_gz, kb['sha256'], self.progress)
        with gzip.open(base_gz, 'rb') as source, open(base_db, 'wb') as output:
            shutil.copyfileobj(source, output, 1 << 20)

        self.stage('增量更新', f"{kb.get('commit', '')[:7]} → {head[:7]}")
        report_path = self.work / 'report.json'
        code, tail = self.tool([self.bin / 'update_gamedata', f'--db={base_db}', f'--source={self.work / "src"}', f'--output={new_db}',
                                '--embed', f'--embed-max-yuan={MAX_EMBED_YUAN}', f'--report-json={report_path}'], cwd=self.work)
        if code == 3:
            raise Held(f'向量估算超过 ¥{MAX_EMBED_YUAN}，没有更新；请确认后手动运行')
        if code != 0:
            raise RuntimeError('update_gamedata 退出码 %s：%s' % (code, ' / '.join(tail[-3:])))
        report = read_json(report_path, {})
        changes = {key: report.get(key) for key in ('changes', 'vectors')}
        shutil.rmtree(self.work / 'src', ignore_errors=True)
        if not report.get('updated'):
            return self.no_content(head, changes)
        # New stories may be what the timeline's sources name: the page is
        # written in again. A failure keeps the timeline the database had.
        timeline = self.add_timeline(new_db)

        self.stage('检查结果')
        tables = changed_tables(base_db, new_db)
        if not tables:
            return self.no_content(head, changes)
        problems, counts = check_update(base_db, new_db)
        changes.update(tables=tables, counts=counts)
        if self.run_record is not None:
            self.run_record.update(changes)
        if problems:
            raise Held('；'.join(problems))

        self.stage('压缩与校验')
        code, tail = self.tool([self.bin / 'finalize_gamedata_assets', f'--output={new_dir}'], cwd=self.work)
        if code != 0:
            raise RuntimeError('finalize 退出码 %s：%s' % (code, ' / '.join(tail[-3:])))
        new_gz, new_manifest = new_dir / KB_GZ, new_dir / KB_MANIFEST

        # A pack is only rebuilt for what the new stories show, and published
        # only when it can show more. Otherwise phones keep the one they have.
        pack_path, pack_meta = None, None
        sprites, images = art_needed(base_db, new_db)
        if sprites or images or self.state.get('pack_pending'):
            pack_path, pack_meta = self.build_pack(channel, new_db, head, sprites, images)

        if self.dry_run:
            summary = f'试跑完成，未上传：{head[:7]}，新库 {new_gz.stat().st_size} 字节' + (f'，新美术包 {pack_path.stat().st_size} 字节' if pack_path else '')
            self.state.pop('failure', None)
            self.save_state()
            return self.finish('dry_run', summary, **changes)

        files = {KB_GZ: new_gz, KB_MANIFEST: new_manifest}
        if pack_path:
            files[PACK] = pack_path
        update = {'sha256': sha256_of(new_gz), 'commit': head, 'commit_date': date}
        if timeline:
            update['timeline_revision'] = timeline
        pack_update = pack_meta if pack_path else None
        self.backup(channel, base_gz, self.work / 'previous' / PACK if pack_path else None)
        self.publish(files, next_channel(channel, update, pack_update), head, date, update['sha256'], pack_update and pack_update['sha256'])
        self.state.pop('failure', None)
        self.state.pop('building', None)
        self.state.pop('no_content', None)
        self.save_state()
        self.show(published={'commit': head, 'commit_date': date, 'sha256': update['sha256'], 'published_at': iso(now()),
                             'pack_commit': (pack_update or channel.get('arknights_story_art', {})).get('kb_commit'),
                             'pack_sha256': (pack_update or channel.get('arknights_story_art', {})).get('sha256')})
        self.finish('published', f'已发布 {head[:7]}' + ('，含新的剧情美术包' if pack_path else ''), **changes)

    def add_timeline(self, db_path):
        """Writes the timeline page as it is now into [db_path]. Returns its
        revision, or None when that did not work (PRTS unreachable, the page's
        format changed): the database then keeps the timeline it had, and the
        status page says why."""
        self.stage('写入泰拉年表')
        wikitext = self.work / 'timeline.wikitext'
        try:
            revision = fetch_timeline(wikitext)
            code, tail = self.tool([self.bin / 'build_terra_timeline', f'--db={db_path}', f'--wikitext={wikitext}', f'--revision={revision}'], cwd=self.work)
            if code != 0:
                raise RuntimeError('build_terra_timeline 退出码 %s：%s' % (code, ' / '.join(tail[-3:])))
        except Exception as error:
            message = self.redact(error)
            print(f'timeline failed: {message}', file=sys.stderr, flush=True)
            self.show(timeline={'state': 'failed', 'why': message, 'at': iso(now())})
            return None
        finally:
            wikitext.unlink(missing_ok=True)
        self.state['timeline_checked_at'] = iso(now())
        self.save_state()
        self.show(timeline={'state': 'written', 'revision': revision, 'at': iso(now())})
        return revision

    def sync_timeline(self, channel):
        """Once a day, when nothing else is to be done: a new revision of the
        timeline page goes into the published knowledge base, whose game data
        stays as it is. True when this took the run."""
        kb = channel['arknights']
        checked = parse_time(self.state.get('timeline_checked_at'))
        if checked and now() - checked < TIMELINE_CHECK and not self.force:
            return False
        try:
            revision = timeline_revision()
        except Exception as error:
            self.show(timeline={'state': 'failed', 'why': self.redact(error), 'at': iso(now())})
            return False
        self.state['timeline_checked_at'] = iso(now())
        self.save_state()
        if revision == kb.get('timeline_revision'):
            self.show(timeline={'state': 'current', 'revision': revision, 'at': iso(now())})
            return False
        failure = self.state.get('timeline_failure') or {}
        if failure.get('revision') == revision and failure.get('count', 0) >= MAX_FAILURES and not self.force:
            return False

        self.begin(kb.get('commit'), 'timeline')
        try:
            self.fresh_work()
            base_gz = self.work / 'base' / KB_GZ
            base_gz.parent.mkdir()
            new_dir = self.work / 'new'
            new_dir.mkdir()
            new_db = new_dir / KB_DB
            self.stage('下载已发布的知识库', f'泰拉年表 {kb.get("timeline_revision") or "无"} → {revision}')
            download(kb['url'], base_gz, kb['sha256'], self.progress)
            with gzip.open(base_gz, 'rb') as source, open(new_db, 'wb') as output:
                shutil.copyfileobj(source, output, 1 << 20)
            written = self.add_timeline(new_db)
            if not written:
                raise RuntimeError(self.status.get('timeline', {}).get('why') or '没能写入泰拉年表')
            self.stage('压缩与校验')
            code, tail = self.tool([self.bin / 'finalize_gamedata_assets', f'--output={new_dir}'], cwd=self.work)
            if code != 0:
                raise RuntimeError('finalize 退出码 %s：%s' % (code, ' / '.join(tail[-3:])))
            new_gz, new_manifest = new_dir / KB_GZ, new_dir / KB_MANIFEST
            if self.dry_run:
                self.finish('dry_run', f'试跑完成，未上传：泰拉年表 {written}，新库 {new_gz.stat().st_size} 字节')
                return True
            update = {'sha256': sha256_of(new_gz), 'timeline_revision': written}
            self.backup(channel, base_gz, None)
            self.publish({KB_GZ: new_gz, KB_MANIFEST: new_manifest}, next_channel(channel, update),
                         kb.get('commit'), kb.get('commit_date') or '', update['sha256'], None)
        except Exception as error:
            message = self.redact(error)
            print(f'timeline publish failed: {message}', file=sys.stderr, flush=True)
            count = failure.get('count', 0) + 1 if failure.get('revision') == revision else 1
            self.state['timeline_failure'] = {'revision': revision, 'count': count}
            self.state.pop('building', None)
            self.save_state()
            self.finish('failed', f"泰拉年表{self.status.get('stage') or ''}失败：{message}", failures=count)
            return True
        self.state.pop('timeline_failure', None)
        self.state.pop('building', None)
        self.save_state()
        self.show(published={**self.status.get('published', {}), 'sha256': update['sha256'], 'published_at': iso(now())})
        self.finish('published', f'已发布新的泰拉年表（版本 {written}）')
        return True

    def no_content(self, head, changes):
        self.state['no_content'] = head
        self.state.pop('failure', None)
        self.state.pop('building', None)
        self.save_state()
        self.finish('no_content', f'{head[:7]} 没有改变知识库的内容，不发布', **changes)

    def build_pack(self, channel, kb_path, commit, sprites, images):
        """Returns (pack path, channel fields), or (None, None) when the pack gains nothing."""
        asset = channel['arknights_story_art']
        self.stage('下载美术元数据与已发布的美术包', f'新立绘 {sprites}，新图 {images}')
        art_db = self.work / 'arkwaifu.sqlite3'
        download(ARKWAIFU_DB, art_db, None, self.progress)
        previous_dir = self.work / 'previous'
        previous_dir.mkdir(exist_ok=True)
        previous = previous_dir / PACK
        download(asset['url'], previous, asset['sha256'], self.progress)
        out = self.work / 'pack' / PACK
        out.parent.mkdir(exist_ok=True)
        self.stage('打包剧情美术')
        code, tail = self.tool([sys.executable, self.bin / 'portraits' / 'build_portrait_pack.py', f'--kb={kb_path}', f'--cache={self.work / "sprites"}',
                                f'--art-cache={self.work / "art"}', f'--arkwaifu-db={art_db}', f'--out={out}', f'--previous={previous}', '--on-demand', '--workers=1'], cwd=self.work)
        if code != 0:
            raise RuntimeError('打包退出码 %s：%s' % (code, ' / '.join(tail[-3:])))
        before, after = pack_counts(previous), pack_counts(out)
        shutil.rmtree(self.work / 'sprites', ignore_errors=True)
        shutil.rmtree(self.work / 'art', ignore_errors=True)
        # Arkwaifu may not have a new story's images yet: come back for them.
        if after['missing_count'] > before['missing_count'] or after['art_missing_count'] > before['art_missing_count']:
            self.state['pack_pending'] = {'etag': url_etag(ARKWAIFU_DB), 'missing': after['missing_count'] + after['art_missing_count']}
        else:
            self.state.pop('pack_pending', None)
        self.save_state()
        if not pack_gained(before, after):
            return None, None
        return out, {'sha256': sha256_of(out), 'size': out.stat().st_size, 'kb_commit': commit}

    def retry_pack(self, channel):
        """Arkwaifu published new images for a pack that was missing some. True when this took the run."""
        pending = self.state.get('pack_pending')
        if not pending or url_etag(ARKWAIFU_DB) == pending.get('etag'):
            return False
        kb = channel['arknights']
        self.begin(kb.get('commit'), 'pack')
        self.fresh_work()
        self.stage('下载已发布的知识库', '补美术包')
        base_gz, base_db = self.work / KB_GZ, self.work / KB_DB
        download(kb['url'], base_gz, kb['sha256'], self.progress)
        with gzip.open(base_gz, 'rb') as source, open(base_db, 'wb') as output:
            shutil.copyfileobj(source, output, 1 << 20)
        base_gz.unlink()
        path, meta = self.build_pack(channel, base_db, kb.get('commit'), 0, 0)
        if not path:
            self.finish('no_content', '美术包没有新的图')
            return True
        if self.dry_run:
            self.finish('dry_run', f'试跑完成，未上传美术包 {path.stat().st_size} 字节')
            return True
        self.backup(channel, None, self.work / 'previous' / PACK)
        self.publish({PACK: path}, next_channel(channel, None, meta), kb.get('commit'), kb.get('commit_date') or '', None, meta['sha256'])
        self.state.pop('building', None)
        self.save_state()
        self.finish('published', '已发布新的剧情美术包')
        return True

    def backup(self, channel, old_gz, old_pack, old_hd=None):
        """Keeps one previous version in the private repository, as release attachments."""
        self.stage('备份上一版')
        hub = GitHub(self.backup_repo, self.token)
        release = hub.release(BACKUP_TAG, create=True)
        short = channel['arknights'].get('commit', 'unknown')[:7]
        channel_file = self.work / f'channel-{short}.json'
        write_json(channel_file, channel)
        uploads = [(channel_file, CHANNEL)]
        if old_gz:
            uploads.append((old_gz, KB_GZ))
        if old_pack:
            uploads.append((old_pack, PACK))
        if old_hd:
            uploads.append((old_hd, PACK_HD))
        for path, kind in uploads:
            name = f'{short}-{channel[asset_key(kind)]["sha256"][:12]}-{kind}' if kind != CHANNEL else f'{short}-{kind}'
            asset = hub.upload(release['id'], path, name)
            for other in hub.assets(release['id']):
                if other['name'].endswith('-' + kind) and other['id'] != asset['id']:
                    hub.call('DELETE', f"{hub.api}/releases/assets/{other['id']}")

    def publish(self, files, channel, commit, commit_date, kb_sha, pack_sha):
        hub = GitHub(REPO, self.token)
        release = hub.release(TAG)
        # All uploads finish before anything is swapped: a phone reading the old
        # channel file only meets a mismatch for the seconds of the swap itself.
        fresh = {}
        for name, path in files.items():
            self.stage('上传', name)
            fresh[name] = hub.upload(release['id'], path, name + '.new')
        channel_file = self.work / CHANNEL
        write_json(channel_file, channel)
        fresh[CHANNEL] = hub.upload(release['id'], channel_file, CHANNEL + '.new')
        self.stage('替换')
        for name, asset in fresh.items():
            hub.replace(release['id'], asset, name)
        hub.json('PATCH', f"{hub.api}/releases/{release['id']}", {'body': release_body(release['body'], now().strftime('%Y-%m-%d'), commit, commit_date, kb_sha, pack_sha)})

        self.stage('核对公开地址')
        for _ in range(10):
            if fetch_channel() == channel:
                break
            time.sleep(15)
        else:
            raise RuntimeError('公开的渠道文件没有更新')
        if kb_sha:
            # The download address may serve the replaced file for a few
            # minutes after the swap (2026-11-14: one check failed, the file
            # was right a minute later): try again before calling it failed.
            check = self.work / 'check.gz'
            for attempt in range(VERIFY_ATTEMPTS):
                try:
                    download(channel['arknights']['url'], check, kb_sha, self.progress)
                    break
                except RuntimeError:
                    if attempt == VERIFY_ATTEMPTS - 1:
                        raise
                    time.sleep(VERIFY_WAIT)
                finally:
                    check.unlink(missing_ok=True)


def asset_key(kind):
    return {KB_GZ: 'arknights', PACK: 'arknights_story_art', PACK_HD: HD_KEY, EF_GZ: EF_KEY}[kind]


def url_etag(url):
    request = urllib.request.Request(url, method='HEAD', headers={'User-Agent': 'arklores-kb-bot'})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.headers.get('ETag') or response.headers.get('Last-Modified') or ''


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--root', default='/srv/arklores-bot')
    parser.add_argument('--dry-run', action='store_true', help='build and check, upload nothing')
    parser.add_argument('--force', action='store_true', help='do not wait for quiet, try a held commit again')
    args = parser.parse_args()
    # systemd gives no locale, and the stage names are Chinese.
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')
    root = Path(args.root)
    (root / 'status').mkdir(parents=True, exist_ok=True)
    with open(root / 'lock', 'w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            print('another run is in progress', flush=True)
            return 0
        return Bot(root, args.dry_run, args.force).main()


if __name__ == '__main__':
    sys.exit(main())

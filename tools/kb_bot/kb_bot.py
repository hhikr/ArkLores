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

Docs: docs/GAMEDATA_BUILD_PIPELINE.md §7.1. The state a page shows is in
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
CHANNEL = 'gamedata_channel.json'

# Upstream often commits twice within an hour or so for one game update.
QUIET_HOURS = 3
MAX_EMBED_YUAN = 3
MAX_FAILURES = 3
RUNS_KEPT = 30
# A table that loses more than this share of its rows is not published.
MAX_SHRINK = 0.01

CONTENT_TABLES = ['story_lines', 'normalized_records', 'entries', 'entry_links', 'collections', 'entities',
                  'entity_aliases', 'entity_documents', 'story_catalog', 'story_line_portraits', 'story_art_events']
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


def next_channel(channel, kb=None, pack=None):
    """The channel file with the new assets; everything else stays as it is."""
    result = json.loads(json.dumps(channel))
    if kb:
        result['arknights'].update(kb)
    if pack:
        result['arknights_story_art'].update(pack)
    return result


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


def commit_date_of(sha, token):
    request = urllib.request.Request(f'{UPSTREAM_API}/commits/{sha}', headers={
        'Authorization': f'Bearer {token}', 'Accept': 'application/vnd.github+json', 'User-Agent': 'arklores-kb-bot'})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)['commit']['committer']['date']


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
            return 1
        finally:
            shutil.rmtree(self.work, ignore_errors=True)
        return 0

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
            return self.retry_pack(channel) or self.finish('idle', '没有新内容')
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

    def backup(self, channel, old_gz, old_pack):
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
            check = self.work / 'check.gz'
            download(channel['arknights']['url'], check, kb_sha, self.progress)
            check.unlink()


def asset_key(kind):
    return 'arknights' if kind == KB_GZ else 'arknights_story_art'


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

#!/usr/bin/env python3
"""Downloads the Endfield game data the knowledge base is built from, from
AKEDatabase's data site (https://data.akedata.wiki, github.com/NagiYume/AKEDatabase).

  python3 ake_data.py --out <dir>            # the latest version
  python3 ake_data.py --version-only         # print the version key and exit

Writes <dir>/tables/<Name>.json (the game tables the build reads, from the
latest TableCfg) and <dir>/json/<path> (mission definitions, level scripts,
level sub-data and the gameplay tables, from the shared Json set), and
<dir>/ake_version.json with what was downloaded.

The dialog trees, cutscene clips and chapters are not on the site (they are
Unity objects in the asset bundles); the build takes them from a supplement
unpacked from the client (docs/GAMEDATA_BUILD_PIPELINE.md §9.3).
"""

import argparse
import hashlib
import json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import sys
import time
import urllib.request

SITE = 'https://data.akedata.wiki'
AGENT = 'arklores-kb-bot (+https://github.com/hhikr/ArkLores)'

# The tables build_endfield_database.dart reads (lib/core/gamedata/build/endfield/).
TABLES = [
    'BlocDataTable', 'CharacterTable', 'CharacterTagDesTable', 'CharacterTagTable', 'DialogOptionTable',
    'DialogSummaryMapTable', 'DialogSummaryTable', 'DialogTextTable', 'DisplayEnemyTypeTable',
    'DistributionInfoTable', 'DomainDataTable', 'DungeonTable', 'EnemyTemplateDisplayInfoTable', 'EnvTalkTable',
    'I18nTextTable_CN', 'ItemTable', 'ItemTypeTable', 'LevelDescTable', 'MailTemplateTable', 'MissionTypeInfoTable',
    'NpcTable', 'PrtsAllItem', 'PrtsCategory', 'PrtsFirstLv', 'PrtsInvestigate', 'PrtsNote', 'PrtsPage',
    'PrtsReading', 'RadioTable', 'ReadingPopUpTable', 'RemoteCommonTable', 'RichContentTable', 'SNSChatTable',
    'SNSDialogOptionTable', 'SNSDialogTable', 'SNSDialogTopicTable', 'TagDataTable', 'TagGroupDataTable',
    'TextTable', 'WeaponBasicTable',
]
# Folders of the Json set the build reads.
JSON_DIRS = ('MissionRuntimeAsset/', 'LevelScriptData/', 'LevelData/', 'GameplayConfig/')


def get(url, tries=4):
    for attempt in range(tries):
        try:
            request = urllib.request.Request(url, headers={'User-Agent': AGENT})
            with urllib.request.urlopen(request, timeout=120) as response:
                return response.read()
        except Exception:
            if attempt == tries - 1:
                raise
            time.sleep(2 * (attempt + 1))


def get_json(url):
    return json.loads(get(f'{url}?t={int(time.time())}'))


def version():
    """The latest TableCfg version and the Json set's revision: what changes
    when the site publishes new game data."""
    manifest = get_json(f'{SITE}/manifest.json')
    index = get_json(f'{SITE}/asset-sync-index.json')
    latest = next(v for v in manifest['versions'] if v['id'] == manifest['latest'])
    return latest, index


def version_key(latest, index):
    return f"{latest['id']}+{index['revision']}"


def download(out, workers=24):
    out = Path(out)
    latest, index = version()
    files = index['datasets']['json']['files']
    jobs = [(f"{SITE}/{latest['tableCfgPath']}/{name}.json", out / 'tables' / f'{name}.json', None) for name in TABLES]
    jobs += [(f"{SITE}/{index['datasets']['json']['root']}/{path}", out / 'json' / path, meta.get('md5'))
             for path, meta in files.items() if path.startswith(JSON_DIRS)]

    def fetch(job):
        url, path, md5 = job
        # A file already there with the index's md5 is not fetched again (a
        # rerun after an interruption; the server bot starts empty).
        if md5 and path.exists():
            data = path.read_bytes()
            if hashlib.md5(data).hexdigest() == md5:
                return len(data)
        data = get(url)
        if md5 and hashlib.md5(data).hexdigest() != md5:
            raise RuntimeError(f'{path.name}: md5 does not match the index')
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return len(data)

    total = 0
    with ThreadPoolExecutor(workers) as pool:
        for i, size in enumerate(pool.map(fetch, jobs), 1):
            total += size
            if i % 500 == 0 or i == len(jobs):
                print(f'{i}/{len(jobs)} files, {total >> 20} MB', flush=True)
    info = {'version': version_key(latest, index), 'game_version': latest['gameVersion'],
            'hotfix': latest['hotfixVersion'], 'published_at': latest['publishedAt'],
            'json_revision': index['revision'], 'files': len(jobs), 'bytes': total}
    (out / 'ake_version.json').write_text(json.dumps(info, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    return info


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--out')
    parser.add_argument('--version-only', action='store_true')
    args = parser.parse_args()
    if args.version_only:
        print(version_key(*version()))
        return 0
    if not args.out:
        parser.error('--out is required')
    print(json.dumps(download(args.out), ensure_ascii=False))
    return 0


if __name__ == '__main__':
    sys.exit(main())

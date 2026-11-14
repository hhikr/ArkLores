#!/usr/bin/env python3
"""Fetches the Endfield game data the knowledge base is built from, from
GitHub (developer 2026-11-14: from repositories, not from a person's website,
so that nobody's site carries our load):

  rmxlinux/EndfieldData   TableCfg (the game tables) and Json (mission
                          definitions, level scripts, level sub-data, gameplay
                          tables), the client's own serialization
  555me/beyondGameData    dialog/json: the conversations' dialog trees

  python3 ef_data.py --heads            # print the two repositories' HEADs
  python3 ef_data.py --out <dir>        # <dir>/data, <dir>/trees

A shallow, blob-less clone with a sparse checkout: only the files the build
reads are downloaded (2026-11: about 330 MB of data, 30 MB of trees).
Cutscene clips and chapters are in neither; the build takes them from the
client supplement (docs/GAMEDATA_BUILD_PIPELINE.md §9.3).
"""

import argparse
import json
from pathlib import Path
import subprocess
import sys

DATA = 'https://github.com/rmxlinux/EndfieldData.git'
TREES = 'https://github.com/555me/beyondGameData.git'
DATA_API = 'https://api.github.com/repos/rmxlinux/EndfieldData'

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
DATA_PATHS = [f'/TableCfg/{name}.json' for name in TABLES] + [
    f'/Json/{folder}/' for folder in ('MissionRuntimeAsset', 'LevelScriptData', 'LevelData', 'GameplayConfig')]
TREE_PATHS = ['/dialog/json/']


def git(*args, cwd=None):
    return subprocess.run(['git', *args], cwd=cwd, capture_output=True, text=True, timeout=3600, check=True).stdout


def head(url):
    return git('ls-remote', url, 'HEAD').split()[0]


def sparse_clone(url, paths, out):
    """The repository's HEAD with only [paths] checked out; returns its commit."""
    git('clone', '--depth', '1', '--filter=blob:none', '--no-checkout', '--quiet', url, str(out))
    git('sparse-checkout', 'set', '--no-cone', *paths, cwd=out)
    git('checkout', '--quiet', cwd=out)
    return git('rev-parse', 'HEAD', cwd=out).strip()


def fetch(out):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    data = sparse_clone(DATA, DATA_PATHS, out / 'data')
    trees = sparse_clone(TREES, TREE_PATHS, out / 'trees')
    missing = [name for name in TABLES if not (out / 'data' / 'TableCfg' / f'{name}.json').exists()]
    if missing:
        raise RuntimeError('数据仓库缺少表：' + '、'.join(missing))
    return {'data_commit': data, 'trees_commit': trees}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--out')
    parser.add_argument('--heads', action='store_true')
    args = parser.parse_args()
    if args.heads:
        print(json.dumps({'data': head(DATA), 'trees': head(TREES)}))
        return 0
    if not args.out:
        parser.error('--out is required')
    print(json.dumps(fetch(args.out)))
    return 0


if __name__ == '__main__':
    sys.exit(main())

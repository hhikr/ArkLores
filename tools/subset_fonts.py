"""Cuts the bundled Chinese fonts down to the characters the app shows.

A full CJK font is 18-26 MB, read into memory when the app starts; most of
its 30 000+ glyphs never appear. Kept: GB2312 (any common Chinese, typed by
the user or written by a model), every character of the knowledge bases, of
the app's own strings and of the code, and the usual punctuation and
symbols. A character outside the set falls back to the system's sans.

Run it again after a knowledge base is rebuilt (new characters), from the
full fonts (not the cut ones in assets/fonts):

    python -m pip install --target <dir> fonttools
    set PYTHONPATH=<dir>
    python tools/subset_fonts.py --font <full NotoSansSC[wght].ttf>=assets/fonts/NotoSansSC.ttf
        --font <full LXGWWenKaiScreen.ttf>=assets/fonts/LXGWWenKaiScreen.ttf
        --db build/gamedata_rebuild/arklores_gamedata_zh.db
        --db build/endfield/arklores_endfield_zh.db

The full fonts: Noto Sans SC from github.com/google/fonts (ofl/notosanssc),
LXGW WenKai Screen v1.522 from github.com/lxgw/LxgwWenKai-Screen/releases.
"""

import argparse
import pathlib
import sqlite3

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Latin, punctuation, symbols, kana and full-width forms.
RANGES = [
    (0x20, 0x7E),
    (0xA0, 0x17F),
    (0x2000, 0x206F),
    (0x2100, 0x21FF),
    (0x2460, 0x24FF),
    (0x2500, 0x25FF),
    (0x2600, 0x26FF),
    (0x3000, 0x30FF),
    (0xFE30, 0xFE4F),
    (0xFF00, 0xFFEF),
]


def gb2312():
    chars = set()
    for hi in range(0xA1, 0xF8):
        for lo in range(0xA1, 0xFF):
            try:
                chars.add(bytes([hi, lo]).decode('gb2312'))
            except UnicodeDecodeError:
                pass
    return chars


def database_chars(path):
    chars = set()
    db = sqlite3.connect(f'file:{path}?mode=ro', uri=True)
    tables = [r[0] for r in db.execute(
        "SELECT name FROM sqlite_master WHERE type = 'table'")]
    for table in tables:
        columns = [r[1] for r in db.execute(f'PRAGMA table_info("{table}")')]
        for column in columns:
            query = (f'SELECT "{column}" FROM "{table}" '
                     f'WHERE typeof("{column}") = \'text\'')
            for (value,) in db.execute(query):
                chars.update(value)
    db.close()
    return chars


def source_chars():
    chars = set()
    for pattern in ('lib/**/*.dart', 'lib/**/*.arb'):
        for file in ROOT.glob(pattern):
            chars.update(file.read_text(encoding='utf-8'))
    return chars


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--font', action='append', required=True,
                        help='full font=output path')
    parser.add_argument('--db', action='append', default=[])
    args = parser.parse_args()

    chars = gb2312() | source_chars()
    for start, end in RANGES:
        chars.update(chr(c) for c in range(start, end + 1))
    for db in args.db:
        chars |= database_chars(db)
    codepoints = {ord(c) for c in chars if ord(c) >= 0x20}
    print(f'{len(codepoints)} characters')

    for pair in args.font:
        source, output = pair.split('=', 1)
        options = subset.Options()
        options.layout_features = ['*']
        options.name_IDs = ['*']
        options.notdef_outline = True
        options.hinting = False
        font = TTFont(source)
        subsetter = subset.Subsetter(options)
        subsetter.populate(unicodes=codepoints)
        subsetter.subset(font)
        font.save(output)
        print(f'{output}: {pathlib.Path(output).stat().st_size} bytes')


if __name__ == '__main__':
    main()

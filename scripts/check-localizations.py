#!/usr/bin/env python3
"""Check translation coverage and format arguments without opening the application."""
import collections
import json
import pathlib
import re

root = pathlib.Path(__file__).resolve().parent.parent


def read(language):
    path = root / 'Resources' / f'{language}.lproj' / 'Localizable.strings'
    entries = {}
    for line in path.read_text().splitlines():
        if not line.startswith('"'):
            continue
        key, value = (json.loads(part) for part in line.removesuffix(';').split(' = ', 1))
        assert key not in entries, f'Duplicate key: {key}'
        entries[key] = value
    return entries


english, chinese = read('en'), read('zh-Hans')
assert english.keys() == chinese.keys(), 'Translation keys differ between languages'
for key, value in english.items():
    assert key == value, f'English source and translation differ: {key}'
    assert not re.search(r'[\u4e00-\u9fff]', key), f'Non-English source key: {key}'
    arguments = lambda text: collections.Counter(re.findall(r'%(?:lld|ld|d|@)', text))
    assert arguments(key) == arguments(chinese[key]), f'Format argument mismatch: {key}'
    assert chinese[key].strip(), f'Empty translation: {key}'
print(f'Checked {len(english)} English source strings and matching Simplified Chinese translations.')

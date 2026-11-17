"""Regenerate the bundled waiting handwriting from its editable phrase list."""
from pathlib import Path
import json
from riddle_paths import reply_paths

root = Path(__file__).resolve().parent
phrases = json.loads((root / 'waiting-phrases.json').read_text(encoding='utf-8'))
assert phrases and len(phrases) == len(set(phrases)), 'Use distinct waiting phrases'
paths = []
for phrase in phrases:
    strokes = reply_paths(phrase)
    assert strokes, 'Unsupported phrase: ' + phrase
    paths.append(strokes)
payload = json.dumps(paths, separators=(',', ':'))
assert len(payload.encode('utf-8')) <= 1048576, 'Waiting catalogue exceeds client limit'
destination = root.parent / 'koreader/plugins/riddle.koplugin/waiting-paths.json'
destination.write_text(payload, encoding='utf-8')
print(f'Generated {len(phrases)} waiting phrases')

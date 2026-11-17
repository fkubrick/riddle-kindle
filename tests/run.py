"""Run with Python, lupa and the installed upstream Ink Away source directory."""
from pathlib import Path
import argparse
from lupa.luajit21 import LuaRuntime

parser=argparse.ArgumentParser()
parser.add_argument('--ink-away-root',type=Path,required=True)
args=parser.parse_args()
repo=Path(__file__).resolve().parents[1]
lua=LuaRuntime()
lua.globals().plugin_root=(repo/'koreader/plugins/ink-away.koplugin').as_posix()
lua.globals().riddle_root=(repo/'koreader/plugins/riddle.koplugin').as_posix()
lua.globals().upstream=args.ink_away_root.resolve().as_posix()
lua.execute('package.path=plugin_root.."/?.lua;"..riddle_root.."/?.lua;"..upstream.."/?.lua;"..package.path')
for file in (repo/'koreader').rglob('*.lua'):
    lua.execute('assert(loadfile(...))',str(file))
lua.execute('''
local net=require("ink/alfred/transport")
assert(not net.configure("http://journal.example.org"))
assert(not net.configure("https://user:password@journal.example.org"))
assert(not net.configure("https://journal.example.org/path"))
assert(net.configure("https://journal.example.org"))
assert(net.endpoint()=="https://journal.example.org")
''')
lua.execute((repo/'tests/test_bridge.lua').read_text(encoding='utf-8')+'\n'+(repo/'tests/test_journal.lua').read_text(encoding='utf-8'))
print('Public client protocol and journal checks passed')
animation=LuaRuntime()
animation.globals().root=(repo/'koreader/plugins/riddle.koplugin').as_posix()
animation.execute('package.path=root.."/?.lua;"..package.path')
animation.execute((repo/'tests/test_animation.lua').read_text(encoding='utf-8'))
print('Ink animation, reading menu and waiting interruption checks passed')

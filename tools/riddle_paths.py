"""Lay out precompiled Dancing Script strokes without production dependencies."""
from functools import lru_cache
import json
from pathlib import Path
import unicodedata

@lru_cache(maxsize=1)
def alphabet():
    return json.loads(Path(__file__).with_name('riddle-alphabet.json').read_text(encoding='utf-8'))['glyphs']

@lru_cache(maxsize=128)
def reply_paths(text):
    text=unicodedata.normalize('NFC',text)
    glyphs=alphabet()
    if not text.strip() or len(text)>160 or any(c not in glyphs and not c.isspace() for c in text):
        return None  # Client keeps the original text, never replaces unknown characters.
    lines=[]; line=''
    def width(s): return sum(glyphs[c]['advance'] for c in s)
    for word in text.split():
        candidate=(line+' '+word).strip()
        if line and width(candidate)>900:
            lines.append(line); line=''
        for char in word:
            if line and width(line+char)>900:
                lines.append(line); line=''
            line+=char
        line+=' '
    if line.strip(): lines.append(line.rstrip())
    paths=[]
    for row,line in enumerate(lines):
        x=0
        for char in line:
            g=glyphs[char]
            paths.extend([[[round(x+p[0],2),round(row*130+p[1],2)] for p in stroke] for stroke in g['paths']])
            x+=g['advance']
    if not paths or sum(map(len,paths))>20000 or len(paths)>2500: return None
    xs=[p[0] for s in paths for p in s]; ys=[p[1] for s in paths for p in s]
    x0,y0,x1,y1=min(xs),min(ys),max(xs),max(ys)
    scale=min(1000/max(1,x1-x0),1300/max(1,y1-y0))
    result=[[[round((x-x0)*scale+36),round((y-y0)*scale+36)] for x,y in s] for s in paths]
    if len(json.dumps(result,separators=(',',':')))>220000: return None
    return result

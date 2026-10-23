#!/usr/bin/env python3
"""Reviewer-only opaque flattening of text bounds from a real native capture.

Every derivative still requires semantic visual inspection before release.
Does not replace displayed text or change app geometry. No original metadata.
"""
from pathlib import Path
import re
import sys
from PIL import Image, ImageDraw

image_path, tree_path, destination = map(Path, sys.argv[1:4])
original = Image.open(image_path).convert('RGB')
cleared = original.copy()
draw = ImageDraw.Draw(cleared)
tree = tree_path.read_text()
window = re.search(r'Window \(Main\).*?\{\{[\d.]+, [\d.]+\}, \{([\d.]+), ([\d.]+)\}\}', tree)
if not window:
    raise ValueError('missing window bounds')
sx, sy = original.width / float(window[1]), original.height / float(window[2])
for line in tree.splitlines():
    if 'StaticText,' not in line and "identifier: 'decision.option." not in line:
        continue
    match = re.search(r'\{\{(-?[\d.]+), (-?[\d.]+)\}, \{([\d.]+), ([\d.]+)\}\}', line)
    if not match:
        continue
    x,y,w,h = map(float, match.groups())
    x0,y0 = max(0,int(x*sx)-2),max(0,int(y*sy)-2)
    x1,y1 = min(original.width,int((x+w)*sx)+3),min(original.height,int((y+h)*sy)+3)
    if x1 <= x0 or y1 <= y0:
        continue
    # Fully erase bounds, then reproduce only occupied line extents, never glyphs.
    pixels = original.load()
    rows = []
    for yy in range(y0,y1):
        occupied = [xx for xx in range(x0,x1) if max(pixels[xx,yy])-min(pixels[xx,yy]) < 65 and max(pixels[xx,yy]) > 105]
        if len(occupied) >= 3:
            rows.append((yy,min(occupied),max(occupied)))
    draw.rectangle((x0,y0,x1,y1),fill=(43,46,49))
    groups = []
    for row in rows:
        if not groups or row[0] > groups[-1][-1][0]+2:
            groups.append([])
        groups[-1].append(row)
    for group in groups:
        draw.rectangle((min(r[1] for r in group),group[0][0],max(r[2] for r in group),group[-1][0]),fill=(108,111,115))
# Status bar may contain other-app or owner metadata, unrelated to app geometry.
draw.rectangle((0,0,original.width,int(62*sy)),fill=(17,19,21))
destination.parent.mkdir(parents=True,exist_ok=True)
cleared.save(destination,format='PNG',pnginfo=None)

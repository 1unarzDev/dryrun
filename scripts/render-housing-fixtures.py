#!/usr/bin/env python3
"""Render committed original SVG/OBJ fixtures side by side. Needs cairosvg; no model calls.
These are portable geometry inspections, not RealityKit or device screenshots.
"""
import html, math
from pathlib import Path
import xml.etree.ElementTree as ET
import cairosvg
ROOT=Path(__file__).resolve().parents[1]
DIR=ROOT/'fixtures/homes/representations'
for name in ['apartment-complex','manufactured','twostory']:
    key='home-sample-'+name
    plans=sorted(DIR.glob(key+'-*.svg'))
    height=max(760,len(plans)*350+100)
    body=[f'<rect width="1500" height="{height}" fill="#fff"/>',f'<text x="30" y="35" font-size="22">DryRun {name}: original synthetic 2D + 3D geometry</text>', '<text x="30" y="65" font-size="15">Portable fixture review; not a device screenshot or route/safety certification.</text>']
    for i,path in enumerate(plans):
        svg=ET.fromstring(path.read_text())
        svg.set('x','30');svg.set('y',str(100+350*i));svg.set('width','640');svg.set('height','310')
        body.append(ET.tostring(svg,encoding='unicode'))
        body.append(f'<text x="30" y="{95+350*i}" font-size="14">{html.escape(path.stem[len(key)+1:])}</text>')
    vertices=[];shapes=[];obj=''
    for line in (DIR/(key+'.obj')).read_text().splitlines():
        tokens=line.split()
        if not tokens:continue
        if tokens[0]=='o':obj=tokens[1]
        elif tokens[0]=='v':vertices.append(tuple(map(float,tokens[1:])))
        elif tokens[0] in ('f','l','p'):shapes.append((tokens[0],obj,[vertices[int(x)-1] for x in tokens[1:]]))
    def project(p):
        x,elev,z=p
        return ((x+z)*0.866,(z-x)*0.5-elev)
    points=[project(p) for p in vertices]
    xmin=min(p[0] for p in points);xmax=max(p[0] for p in points)
    ymin=min(p[1] for p in points);ymax=max(p[1] for p in points)
    scale=min(690/max(1,xmax-xmin),620/max(1,ymax-ymin))
    def pixel(p):
        x,y=project(p)
        return (740+(x-xmin)*scale,150+(y-ymin)*scale)
    for kind,obj,vs in sorted(shapes,key=lambda s:(0 if s[0]=='f' else 1,-sum(p[1] for p in s[2])/len(s[2]))):
        xy=[pixel(p) for p in vs];coords=' '.join(f'{x:.2f},{y:.2f}' for x,y in xy)
        if kind=='f':body.append(f'<polygon points="{coords}" fill="#e6eff2" fill-opacity="0.7" stroke="#55646a" stroke-width="1"/>')
        elif kind=='l':
            color='#2979bd' if '_window_' in obj else '#268168' if obj.startswith('pt-') else '#777'
            body.append(f'<polyline points="{coords}" fill="none" stroke="{color}" stroke-width="{4 if obj.startswith("pt-") else 2}"/>')
        else:
            x,y=xy[0]
            body.append(f'<circle cx="{x}" cy="{y}" r="4" fill="#b33c38"/><text x="{x+6}" y="{y-6}" font-size="10">{html.escape(obj)}</text>')
    body.append('<text x="740" y="110" font-size="18">OBJ in metres: +Y up, floor transforms applied</text>')
    body.append(f'<text x="740" y="{height-35}" font-size="14">Blue: windows · Green: other openings · Red: safety markers</text>')
    svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="1500" height="{height}">'+''.join(body)+'</svg>'
    (DIR/(key+'-comparison.svg')).write_text(svg)
    cairosvg.svg2png(bytestring=svg.encode(),write_to=str(DIR/(key+'-comparison.png')))
    print(key)

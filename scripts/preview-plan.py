#!/usr/bin/env python3
"""Render core PlanDocument JSON as a portable reference PDF, never as native iOS verification.

Generate fictional snapshots: DRYRUN_DUMP=1 scripts/swift.sh packages/DryRunCore test --filter PlanDemoDump
Run: python scripts/preview-plan.py output/plan-examples/*.json --output output/pdf --paper both
Requires reportlab; a Unicode NotoSans/DejaVu font. Apple tiles are deliberately unavailable here.
"""
import argparse
import json
from pathlib import Path
from xml.sax.saxutils import escape
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4, letter
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, PageBreak, Flowable, KeepTogether


def fonts():
    candidates = [Path('/usr/share/fonts/noto'), Path('/usr/share/fonts/truetype/noto'), Path('/Library/Fonts')]
    for root in candidates:
        if (root / 'NotoSans-Regular.ttf').exists():
            pdfmetrics.registerFont(TTFont('Body', str(root / 'NotoSans-Regular.ttf')))
            pdfmetrics.registerFont(TTFont('Bold', str(root / 'NotoSans-Bold.ttf')))
            return
    raise SystemExit('Set up NotoSans-Regular.ttf and NotoSans-Bold.ttf in a supported font folder.')


class Diagram(Flowable):
    def __init__(self, home, floor, route=None):
        super().__init__()
        self.width, self.height = 500, 250
        self.home, self.floor, self.route = home, floor, route

    def draw(self):
        c = self.canv
        rooms = [r for r in self.home['spaces'] if r['floorID'] == self.floor['id']]
        points = [p for r in rooms for p in r['polygon']]
        if not points:
            return
        minx, miny = min(p['x'] for p in points), min(p['y'] for p in points)
        dx = max(p['x'] for p in points)-minx
        dy = max(p['y'] for p in points)-miny
        scale = min((self.width-26)/max(dx, 1), (self.height-26)/max(dy, 1))
        def xy(p): return 13+(p['x']-minx)*scale, self.height-13-(p['y']-miny)*scale
        def line(a,b): c.line(*xy(a),*xy(b))
        for room in rooms:
            path = c.beginPath()
            path.moveTo(*xy(room['polygon'][0]))
            for p in room['polygon'][1:]: path.lineTo(*xy(p))
            path.close()
            c.setFillColor(colors.HexColor('#f2f2f2')); c.setStrokeColor(colors.HexColor('#444444'))
            c.drawPath(path, fill=1, stroke=1)
            x = sum(p['x'] for p in room['polygon'])/len(room['polygon'])
            y = sum(p['y'] for p in room['polygon'])/len(room['polygon'])
            cx, cy = xy({'x':x,'y':y})
            c.setFillColor(colors.black); c.setFont('Body',8)
            c.drawCentredString(cx,cy,room['label'])
        # Portals interrupt the room boundary, preserving canonical endpoints.
        for portal in self.home['portals']:
            if portal['floorID'] != self.floor['id']: continue
            c.setStrokeColor(colors.white); c.setLineWidth(4); line(portal['a'],portal['b'])
            if portal['kind'] == 'window':
                c.setStrokeColor(colors.HexColor('#888888')); c.setLineWidth(1); line(portal['a'],portal['b'])
            elif portal.get('verification') != 'verified':
                c.setStrokeColor(colors.black); c.setLineWidth(1); c.setDash(2,2);line(portal['a'],portal['b']);c.setDash()
        for obstacle in self.home.get('obstacles',[]):
            if obstacle['floorID'] != self.floor['id'] or not obstacle.get('polygon'): continue
            path=c.beginPath();path.moveTo(*xy(obstacle['polygon'][0]))
            for p in obstacle['polygon'][1:]:path.lineTo(*xy(p))
            path.close();c.setFillColor(colors.HexColor('#999999'));c.drawPath(path,stroke=1,fill=1)
        for connector in self.home.get('connectors',[]):
            p = connector.get('fromPoint') if connector.get('fromFloorID') == self.floor['id'] else connector.get('toPoint') if connector.get('toFloorID') == self.floor['id'] else None
            if p:
                x,y=xy(p);c.setFillColor(colors.black);c.setFont('Bold',8);c.drawString(x,y,'STAIR')
        if self.route:
            c.setStrokeColor(colors.black);c.setLineWidth(2.5)
            for leg in self.route.get('legs',[]):
                if leg['floorID'] != self.floor['id']:continue
                pts=leg['points']
                for a,b in zip(pts,pts[1:]):line(a,b)
                if pts:
                    c.setFillColor(colors.white);c.circle(*xy(pts[0]),3,fill=1,stroke=1)
                    c.setFillColor(colors.black);c.circle(*xy(pts[-1]),3,fill=1,stroke=1)


def render(path, target, paper):
    data=json.loads(path.read_text())
    pagesize = A4 if paper == 'a4' else letter
    width,height=pagesize
    styles={
        'title':ParagraphStyle('title',fontName='Bold',fontSize=19,leading=24,spaceAfter=15),
        'head':ParagraphStyle('head',fontName='Bold',fontSize=12,leading=17,spaceBefore=12,spaceAfter=6,keepWithNext=True),
        'body':ParagraphStyle('body',fontName='Body',fontSize=10.5,leading=15,spaceAfter=6,splitLongWords=True),
        'bold':ParagraphStyle('bold',fontName='Bold',fontSize=10.5,leading=15,spaceAfter=6),
        'note':ParagraphStyle('note',fontName='Body',fontSize=8.5,leading=12,spaceAfter=7,textColor=colors.HexColor('#444444')),
    }
    def p(text,style='body'):return Paragraph(escape(str(text)).replace('\n','<br/>'),styles[style])
    story=[p('Fictional document example','title'),p('Portable reference renderer from DryRunCore PlanDocument. This is not an iOS export or evidence of native build, PDFKit, sharing, printing, or Apple snapshot behavior.','note')]
    for banner in ['contentReviewBanner','draftTranslationBanner','fallbackNote']:
        if data.get(banner):story.append(p(data[banner],'note'))
    story.append(p(data['footer'],'note'))
    for i,page in enumerate(data['pages']):
        if i:story.append(PageBreak())
        story.append(p(page['title'],'title'))
        for section in page['sections']:
            story.append(p(section['heading'],'head'))
            for line in section['lines']:
                style='bold' if section['id']=='critical' or line['style']=='prohibition' else 'body'
                story.append(p(('[EN] ' if line.get('isFallback') else '')+line['text'],style))

    snapshot=data.get('visualSnapshot') or {}
    home=snapshot.get('home')
    if home:
        for floor in home['floors']:
            story.extend([PageBreak(),p('Example home / '+floor['label'],'title'),p('Canonical indoor metres. This overview contains no implied current route. Door gaps, windows and obstacles are shown from saved data.','note'),Diagram(home,floor)])
        for i,result in enumerate(snapshot.get('routes',[])):
            if not result.get('primary'):continue
            person=(snapshot.get('personLabels') or {}).get(result['request'].get('personID'), 'Unassigned person')
            scenario=(snapshot.get('routeScenarioIDs') or ['unknown']*len(snapshot.get('routes',[])))[i]
            label=(snapshot.get('scenarioLabels') or {}).get(scenario,scenario)
            for floor in home['floors']:
                if not any(leg['floorID']==floor['id'] for leg in result['primary']['legs']):continue
                story.extend([PageBreak(),p(label+' / '+person,'title'),p('One qualified exercise route, using the exact saved route legs. No predicted safe time or outdoor path is implied.','note'),Diagram(home,floor,result['primary'])])
    if snapshot.get('savedPlaces') or snapshot.get('homeCoordinate'):
        story.extend([PageBreak(),p('Saved neighborhood destinations','title'),p('Map unavailable in this portable reference. Names, addresses and finding instructions remain usable as text. No retained Apple map imagery is included.','note')])
        for i,place in enumerate(snapshot.get('savedPlaces',[]),1):
            story.append(p(str(i)+'. '+place['label'],'head'))
            for key in ['addressText','findingInstructions']:
                if place.get(key):story.append(p(place[key]))
    def footer(c,doc):
        c.saveState();c.setFont('Body',8);c.setFillColor(colors.HexColor('#555555'))
        c.drawString(42,24,'EXAMPLE - portable reference / native rendering unverified')
        c.drawRightString(width-42,24,str(doc.page));c.restoreState()
    doc=SimpleDocTemplate(str(target),pagesize=pagesize,leftMargin=42,rightMargin=42,topMargin=36,bottomMargin=42,title='DryRun fictional reference '+path.stem,author='DryRun')
    doc.build(story,onFirstPage=footer,onLaterPages=footer)
    print(target)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('files',nargs='+',type=Path)
    parser.add_argument('--output',type=Path,default=Path('output/pdf'))
    parser.add_argument('--paper',choices=['letter','a4','both'],default='both')
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True);fonts()
    for file in args.files:
        for paper in (['letter','a4'] if args.paper=='both' else [args.paper]):render(file,args.output/(file.stem+'-'+paper+'.pdf'),paper)
if __name__=='__main__':main()

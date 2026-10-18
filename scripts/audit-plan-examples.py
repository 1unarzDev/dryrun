#!/usr/bin/env python3
"""Audit fictional portable PDFs and optionally render pages for human review (requires pypdf/Poppler/Pillow)."""
import argparse, json, subprocess
from pathlib import Path
from pypdf import PdfReader

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--render',action='store_true')
    parser.add_argument('--output',type=Path,default=Path('tmp/pdfs/final'))
    args=parser.parse_args(); args.output.mkdir(parents=True,exist_ok=True)
    audit=[]
    for file in sorted(Path('output/pdf').glob('*.pdf')):
        reader=PdfReader(file); text=' '.join(' '.join(p.extract_text() or '' for p in reader.pages).split())
        for expected in ['+1 202 555 0148','Example mailbox',"Example relative's home",'Fictional landmark beside the driveway','Call the example contact before going']:
            assert expected in text,(file,expected)
        if 'large-long' in file.name: assert 'END OF LONG EXAMPLE NOTE' in text,file
        bounds=list(reader.pages[0].mediabox); expected=(612,792) if 'letter' in file.stem else (595.28,841.89)
        assert abs(float(bounds[2])-expected[0])<.1 and abs(float(bounds[3])-expected[1])<.1,file
        assert not any('\ufffd' in (p.extract_text() or '') for p in reader.pages),file
        audit.append({'file':str(file),'pages':len(reader.pages),'textCharacters':len(text),'paperPoints':[float(v) for v in bounds]})
        if args.render:
            prefix=args.output/file.stem
            subprocess.run(['pdftoppm','-scale-to','1200','-png',str(file),str(prefix)],check=True,stdout=subprocess.DEVNULL)
            from PIL import Image,ImageDraw
            images=sorted(args.output.glob(file.stem+'-*.png'))
            cols=4; rows=(len(images)+cols-1)//cols
            sheet=Image.new('RGB',(1200,rows*420),'#d5d5d5'); draw=ImageDraw.Draw(sheet)
            for i,path in enumerate(images):
                im=Image.open(path).convert('RGB');im.thumbnail((290,390))
                x=i%cols*300;y=i//cols*420
                sheet.paste(im,(x,y+22));draw.text((x+3,y+4),path.name[-25:],fill='black')
            sheet.save(args.output/(file.stem+'-contact.png'))
    (args.output/'text-audit.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(audit,ensure_ascii=False,indent=2))
if __name__=='__main__': main()

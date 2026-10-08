from pathlib import Path
from PIL import Image,ImageCms,ImageChops
import xml.etree.ElementTree as ET
import json,re,zipfile,hashlib,io,tempfile,os
R=Path(__file__).resolve().parent.parent/'inlaut-design-v1'
expected={'README.md','DESIGN_GUIDE.md','LICENSE-ASSETS.md','app-icon/layers/layers.md','app-icon/flat/icon.svg','menubar/preview-menubar.png','web/favicon.svg','web/favicon.ico','web/apple-touch-icon-180.png','web/og-image-1200x630.png','web/github-social-1280x640.png','distribution/dmg-background-660x400.png','distribution/dmg-background-660x400@2x.png','distribution/readme-header-1600x400.png','tokens/colors.json','tokens/InlautColors.swift','checks/contact-sheet.png'}
expected|={f'app-icon/layers/{x}.svg' for x in ['00-background','01-foreground-sound','02-foreground-caret']}
expected|={f'app-icon/preview/icon-{x}-1024.png' for x in ['default','dark','clear-light','clear-dark','tinted-light','tinted-dark']}
expected|={f'app-icon/flat/icon-{s}.png' for s in [1024,512,256,128,64,32,16]}
for state in ['ready','recording','transcribing','preparing','failed']:
 expected.add(f'menubar/menubar-{state}.svg')
 for scale in [1,2]:expected.add(f'menubar/png/menubar-{state}@{scale}x.png')
for kind in ['wordmark-inlaut','lockup-horizontal','symbol']:
 for color in ['black','white','color']:
  expected.add(f'logo/{kind}-{color}.svg')
  for size in [512,2048]:expected.add(f'logo/png/{kind}-{color}-{size}.png')
actual={str(p.relative_to(R)) for p in R.rglob('*') if p.is_file()}
assert actual==expected,{'missing':expected-actual,'extra':actual-expected}
for p in R.rglob('*.svg'):
 root=ET.parse(p).getroot();raw=p.read_text()
 assert not re.search(r'<(?:text|image|filter|use|foreignObject)\b|url\(|href=|@import|<!ENTITY',raw)
 assert set(el.tag.split('}')[-1] for el in root.iter())<={'svg','path','g'}
 if p.parent.name=='layers':assert root.attrib['viewBox']=='0 0 1024 1024' and root.attrib['width']==root.attrib['height']=='1024'
 if p.parent.name=='menubar':
  assert root.attrib['viewBox']=='0 0 18 18'
  assert all(el.attrib.get('fill')=='#000000' for el in root.iter() if el.tag.endswith('path'))
for p in R.rglob('*.png'):
 im=Image.open(p);assert im.mode=='RGBA'
 profile=ImageCms.ImageCmsProfile(io.BytesIO(im.info['icc_profile']));assert 'sRGB' in ImageCms.getProfileDescription(profile)
 rel=str(p.relative_to(R));dims=None
 if p.parent.name=='preview':dims=(1024,1024)
 if p.parent.name=='flat':s=int(p.stem.split('-')[-1]);dims=(s,s)
 if 'menubar/png/' in rel:
  s=36 if '@2x' in p.name else 18;dims=(s,s)
  assert im.convert('RGB').getextrema()==((0,0),(0,0),(0,0));assert im.getchannel('A').getextrema()==(0,255)
 if 'logo/png/' in rel:
  assert im.width==int(p.stem.split('-')[-1]);assert im.getchannel('A').getextrema()==(0,255)
 prescribed={'web/apple-touch-icon-180.png':(180,180),'web/og-image-1200x630.png':(1200,630),'web/github-social-1280x640.png':(1280,640),'distribution/dmg-background-660x400.png':(660,400),'distribution/dmg-background-660x400@2x.png':(1320,800),'distribution/readme-header-1600x400.png':(1600,400)}
 dims=prescribed.get(rel,dims)
 if dims:assert im.size==dims,(rel,im.size,dims)
for kind in ['wordmark-inlaut','lockup-horizontal','symbol']:
 forms=[]
 for color in ['color','black','white']:
  r=ET.parse(R/f'logo/{kind}-{color}.svg').getroot()
  for el in r.iter():el.attrib.pop('fill',None)
  forms.append(ET.tostring(r))
 assert len(set(forms))==1
ico=Image.open(R/'web/favicon.ico');assert ico.ico.sizes()=={(16,16),(32,32),(48,48)}
for s in [16,32]:
 a=ico.ico.getimage((s,s)).convert('RGBA');b=Image.open(R/f'app-icon/flat/icon-{s}.png')
 assert ImageChops.difference(a,b).getbbox() is None
# Free 96 pt squares in the DMG image, reserved for actual Finder icons.
for scale in [1,2]:
 im=Image.open(R/('distribution/dmg-background-660x400'+('@2x' if scale==2 else '')+'.png'))
 for x in [170,490]:
  tile=im.crop(((x-48)*scale,152*scale,(x+48)*scale,248*scale))
  assert len(tile.getcolors(tile.width*tile.height))==1
# Execute the documented Color Set generator in isolation and check the produced names.
readme=(R/'README.md').read_text();snippet=readme.split('```python\n',1)[1].split('```',1)[0]
with tempfile.TemporaryDirectory(prefix='inlaut-assets-check-') as td:
 t=Path(td);(t/'tokens').mkdir();(t/'tokens/colors.json').write_bytes((R/'tokens/colors.json').read_bytes());old=os.getcwd();os.chdir(t)
 try:
  exec(compile(snippet,'README.md','exec'),{})
  for tok in json.loads((R/'tokens/colors.json').read_text())['colors']:
   c=json.loads((t/'InlautColors.xcassets'/f"{tok['assetName']}.colorset"/'Contents.json').read_text());assert len(c['colors'])==2
 finally:os.chdir(old)
def lum(c):
 a=[int(c[i:i+2],16)/255 for i in (1,3,5)];a=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in a];return sum(v*w for v,w in zip(a,[.2126,.7152,.0722]))
def ratio(a,b):
 x,y=sorted([lum(a),lum(b)]);return (y+.05)/(x+.05)
colors=json.loads((R/'tokens/colors.json').read_text())['colors'];by={x['name']:x for x in colors}
contrast={}
for mode in ['light','dark']:
 for role in ['ink','accent','recording','border']:
  v=ratio(by[role][mode],by['paper'][mode]);contrast[f'{role}-{mode}']=round(v,2);assert v >= (3 if role in ['recording','border'] else 4.5)
report={'status':'passed','files':len(actual),'svg':len(list(R.rglob('*.svg'))),'png':len(list(R.rglob('*.png'))),'icoSizes':sorted(ico.ico.sizes()),'contrast':contrast,'checks':['exact manifest','SVG paths and dimensions','black-only alpha templates','RGBA and sRGB PNGs','pixel-hinted ICO sizes','identical logo variant geometry','DMG icon clearances','documented asset generator'],'nativeIconComposerTested':False}
(R.parent/'build-support/validation-report.json').write_text(json.dumps(report,indent=2)+'\n')
out=R.parent/'inlaut-design-v1.zip'
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for rel in sorted(actual):z.write(R/rel,str(Path(R.name)/rel))
with zipfile.ZipFile(out) as z:assert z.testzip() is None;assert len(z.namelist())==len(actual)
print(json.dumps(report,indent=2));print('ZIP:',out,'bytes:',out.stat().st_size,'SHA256:',hashlib.sha256(out.read_bytes()).hexdigest())

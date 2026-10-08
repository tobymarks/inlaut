from pathlib import Path
from io import BytesIO
import json, math, zipfile, hashlib, xml.etree.ElementTree as ET
import cairosvg
from PIL import Image, ImageDraw, ImageFont, ImageCms
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

HERE=Path(__file__).resolve().parent
ROOT=HERE.parent/'inlaut-design-v1'
ROOT.mkdir(exist_ok=True)
ICC=ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes()
PAPER='#F6F2E9'; SAND='#E4DCCF'; INK='#182E30'; TEAL='#236B63'; MINT='#9AC9BB'; RED='#C44336'; CORAL='#FF8E80'
FONT=HERE/'manrope-medium.ttf'
if not FONT.exists(): instantiateVariableFont(TTFont(HERE/'manrope.ttf'),{'wght':500},inplace=True).save(FONT)

def write(rel,text):
 p=ROOT/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text,encoding='utf-8')
def svg(w,h,body): return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>'
def path(d,c=INK,extra=''):return f'<path fill="{c}" d="{d}" {extra}/>'
def rect(x,y,w,h,r=0):
 if not r:return f'M{x} {y}h{w}v{h}h{-w}Z'
 return f'M{x+r} {y}H{x+w-r}Q{x+w} {y} {x+w} {y+r}V{y+h-r}Q{x+w} {y+h} {x+w-r} {y+h}H{x+r}Q{x} {y+h} {x} {y+h-r}V{y+r}Q{x} {y} {x+r} {y}Z'
def circle(cx,cy,r):return f'M{cx-r} {cy}a{r} {r} 0 1 0 {2*r} 0a{r} {r} 0 1 0 {-2*r} 0Z'
def save_png(im,rel):
 p=ROOT/rel;p.parent.mkdir(parents=True,exist_ok=True);im.convert('RGBA').save(p,icc_profile=ICC)
def render(s,w,h=None):return Image.open(BytesIO(cairosvg.svg2png(bytestring=s.encode(),output_width=w,output_height=h))).convert('RGBA')
def export_svg(rel,s,widths=()):
 write(rel,s)
 for width in widths:save_png(render(s,width),Path(rel).parent/'png'/f'{Path(rel).stem}-{width}.png')
def font(size):return ImageFont.truetype(str(FONT),size)
def text(im,xy,words,size=22,fill=INK):ImageDraw.Draw(im).text(xy,words,font=font(size),fill=fill)
def paste(im,src,xy):im.alpha_composite(src,xy)
def centered(im,y,words,size,fill=INK):
 w=ImageDraw.Draw(im).textlength(words,font=font(size));text(im,((im.width-w)/2,y),words,size,fill)

# All marks are original filled paths. No font is used to construct the wordmark.
word=[rect(8,48,18,84,3),circle(17,20,10),
'M48 132V85C48 60 64 46 87 46C110 46 126 60 126 85V132H108V85C108 70 100 63 87 63C74 63 66 70 66 85V132Z',
rect(148,8,18,124,3),
'M271 132H254V122C247 130 237 134 226 134C202 134 185 116 185 90C185 65 202 46 227 46C252 46 271 64 271 90Z M253 90C253 74 243 63 228 63C213 63 203 74 203 90C203 106 213 117 228 117C243 117 253 106 253 90Z',
'M294 48H312V95C312 110 319 117 333 117C347 117 354 110 354 95V48H372V95C372 120 357 134 333 134C309 134 294 120 294 95Z',
'M402 25H420V48H447V65H420V104C420 113 425 117 434 117H447V132H432C412 132 402 123 402 105V65H389V48H402Z']
def word_body(c):return ''.join(path(d,c,'fill-rule="evenodd"') for d in word)
CARET=rect(476,264,72,496,10)+rect(432,264,160,32,10)+rect(432,728,160,32,10)
BARS=rect(282,404,68,216,10)+rect(674,404,68,216,10)
def symbol(c=INK):return path(CARET,c)+path(BARS,c)
# 1024 source layers use the same full canvas; foreground geometry is never moved by appearance.
write('app-icon/layers/00-background.svg',svg(1024,1024,path(rect(0,0,1024,1024),PAPER)))
write('app-icon/layers/01-foreground-sound.svg',svg(1024,1024,path(BARS,TEAL)))
write('app-icon/layers/02-foreground-caret.svg',svg(1024,1024,path(CARET,TEAL)))
MASK=rect(24,24,976,976,220)
def icon(bg,fg):return svg(1024,1024,path(MASK,bg)+symbol(fg))
variants={'default':(PAPER,TEAL),'dark':(INK,MINT),'clear-light':('#E8E8E8','#292929'),'clear-dark':('#292929','#FFFFFF'),'tinted-light':('#DFEBE5','#254F47'),'tinted-dark':('#1C312D','#A5D2C3')}
def icon_raster(bg,fg,size):
 if size not in (16,32):return render(icon(bg,fg),size)
 # Optical pixel hinting only at tiny sizes; the motif and appearances stay identical.
 if size==16:
  d=rect(7,4,2,8)+rect(6,4,4,1)+rect(6,11,4,1)+rect(4,6,1,4)+rect(11,6,1,4)
 else:
  d=rect(15,8,2,16)+rect(13,8,6,1)+rect(13,23,6,1)+rect(9,13,2,6)+rect(21,13,2,6)
 return render(svg(size,size,path(rect(.375*size/16,.375*size/16,size*.953125,size*.953125,size*.21484375),bg)+path(d,fg)),size)
for name,(bg,fg) in variants.items():save_png(render(icon(bg,fg),1024),f'app-icon/preview/icon-{name}-1024.png')
write('app-icon/flat/icon.svg',icon(PAPER,TEAL))
for size in [1024,512,256,128,64,32,16]:save_png(icon_raster(PAPER,TEAL,size),f'app-icon/flat/icon-{size}.png')
for name,c in [('color',TEAL),('black','#000000'),('white','#FFFFFF')]:
 export_svg(f'logo/wordmark-inlaut-{name}.svg',svg(455,142,word_body(c)),[512,2048])
 export_svg(f'logo/symbol-{name}.svg',svg(576,576,f'<g transform="translate(-224 -224)">{symbol(c)}</g>'),[512,2048])
 body=f'<g transform="translate(-27 -22) scale(.2)">{symbol(c)}</g><g transform="translate(155 9)">{word_body(c)}</g>'
 export_svg(f'logo/lockup-horizontal-{name}.svg',svg(622,162,body),[512,2048])

ready=rect(8.2,1,1.6,16,.3)+rect(6.4,1,5.2,1.5,.3)+rect(6.4,15.5,5.2,1.5,.3)+rect(3,6,1.5,6,.3)+rect(13.5,6,1.5,6,.3)
recording=rect(7.5,1,3,16,.5)+rect(6,1,6,2,.4)+rect(6,15,6,2,.4)+rect(2.5,4,2.8,10,.5)+rect(12.7,4,2.8,10,.5)
transcribing=rect(8.2,1,1.6,16,.3)+rect(6.4,1,5.2,1.5,.3)+rect(6.4,15.5,5.2,1.5,.3)+rect(1.5,6,4.5,1.5,.3)+rect(1.5,10.5,4.5,1.5,.3)+rect(12,6,4.5,1.5,.3)+rect(12,10.5,4.5,1.5,.3)
preparing=rect(8.2,1,1.6,6.2,.3)+rect(8.2,10.8,1.6,6.2,.3)+rect(6.4,1,5.2,1.5,.3)+rect(6.4,15.5,5.2,1.5,.3)+rect(3,7.5,1.5,3,.3)+rect(13.5,7.5,1.5,3,.3)
# Deliberate gap behind a slash; no white knockout in this template image.
failed=rect(8.2,1,1.6,5.5,.3)+rect(8.2,11.5,1.6,5.5,.3)+rect(6.4,1,5.2,1.5,.3)+rect(6.4,15.5,5.2,1.5,.3)+rect(3,6,1.5,3,.3)+rect(13.5,9,1.5,3,.3)+'M2 14.7L14.7 2L16 3.3L3.3 16Z'
MENUS=dict(zip(['ready','recording','transcribing','preparing','failed'],[ready,recording,transcribing,preparing,failed]))
for name,d in MENUS.items():
 s=svg(18,18,path(d,'#000000'));write(f'menubar/menubar-{name}.svg',s)
 for scale in [1,2]:
  im=render(s,18*scale);alpha=im.getchannel('A');im=Image.new('RGBA',im.size,(0,0,0,0));im.putalpha(alpha)
  save_png(im,f'menubar/png/menubar-{name}@{scale}x.png')
labels=['Bereit','Aufnahme','Erkennt …','Vorbereitung','Fehler']
im=Image.new('RGBA',(1000,244),PAPER)
text(im,(28,15),'Menüleiste · alle Zustände · 18 pt / 36 px @2x',18)
for row,(bg,fg) in enumerate([('#FFFFFF','#000000'),(INK,'#FFFFFF')]):
 y=58+row*87;ImageDraw.Draw(im).rectangle((20,y,980,y+70),fill=bg)
 for i,((name,d),label) in enumerate(zip(MENUS.items(),labels)):
  x=64+i*188;paste(im,render(svg(18,18,path(d,fg)),36),(x,y+17));text(im,(x+47,y+25),label,13,fg)
save_png(im,'menubar/preview-menubar.png')

write('web/favicon.svg',icon(PAPER,TEAL))
ico=render(icon(PAPER,TEAL),48);ico.save(ROOT/'web/favicon.ico',sizes=[(16,16),(32,32),(48,48)],append_images=[icon_raster(PAPER,TEAL,16),icon_raster(PAPER,TEAL,32)])
save_png(render(icon(PAPER,TEAL),180),'web/apple-touch-icon-180.png')

def logo_image(width,c=INK):return render(svg(455,142,word_body(c)),width)
def editorial(w,h,github=False):
 im=Image.new('RGBA',(w,h),PAPER);d=ImageDraw.Draw(im)
 margin=72;d.line((margin,64,w-margin,64),fill=SAND,width=2)
 text(im,(margin,27),'Inlaut / LOKALES DIKTAT FÜR macOS',16,TEAL)
 paste(im,logo_image(430),(margin,106))
 text(im,(margin,282),'Sprechen. Loslassen.',42)
 text(im,(margin,338),'Weiterschreiben.',42)
 text(im,(margin,h-104),'Deine Stimme wird Text. Direkt am Cursor.',23)
 text(im,(margin,h-61),'Lokal auf deinem Mac. Ohne Konto. Ohne Cloud.',18,TEAL)
 paste(im,render(icon(PAPER,TEAL),300),(w-390,160))
 if github:text(im,(w-361,h-61),'CODE: GPL-3.0',16,TEAL)
 return im
save_png(editorial(1200,630),'web/og-image-1200x630.png')
save_png(editorial(1280,640,True),'web/github-social-1280x640.png')
im=Image.new('RGBA',(1600,400),PAPER)
paste(im,render(svg(576,576,f'<g transform="translate(-224 -224)">{symbol(TEAL)}</g>'),220),(66,90))
paste(im,logo_image(450),(344,61));text(im,(350,236),'Sprechen. Loslassen. Weiterschreiben.',32)
text(im,(1134,154),'Lokal auf deinem Mac.',23,TEAL);text(im,(1134,192),'Ohne Konto. Ohne Cloud.',23,TEAL)
save_png(im,'distribution/readme-header-1600x400.png')
# DMG backgrounds are purposefully empty at the requested icon centers.
for scale in [1,2]:
 im=Image.new('RGBA',(660*scale,400*scale),PAPER);paste(im,logo_image(160*scale),(250*scale,29*scale))
 centered(im,103*scale,'Ziehe Inlaut in den Ordner Programme.',18*scale,INK)
 arrow=svg(100,40,path('M0 17H84L72 5L76 1L98 20L76 39L72 35L84 23H0Z',TEAL))
 paste(im,render(arrow,76*scale),(292*scale,185*scale))
 centered(im,349*scale,'Danach findest du Inlaut in der Menüleiste.',14*scale,TEAL)
 save_png(im,'distribution/dmg-background-660x400'+('@2x' if scale==2 else '')+'.png')

tokens=[('paper','InlautPaper',PAPER,INK,'Markenfläche; UI bevorzugt Systemmaterial'),('surface','InlautSurface',SAND,'#243D3E','Sekundäre Markenfläche'),('ink','InlautInk',INK,PAPER,'Text auf Markenflächen; UI .primary'),('accent','InlautAccent',TEAL,MINT,'Sparsames tint und Links'),('recording','InlautRecording',RED,CORAL,'Aufnahmepunkt, kein kleiner Text auf Papier'),('border','InlautBorder',TEAL,MINT,'Bedeutungstragende Konturen; Deko darf Sand verwenden')]
write('tokens/colors.json',json.dumps({'colorSpace':'sRGB','colors':[{'name':n,'assetName':a,'light':l,'dark':d,'usage':u} for n,a,l,d,u in tokens]},ensure_ascii=False,indent=2)+'\n')
write('tokens/InlautColors.swift','// Inlaut design v1. Requires the named Color Sets described in README.md.\nimport SwiftUI\n\npublic extension Color {\n'+''.join(f'    static var inlaut{n.title()}: Color {{ Color("{a}") }}\n' for n,a,*_ in tokens)+'}\n')

# Native-size sheet plus nearest-neighbor enlargements to expose tiny raster defects.
im=Image.new('RGBA',(1200,760),PAPER);d=ImageDraw.Draw(im)
text(im,(32,20),'SETZPUNKT / Grössen- und Kontrastprobe',24)
text(im,(32,59),'Originalgrössen jeweils links; rechts 4× Pixelansicht. Flache Vorschauen, kein Systemglas.',15)
for row,(bg,fg,variant) in enumerate([(PAPER,'#000000','default'),(INK,'#FFFFFF','dark')]):
 y=106+row*252;d.rectangle((20,y,1180,y+232),fill=bg)
 for i,size in enumerate([16,32]):
  small=icon_raster(*variants[variant],size);x=48+i*220
  paste(im,small,(x,y+51));paste(im,small.resize((size*4,size*4),Image.Resampling.NEAREST),(x+54,y+33))
  text(im,(x,y+182),f'App-Icon {size} px',14,fg)
 for i,(name,glyph) in enumerate(MENUS.items()):
  x=516+i*130;small=render(svg(18,18,path(glyph,fg)),18)
  paste(im,small,(x,y+51));paste(im,small.resize((72,72),Image.Resampling.NEAREST),(x+24,y+40))
  text(im,(x,y+143),name,12,fg);text(im,(x,y+167),'18 px / 4×',12,fg)
text(im,(32,645),'Wortmarke · 90 px Mindestbreite',15);paste(im,logo_image(90),(32,683))
text(im,(362,645),'Wortmarke · 180 px',15);paste(im,logo_image(180),(362,673))
text(im,(725,645),'Farbe / Schwarz / Weiss: identische Pfade',15)
save_png(im,'checks/contact-sheet.png')
print('Artwork generated:',ROOT)

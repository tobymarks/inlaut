from pathlib import Path
from io import BytesIO
import cairosvg
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).parent
# Independent vector constructions; not extracted from generated mockups.
paths=[
'M8 1H10V17H8Z M6.5 1H11.5V2.5H6.5Z M6.5 15.5H11.5V17H6.5Z M3.5 6H5V12H3.5Z M13 6H14.5V12H13Z',
'M2 17V2Q2 1 3 1H4Q5 1 5 2V4Q7 3 9 3Q16 3 16 9V17H14V9Q14 5 9 5Q5 5 5 9V17Z M8 9Q8 8 9 8Q10 8 10 9V13Q10 14 9 14Q8 14 8 13Z',
'M1 10C2 10 2.5 4 5.5 4C8.5 4 8 12 11 12H15V9H17V14H11C6.5 14 6.5 6 5.5 6C4.5 6 4 12 1 12Z'
]
canvas=Image.new('RGB',(760,244),'#F6F2E9'); d=ImageDraw.Draw(canvas)
font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',14)
small=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',12)
d.text((20,14),'MENU BAR / READY — native 16 px and 32 px raster samples',font=font,fill='#182E30')
for i,(name,path) in enumerate(zip(['A / Setzpunkt','B / Innenraum','C / Sprechspur'],paths)):
 x=20+i*246
 d.text((x,47),name,font=font,fill='#182E30')
 for dark in [False,True]:
  y=78+dark*82; bg='#20252B' if dark else '#FFFFFF'; fg='#FFFFFF' if dark else '#000000'
  d.rectangle((x,y,x+225,y+65),fill=bg)
  for size,dx in [(16,38),(32,132)]:
   svg=f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><path fill="{fg}" d="{path}"/></svg>'
   raw=cairosvg.svg2png(bytestring=svg.encode(),output_width=size,output_height=size)
   icon=Image.open(BytesIO(raw)).convert('RGBA'); canvas.paste(icon,(x+dx,y+8+(32-size)//2),icon)
   d.text((x+dx-4,y+45),f'{size} px',font=small,fill=fg)
canvas.save(ROOT/'menubar-size-proof.png')

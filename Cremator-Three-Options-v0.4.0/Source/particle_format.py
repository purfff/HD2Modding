"""Decode bounded v0x73 particle sections; field semantics backed by recorded engine code."""
from pathlib import Path
import struct,json
HERE=Path(__file__).resolve().parent
INIT_SIZES={0:12,1:16,2:212,3:16,4:32,6:16}
# Opcode + payload: current EXE skip table RVA 0x1676820.
SIM_SIZES=[24,16,192,28,24,180,24,28,44,228,32,192,136,16,40,32,12,20,24,16,12,192,24,40,12,184,24,76,188,196,20,24,16,24,200,12,260,24,16]
def u(b,o):return struct.unpack_from('<I',b,o)[0]
def f(b,o,n=1):return list(struct.unpack_from('<'+'f'*n,b,o))
def decode(b):
 assert u(b,0)==0x73
 off=80+16*u(b,20);systems=[]
 for index in range(u(b,24)):
  size=u(b,off+256);co=u(b,off+232);eo=u(b,off+240);vo=u(b,off+252)
  assert 264<=co<=eo<=vo<=size and off+size<=len(b)
  item={'index':index,'offset':off,'size':size,'capacity':u(b,off),'position':f(b,off+168,3),'init':[],'sim':[]}
  for label,begin,end,sizes in [('init',co,eo,INIT_SIZES),('sim',eo,vo,SIM_SIZES)]:
   at=begin
   while at<end:
    op=u(b,off+at);step=sizes[op];assert at+step<=end
    entry={'offset':off+at,'op':op,'size':step,'words':list(struct.unpack_from('<'+'I'*(step//4-1),b,off+at+4))}
    if label=='init' and op in (1,2):entry['range']=f(b,off+at+8,2)
    if label=='sim' and op==28:entry['drag']=f(b,off+at+16)[0]
    if label=='sim' and op==11:entry['rate']=f(b,off+at+4,2)
    item[label].append(entry);at+=step
   assert at==end
  assert len(item['init'])==u(b,off+228)
  assert len(item['sim'])==u(b,off+236)
  if item['sim']:
   assert item['sim'][0]['op']==0
   age,_,life=item['sim'][0]['words'][:3]
   item['lifetime_slot']=life
   match=[x for x in item['init'] if x['op']==1 and x['words'][0]==life]
   assert len(match)==1
   item['lifetime']=match[0]['range'];item['lifetime_offset']=match[0]['offset']+8
  systems.append(item);off+=size
 assert off==len(b)
 return systems
if __name__=='__main__':
 out={}
 for name,file in [('cremator','cremator-df16f5c644edc2b1.main.bin'),('sentry','sentry_lumberer-0a4bd8a1833f11b2.main.bin')]:
  ss=decode((HERE/'native_effects'/file).read_bytes());out[name]=ss
  for s in ss:print(name,s['index'],'cap',s['capacity'],'life',s.get('lifetime'),'ops',[x['op'] for x in s['sim']],'drag',[x.get('drag') for x in s['sim'] if x['op']==28],'rate',[x.get('rate') for x in s['sim'] if x['op']==11])
 (HERE/'native_effects/decoded.json').write_text(json.dumps(out,indent=2))

#!/usr/bin/env python3
"""Build data/graph.json (nodes + edges) from data/shelves.json, picks.json, books.json, edges.json,
skipping anything in blocklist.json and flagging wantlist.json. Generic: clusters come from config.json."""
import json,re,os,urllib.parse
os.chdir(os.path.dirname(os.path.abspath(__file__)))
cfg=json.load(open("config.json"))
def load(f,d):
  p="data/"+f
  return json.load(open(p)) if os.path.exists(p) else d
short=lambda t:re.split(r"[:(]",t)[0].strip()
CL=cfg["clusters"]; DEF=cfg.get("default_cluster") or next(iter(CL))
sh=load("shelves.json",{}); picks=load("picks.json",[]); books=load("books.json",{}); L=[tuple(e) for e in load("edges.json",[])]
low=lambda xs:{(x["title"] if isinstance(x,dict) else x).lower() for x in xs}
BL=low(load("blocklist.json",[])); WL=low(load("wantlist.json",[]))
amz=lambda t,a:"https://www.amazon.com/s?k="+urllib.parse.quote_plus(short(t)+" "+a.split("&")[0].strip())+"&i=stripbooks"
shelf={}
for s in ("currently-reading","read","to-read"):
  for b in sh.get(s,[]): shelf.setdefault(short(b["title"]),(s,b))
nodes=[];edges=[]
for t,(s,b) in shelf.items():
  meta=books.get(t,{}); c=meta.get("cluster",DEF); c=c if c in CL else DEF; a=re.sub(r"\s+"," ",b["author"])
  nodes.append(dict(id=t,label=t,kind="book",shelf=s,cluster=c,author=a,note=meta.get("note",""),year=b.get("year"),myrating=b.get("rating"),amazon=amz(t,a)))
for p in picks:
  t,a,y,r,cl,w,ed,src,k=p[:9]; cover=p[9] if len(p)>9 else None; s=short(t)
  if s.lower() in BL or t.lower() in BL or s in shelf: continue
  cl=cl if cl in CL else ("wild" if k=="w" and "wild" in CL else DEF)
  nodes.append(dict(id=s,label=s,full=t,kind="wild" if k=="w" else "pick",shelf="suggestion",cluster=cl,author=a,year=y,rating=r,why=w,note=w,
    source=src,want=t.lower() in WL,amazon=amz(t,a),cover_url=cover))
  L+=[(s,x,l) for x,l in ed]
used={n["cluster"] for n in nodes}
for k,v in CL.items():
  if k in used: nodes.append(dict(id="C:"+k,label=v["name"],kind="cluster",cluster=k))
for n in nodes:
  if n["kind"]!="cluster": edges.append(dict(source=n["id"],target="C:"+n["cluster"],label="",kind="member"))
ids={n["id"] for n in nodes}
for a,b,l in L:
  if a in ids and b in ids: edges.append(dict(source=a,target=b,label=l,kind="rel"))
json.dump(dict(nodes=nodes,edges=edges,clusters={k:{"name":v["name"],"color":v["color"]} for k,v in CL.items()}),open("data/graph.json","w"),ensure_ascii=False)
print(f"{sum(n['kind']=='book' for n in nodes)} books, {sum(n['kind'] in('pick','wild') for n in nodes)} picks, {len(edges)} edges")

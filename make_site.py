#!/usr/bin/env python3
"""Assemble dist/: index.html (generic template) + data.js (user data) + vendor/ + covers/ (cached from Open Library)."""
import json,os,re,shutil,sys,time,urllib.request,urllib.parse
os.chdir(os.path.dirname(os.path.abspath(__file__)))
cfg=json.load(open("config.json")); D=json.load(open("data/graph.json"))
os.makedirs("dist/covers",exist_ok=True); shutil.copytree("site/vendor","dist/vendor",dirs_exist_ok=True)
CACHE="data/covers.json"; cache=json.load(open(CACHE)) if os.path.exists(CACHE) else {}
slug=lambda s:re.sub(r"[^a-z0-9]+","-",s.lower()).strip("-")[:60]
def get(u):
  b=urllib.request.urlopen(u,timeout=30).read(); return b if len(b)>2000 else None
for n in D["nodes"]:
  if n["kind"]=="cluster": continue
  key=n["id"]; f=f"covers/{slug(key)}.jpg"; want=n.pop("cover_url",None) or ""
  if cache.get(key+"|src")!=want or (cache.get(key) and not os.path.exists("dist/"+cache[key])):
    cache[key]=None; cache[key+"|src"]=want
    try:
      img=get(want.replace("-L.jpg","-M.jpg")) if want else None
      if not img:
        q=urllib.parse.urlencode({"title":n.get("full",n["label"]).split(":")[0],"author":re.split(r"&|,",n.get("author",""))[0].strip(),"limit":5,"fields":"cover_i"})
        cid=next((d["cover_i"] for d in json.load(urllib.request.urlopen("https://openlibrary.org/search.json?"+q,timeout=20))["docs"] if d.get("cover_i")),None)
        img=get(f"https://covers.openlibrary.org/b/id/{cid}-M.jpg") if cid else None
      if img: open("dist/"+f,"wb").write(img); cache[key]=f
    except Exception as e: print("cover err",key,e,file=sys.stderr)
  if cache.get(key): n["cover"]=cache[key]
json.dump(cache,open(CACHE,"w"),indent=1)
if os.path.exists("data/positions.json"):
  P=json.load(open("data/positions.json"))
  for n in D["nodes"]:
    if n["id"] in P: n["x"],n["y"]=P[n["id"]]
D["meta"]={"title":cfg.get("site_title","Alexandria"),"subtitle":cfg.get("site_subtitle",""),"footer":cfg.get("footer","Built by Alexandria"),"api":cfg.get("worker_url","")}
open("dist/data.js","w").write("window.ALEXANDRIA_DATA="+json.dumps(D,ensure_ascii=False)+";")
open("dist/index.html","w").write(open("site/template.html").read().replace('src="data.js"',f'src="data.js?v={int(time.time())}"'))
print("covers:",sum(1 for n in D["nodes"] if n.get("cover")),"/",sum(1 for n in D["nodes"] if n["kind"]!="cluster"))

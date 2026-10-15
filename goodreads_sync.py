#!/usr/bin/env python3
"""Sync the user's Goodreads shelves into data/shelves.json (user id: env GOODREADS_USER_ID or config.json goodreads_user_id).
Diffs against the current shelves.json, writes goodreads_changes.json (+ prints a short summary),
drops any suggestion the user has now shelved from picks.json, and rebuilds + republishes only if something changed.
Usage: python3 goodreads_sync.py [--dry-run]"""
import json,re,sys,subprocess,urllib.request,xml.etree.ElementTree as ET,datetime,os
os.chdir(os.path.dirname(os.path.abspath(__file__)))
UID=os.environ.get("GOODREADS_USER_ID") or str(json.load(open("config.json"))["goodreads_user_id"]); SHELVES=["currently-reading","read","to-read"]; DRY="--dry-run" in sys.argv
NAMES={"currently-reading":"currently reading","read":"read","to-read":"want to read"}
def fetch(shelf):
  out=[]
  for page in range(1,30):
    req=urllib.request.Request(f"https://www.goodreads.com/review/list_rss/{UID}?shelf={shelf}&page={page}",headers={"User-Agent":"Mozilla/5.0"})
    items=ET.fromstring(urllib.request.urlopen(req,timeout=30).read()).findall("./channel/item")
    if not items: break
    for it in items:
      g=lambda t:(it.findtext(t) or "").strip()
      out.append({"title":g("title"),"author":g("author_name"),"year":g("book_published"),"rating":g("user_rating") or "0"})
    if len(items)<100: break
  return out
short=lambda t:re.split(r"[:(]",t)[0].strip().lower()
old=json.load(open("data/shelves.json")) if os.path.exists("data/shelves.json") else {}
new={}
for s in SHELVES:
  try: new[s]=fetch(s)
  except Exception as e: sys.exit(f"Goodreads fetch failed for {s}: {e} (nothing changed)")
if not sum(map(len,new.values())) and sum(map(len,old.values())): sys.exit("Goodreads returned no books at all (private or down?); nothing changed")
loc=lambda d:{short(b["title"]):(s,b) for s in SHELVES for b in d.get(s,[])}
O,N=loc(old),loc(new)
added=[(N[k][1]["title"],N[k][0]) for k in N if k not in O]
removed=[(O[k][1]["title"],O[k][0]) for k in O if k not in N]
moved=[(N[k][1]["title"],O[k][0],N[k][0]) for k in N if k in O and O[k][0]!=N[k][0]]
rated=[(N[k][1]["title"],N[k][1]["rating"]) for k in N if k in O and N[k][1]["rating"]!=O[k][1]["rating"] and N[k][1]["rating"]!="0"]
picks=json.load(open("data/picks.json")) if os.path.exists("data/picks.json") else []
dropped=[p[0] for p in picks if short(p[0]) in N]
changed=bool(added or removed or moved or rated or dropped)
lines=[]
for t,s in added: lines.append(f"+ {t} ({NAMES[s]})")
for t,a,b in moved: lines.append(f"→ {t}: {NAMES[a]} → {NAMES[b]}")
for t,r in rated: lines.append(f"★ {t}: rated {r}/5")
for t,s in removed: lines.append(f"− {t} (no longer on {NAMES[s]})")
for t in dropped: lines.append(f"✓ dropped suggestion now on his shelves: {t}")
if not changed: print("no changes"); sys.exit(0)
if not old: print("(first sync)")
print(f"Goodreads: {len(added)} added, {len(moved)} moved, {len(rated)} rated, {len(removed)} removed, {len(dropped)} suggestions dropped"); print("\n".join(lines))
if DRY: print("(dry run: nothing written)"); sys.exit(0)
json.dump({"at":datetime.datetime.now().isoformat(timespec="seconds"),"added":added,"moved":moved,"rated":rated,"removed":removed,"dropped_suggestions":dropped},open("data/goodreads_changes.json","w"),ensure_ascii=False,indent=1)
json.dump(new,open("data/shelves.json","w"),ensure_ascii=False,indent=1)
if dropped: json.dump([p for p in picks if p[0] not in dropped],open("data/picks.json","w"),ensure_ascii=False,indent=1)
if added or removed or dropped:  # node set changed: recompute positions on publish
  if os.path.exists("data/positions.json"): os.remove("data/positions.json")
if os.environ.get("NO_PUBLISH"): print("shelves updated (NO_PUBLISH set: not republished)"); sys.exit(0)
subprocess.run(["./publish_map.sh"],check=True,stdout=subprocess.DEVNULL)
print("rebuilt and republished")

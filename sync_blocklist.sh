#!/usr/bin/env bash
# Pull 👍/👎 events from the Alexandria worker (GET /events) into local state, then rebuild + republish.
#   thumbs_down -> blocklist.json (never suggested again; dropped from wantlist)
#   thumbs_up   -> wantlist.json  (shown under "Want to read" on the site)
# Idempotent: already-applied titles are skipped; republishes only when something changed.
# Usage: ./sync_blocklist.sh [--dry-run]
set -euo pipefail
source "$(dirname "$0")/lib.sh"
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1
API=$(cfg worker_url); [[ -n $API ]] || { echo "no worker_url in config.json"; exit 1; }
curl -fsS --get "$API/events" --data-urlencode "key@$(read_key_file)" -o /tmp/alex_events.json
DRY=$DRY python3 - <<'PY'
import json,os
dry=os.environ["DRY"]=="1"
ev=json.load(open("/tmp/alex_events.json"))
picks={p[0].lower():p for p in json.load(open("data/picks.json"))}
bl=json.load(open("data/blocklist.json")); wl=json.load(open("data/wantlist.json"))
B={b["title"].lower() for b in bl}; W={w["title"].lower() for w in wl}
down=[];up=[];undone=[]
last={}  # (title, list) -> last event; replaying the full log is idempotent
for e in sorted(ev["events"],key=lambda e:e["ts"]):
  p=picks.get((e.get("title") or "").lower())
  if not p: continue
  t=e["type"]; lst={"thumbs_down":"down","thumbs_up":"up"}.get(t) or ({"thumbs_down":"down","thumbs_up":"up"}.get(e.get("note","")) if t=="undo" else None)
  if lst: last[(p[0],lst)]=(t,e["ts"],p)
for (title,lst),(t,ts,p) in last.items():
  k=title.lower(); rec={"title":title,"author":p[1],"at":ts}
  if lst=="down":
    if t=="thumbs_down" and k not in B: B.add(k); bl.append(rec); down.append(title)
    if t=="undo" and k in B: B.discard(k); bl=[x for x in bl if x["title"].lower()!=k]; undone.append("👎 "+title)
  else:
    if t=="thumbs_up" and k not in W: W.add(k); wl.append(rec); up.append(title)
    if t=="undo" and k in W: W.discard(k); wl=[x for x in wl if x["title"].lower()!=k]; undone.append("👍 "+title)
wl=[w for w in wl if w["title"].lower() not in B]
print(f"events: {ev['count']} (tripped: {ev.get('tripped')}) | new 👎: {down or 'none'} | new 👍: {up or 'none'} | undone: {undone or 'none'}")
changed=bool(down or up or undone)
if changed and not dry:
  json.dump(bl,open("data/blocklist.json","w"),ensure_ascii=False,indent=1); json.dump(wl,open("data/wantlist.json","w"),ensure_ascii=False,indent=1)
open("/tmp/alex_changed","w").write("1" if changed and not dry else "")
PY
rm -f /tmp/alex_events.json
if [[ -s /tmp/alex_changed ]]; then ./publish_map.sh; else [[ $DRY == 1 ]] && echo "dry run: nothing written" || echo "no changes"; fi

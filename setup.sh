#!/usr/bin/env bash
# Alexandria one-shot setup (idempotent: safe to re-run; finished steps are skipped).
# Needs: config.json (copy config.example.json), gh logged in, node >= 18, python3,
#        env CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID, ALEXANDRIA_WEBHOOK_URL, ALEXANDRIA_WEBHOOK.
# Usage: ./setup.sh [--dry-run]     (--dry-run: check everything, print what would happen, change nothing remote)
set -euo pipefail; source "$(dirname "$0")/lib.sh"
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1
say(){ printf '\n== %s\n' "$*"; }
do_(){ if [[ $DRY == 1 ]]; then echo "  [dry-run] $*"; else "$@"; fi; }
die(){ echo "ERROR: $*" >&2; exit 1; }
CF=https://api.cloudflare.com/client/v4

say "0. Checks"
[[ -f config.json ]] || die "config.json missing: cp config.example.json config.json and fill it in"
python3 -c 'import json;json.load(open("config.json"))' || die "config.json is not valid JSON"
for k in goodreads_user_id display_name github_owner worker_name; do [[ -n "$(cfg $k)" ]] || die "config.json: $k is empty"; done
command -v python3 >/dev/null || die "python3 not found"
command -v node >/dev/null && [[ $(node -p 'process.versions.node.split(".")[0]') -ge 18 ]] || die "node >= 18 required (wrangler 3)"
command -v gh >/dev/null || die "gh (GitHub CLI) not found"
for v in CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID ALEXANDRIA_WEBHOOK_URL ALEXANDRIA_WEBHOOK; do [[ -n "${!v:-}" ]] || die "env $v is not set"; done
[[ "$ALEXANDRIA_WEBHOOK_URL" == https://* ]] || die "ALEXANDRIA_WEBHOOK_URL must be an https URL"
if [[ $DRY == 0 ]]; then gh auth status >/dev/null 2>&1 || die "gh is not logged in (gh auth login)"; else echo "  [dry-run] skip gh auth check"; fi
OWNER=$(cfg github_owner); WN=$(cfg worker_name); ORIGIN="https://${OWNER,,}.github.io"
echo "  ok: owner=$OWNER worker=$WN origin=$ORIGIN"

say "1. Local data files"
mkdir -p data; for f in picks blocklist wantlist; do [[ -f data/$f.json ]] || echo '[]' > data/$f.json; done; [[ -f data/books.json ]] || echo '{}' > data/books.json; [[ -f data/edges.json ]] || echo '[]' > data/edges.json
echo "  data/: $(ls data | tr '\n' ' ')"

say "2. Goodreads shelves (user $(cfg goodreads_user_id))"
if [[ $DRY == 1 ]]; then echo "  [dry-run] would run: NO_PUBLISH=1 python3 goodreads_sync.py"; else NO_PUBLISH=1 python3 goodreads_sync.py; fi

say "3. GitHub Pages repo"
R=$(cfg pages_repo)
if [[ -z $R ]]; then R="alexandria-map-$(python3 -c 'import secrets;print(secrets.token_hex(6))')"; echo "  new unguessable repo name: $R"; [[ $DRY == 1 ]] || cfg_set pages_repo "$R"; fi
if [[ $DRY == 1 ]] || ! gh repo view "$OWNER/$R" >/dev/null 2>&1; then
  do_ gh repo create "$OWNER/$R" --public --add-readme -d "Alexandria reading map (build output)"
fi
if [[ $DRY == 1 ]] || ! gh api "repos/$OWNER/$R/pages" >/dev/null 2>&1; then
  do_ gh api -X POST "repos/$OWNER/$R/pages" -f "source[branch]=main" -f "source[path]=/"
fi
echo "  site: https://${OWNER,,}.github.io/$R/"

say "4. Cloudflare: workers.dev subdomain, KV, worker, secrets"
cfapi(){ curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H 'Content-Type: application/json' "$@"; }
if [[ $DRY == 1 ]]; then SUB=$(cfg workers_subdomain); SUB=${SUB:-${OWNER,,}}; echo "  [dry-run] would ensure workers.dev subdomain '$SUB' and a KV namespace '$WN-kv'"
else
  SUB=$(cfapi "$CF/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/subdomain" | python3 -c 'import sys,json;print((json.load(sys.stdin).get("result") or {}).get("subdomain",""))')
  if [[ -z $SUB ]]; then SUB=$(cfg workers_subdomain); SUB=${SUB:-${OWNER,,}}
    cfapi -X PUT -d "{\"subdomain\":\"$SUB\"}" "$CF/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/subdomain" | python3 -c 'import sys,json;d=json.load(sys.stdin);sys.exit(0 if d.get("success") else "subdomain: "+str(d.get("errors")))'
    echo "  registered $SUB.workers.dev (its TLS cert can take a few minutes)"; fi
  cfg_set workers_subdomain "$SUB"
  KV=$(cfg kv_namespace_id)
  if [[ -z $KV ]]; then
    KV=$(cfapi "$CF/accounts/$CLOUDFLARE_ACCOUNT_ID/storage/kv/namespaces?per_page=100" | python3 -c "import sys,json;print(next((n['id'] for n in json.load(sys.stdin).get('result') or [] if n['title']=='$WN-kv'),''))")
    [[ -n $KV ]] || KV=$(cfapi -X POST -d "{\"title\":\"$WN-kv\"}" "$CF/accounts/$CLOUDFLARE_ACCOUNT_ID/storage/kv/namespaces" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["result"]["id"]) if d.get("success") else sys.exit("kv: "+str(d.get("errors")))')
    cfg_set kv_namespace_id "$KV"; fi
fi
KV=$(cfg kv_namespace_id); KV=${KV:-DRYRUN_KV_ID}
sed -e "s/__WORKER_NAME__/$WN/" -e "s/__ACCOUNT_ID__/$CLOUDFLARE_ACCOUNT_ID/" -e "s/__KV_ID__/$KV/" -e "s#__ORIGIN__#$ORIGIN#" worker/wrangler.toml.example > worker/wrangler.toml
echo "  wrote worker/wrangler.toml"
RK=$(read_key_file)
if [[ ! -s $RK ]]; then if [[ $DRY == 1 ]]; then echo "  [dry-run] would generate read key -> $RK"; else (umask 077; mkdir -p "$(dirname "$RK")"; python3 -c 'import secrets;print(secrets.token_urlsafe(32),end="")' > "$RK"); echo "  generated read key -> $RK"; fi; fi
if [[ $DRY == 1 ]]; then echo "  [dry-run] would: npm install (worker/), wrangler deploy, wrangler secret put WEBHOOK_URL / WEBHOOK_KEY / READ_KEY (via stdin)"
else
  (cd worker && npm install --silent >/dev/null 2>&1 && npx wrangler deploy >/dev/null)
  (cd worker && printf %s "$ALEXANDRIA_WEBHOOK_URL" | npx wrangler secret put WEBHOOK_URL >/dev/null 2>&1)
  (cd worker && printf %s "$ALEXANDRIA_WEBHOOK"     | npx wrangler secret put WEBHOOK_KEY >/dev/null 2>&1)
  (cd worker && npx wrangler secret put READ_KEY < "$RK" >/dev/null 2>&1)
  echo "  worker deployed, 3 secrets set"
fi
URL="https://$WN.$SUB.workers.dev"; [[ $DRY == 1 ]] || cfg_set worker_url "$URL"; echo "  worker: $URL"

say "5. Build + publish"
if [[ $DRY == 1 ]]; then ./publish_map.sh --dry-run; else ./publish_map.sh; fi

say "Done"
echo "Site:   https://${OWNER,,}.github.io/$R/   (first Pages build ~1-2 min)"
echo "Worker: $URL   (audit: GET /events?key=<contents of $RK>)"
echo "Next: the bot researches picks into data/picks.json (see data/README.md), then ./publish_map.sh"

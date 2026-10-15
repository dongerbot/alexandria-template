#!/usr/bin/env bash
# Refresh the worker's allowed-title list in KV (all picks, including blocklisted ones so "undo" still validates).
set -euo pipefail; source "$(dirname "$0")/lib.sh"
: "${CLOUDFLARE_API_TOKEN:?}" "${CLOUDFLARE_ACCOUNT_ID:?}"
KV=$(cfg kv_namespace_id); [[ -n $KV ]] || { echo "no kv_namespace_id in config.json (run setup.sh)"; exit 1; }
python3 - > /tmp/alex_titles.json <<'P'
import json,re,os
p=json.load(open("data/picks.json")) if os.path.exists("data/picks.json") else []
print(json.dumps([{"title":x[0],"short":re.split(r"[:(]",x[0])[0].strip(),"author":x[1]} for x in p],ensure_ascii=False))
P
(cd worker && npx --yes wrangler kv key put --namespace-id="$KV" titles --path /tmp/alex_titles.json >/dev/null)
echo "titles pushed: $(python3 -c 'import json;print(len(json.load(open("/tmp/alex_titles.json"))))')"

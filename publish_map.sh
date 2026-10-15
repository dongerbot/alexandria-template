#!/usr/bin/env bash
# Rebuild the site and deploy it to Cloudflare Pages (project pages_project in config.json),
# behind the password gate in pages/functions/_middleware.js (SITE_PASSWORD secret, set by setup.sh).
# Usage: ./publish_map.sh [--dry-run]
set -euo pipefail; source "$(dirname "$0")/lib.sh"
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1
python3 build.py
python3 make_site.py
[[ -s data/positions.json ]] || python3 layout.py || echo "WARN: layout.py failed (install playwright); map will lay itself out in the browser"
if [[ -n "${CLOUDFLARE_API_TOKEN:-}" && -n "$(cfg kv_namespace_id)" && $DRY == 0 ]]; then ./push_titles.sh || echo "WARN: titles not refreshed"; fi
PP=$(cfg pages_project)
if [[ $DRY == 1 ]]; then echo "dry run: built dist/; would deploy it with pages/functions/ to Cloudflare Pages project ${PP:-<pages_project from setup.sh>}"; exit 0; fi
[[ -n $PP ]] || { echo "no pages_project in config.json (run setup.sh)"; exit 1; }
for v in CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID; do [[ -n "${!v:-}" ]] || { echo "env $v is not set"; exit 1; }; done
[[ -x worker/node_modules/.bin/wrangler ]] || (cd worker && npm install --silent >/dev/null 2>&1)
export WRANGLER_CACHE_DIR=${WRANGLER_CACHE_DIR:-${TMPDIR:-/tmp}/wrangler-cache}
rm -rf pages/public; cp -r dist pages/public
(cd pages && ../worker/node_modules/.bin/wrangler pages deploy public --project-name "$PP" --branch main --commit-dirty=true 2>&1 | grep -E "Deployment complete|ERROR") || { echo "deploy failed"; exit 1; }
echo "$(cfg site_url)  (password-protected)"

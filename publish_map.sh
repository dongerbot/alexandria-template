#!/usr/bin/env bash
# Rebuild the site and publish it to GitHub Pages (https://<owner>.github.io/<pages_repo>/).
# Usage: ./publish_map.sh [--dry-run]
set -euo pipefail; source "$(dirname "$0")/lib.sh"
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1
python3 build.py
python3 make_site.py
[[ -s data/positions.json ]] || python3 layout.py || echo "WARN: layout.py failed (install playwright); map will lay itself out in the browser"
if [[ -n "${CLOUDFLARE_API_TOKEN:-}" && -n "$(cfg kv_namespace_id)" && $DRY == 0 ]]; then ./push_titles.sh || echo "WARN: titles not refreshed"; fi
OWNER=$(cfg github_owner); R=$(cfg pages_repo)
if [[ $DRY == 1 ]]; then echo "dry run: built dist/; would publish it to $OWNER/${R:-<pages_repo from setup.sh>}"; exit 0; fi
[[ -n $R ]] || { echo "no pages_repo in config.json (run setup.sh)"; exit 1; }
W=${TMPDIR:-/tmp}/alexandria-pages-$R
[[ -d $W/.git ]] || { rm -rf "$W"; gh repo clone "$OWNER/$R" "$W" -- -q; }
git -C "$W" pull -q --rebase 2>/dev/null || true
find "$W" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +; cp -r dist/. "$W/"; touch "$W/.nojekyll"
git -C "$W" add -A
git -C "$W" -c user.name="$OWNER" -c user.email="$OWNER@users.noreply.github.com" commit -qm "update map $(date +%F_%H%M)" || echo "no changes"
git -C "$W" push -q origin HEAD:main
echo "https://$OWNER.github.io/$R/  (Pages takes ~1 min to update)"

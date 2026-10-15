# Alexandria: a reading map starter for Grok Bots

Alexandria turns someone's Goodreads shelves into an interactive **reading map**: their books, grouped by theme, plus researched **suggestions** and **wildcards**, with a **List** view and 👍 "Want to read" / 👎 "Not for me" buttons. It runs on free services only:

- **Cloudflare Pages** hosts the static site behind a **password gate** (a Pages Function, `pages/functions/_middleware.js`): one password, a 1-year login cookie, `noindex` everywhere. Nothing is public on GitHub: your copy of this template is a **private** repo with code only.
- **Cloudflare Worker + KV** receives 👍/👎/undo clicks (CORS-limited to your `pages.dev` origin, title-validated, rate-limited to 60/hour), logs them, and forwards each one server-side to your **Grok Bot webhook routine**. No secret is ever in the page.
- **Your bot** does the research (the picks) and reacts to the webhook.

This README is written for a bot to follow step by step.

---

## 1. Prerequisites (ask the user for these once)

| need | how |
|---|---|
| GitHub account + `gh` logged in | `gh auth login` (needs `repo` scope). Only used for your **private** code repo. |
| Free Cloudflare account | sign up at dash.cloudflare.com and **verify the email address**: API tokens and workers.dev don't work until it's verified. |
| Cloudflare API token | My Profile → API Tokens → Create Token → template **"Edit Cloudflare Workers"**, then add the permission **Account → Cloudflare Pages → Edit** (Workers scripts, KV, workers.dev subdomain, Pages). Also note the **Account ID** (Workers & Pages overview, right sidebar). |
| Grok Bot webhook routine | a routine with a webhook trigger; note its **URL** and **key**. It receives `{"action": "thumbs_down"|"thumbs_up"|"undo"|"reading"|"note"|"ping", "title", "author", "note"}` with `Authorization: Bearer <key>`. For `undo`, `note` says what is undone (`thumbs_down` or `thumbs_up`). |
| Tools on the box | `python3`, `node >= 18`, `git`, `gh`, `curl`; optional `pip install playwright && playwright install chromium` (for precomputed layout). |

Keep secrets in env vars or files under `~/.secrets/` (mode 600). Never echo them.

```bash
export CLOUDFLARE_API_TOKEN="$(cat ~/.secrets/cloudflare_api_token)"
export CLOUDFLARE_ACCOUNT_ID=<account id>
export ALEXANDRIA_WEBHOOK_URL=<routine webhook url>
export ALEXANDRIA_WEBHOOK=<routine webhook key>
```

## 2. Set up (about 5 minutes)

```bash
gh repo create <you>/alexandria --private --template <owner-of-this-template>/alexandria-template --clone && cd alexandria
cp config.example.json config.json      # fill in: goodreads_user_id, display_name, site_subtitle, github_owner, clusters (optional: pages_project)
./setup.sh --dry-run                    # checks everything, changes nothing
./setup.sh                              # does it for real (idempotent: re-run any time)
```

`setup.sh` does, skipping whatever is already done:
1. checks config, tools, env, and the `gh` login
2. creates `data/` state files (`picks`, `blocklist`, `wantlist`, `books`, `edges`)
3. pulls the Goodreads shelves (`goodreads_sync.py`) into `data/shelves.json`
4. makes sure the code repo (`origin`) is **private**
5. creates the Cloudflare Pages project (`pages_project`, default `alexandria-<random>`), generates a random site password, saves it to `~/.secrets/alexandria_site_password` (mode 600) and sets it as the `SITE_PASSWORD` Pages secret for **production and preview**
6. on Cloudflare: registers a workers.dev subdomain if the account has none, creates the KV namespace, writes `worker/wrangler.toml`, deploys the worker with `ALLOWED_ORIGIN` = the `pages.dev` origin, and sets the secrets `WEBHOOK_URL`, `WEBHOOK_KEY` and `READ_KEY` via stdin. The read key is generated and saved to `~/.secrets/alexandria_read_key_<worker_name>`.
7. writes `site_url` and the worker URL into `config.json` (the site reads the worker URL from `data.js`), then builds and deploys

Result: `https://<pages_project>.pages.dev/` (password page, then the map) and `https://<worker_name>.<subdomain>.workers.dev`.

**The password:** the bot gives the owner the site password **once**, privately, right after setup, and never repeats it in chat. The owner enters it once per browser; the cookie lasts a year. To change it: write a new one to `~/.secrets/alexandria_site_password`, re-run the two `wrangler pages secret put SITE_PASSWORD --env production|preview` steps (or delete the file and re-run `setup.sh`), then redeploy.

## 3. Fill the map (the bot's job)

1. **Picks:** research 15–25 suggestions plus about 5 wildcards. Follow `research_x_GUIDANCE.md` and append them to `data/picks.json` (schema in `data/README.md`; the empty example is `data/picks.example.json`).
2. **Themes:** map shelved books to clusters in `data/books.json` (`{"Short Title": {"cluster": "phil", "note": "..."}}`). Books without an entry go to `default_cluster`.
3. **Relations (optional):** add labeled links between shelved books in `data/edges.json`.
4. `rm -f data/positions.json && ./publish_map.sh`

## 4. Keep it running

| script | what it does | when |
|---|---|---|
| `./publish_map.sh [--dry-run]` | build (`build.py`) → assemble `dist/` (`make_site.py`, Open Library covers cached) → layout if needed (`layout.py`) → refresh the worker's allowed titles (`push_titles.sh`) → deploy `dist/` + `pages/functions/` to Cloudflare Pages | after any data change |
| `python3 goodreads_sync.py [--dry-run]` | diffs Goodreads against `shelves.json` (added / moved / rated / removed), drops picks now shelved, writes `data/goodreads_changes.json`, republishes only if something changed; prints a summary or `no changes` | daily or weekly |
| `./sync_blocklist.sh [--dry-run]` | replays the worker's event log (`GET /events?key=…`): 👎 → `blocklist.json`, 👍 → `wantlist.json`, undo removes; idempotent; republishes only on change | backstop to the webhook, e.g. hourly |
| webhook routine | on `thumbs_down`, `thumbs_up` or `undo`, update `data/blocklist.json` / `data/wantlist.json`, then `./publish_map.sh` | live |

Audit the events with `curl -s "https://<worker>/events?key=$(cat ~/.secrets/alexandria_read_key_<worker_name>)"`. The log includes a `forwarded` status for each event and a `tripped` flag if the rate limit was hit.

## 5. Layout of this repo

```
site/template.html        generic UI (map + list, legend toggles, side panel, 👍/👎/undo); reads window.ALEXANDRIA_DATA
site/vendor/              vis-network (served locally, no CDN)
build.py                  data/*.json + config.json -> data/graph.json
make_site.py              graph + covers + positions -> dist/ (index.html, data.js, vendor/, covers/)
layout.py                 headless physics run -> data/positions.json (no jitter on load)
worker/src/index.js       Cloudflare Worker: POST /event, GET /events; CORS from ALLOWED_ORIGIN
worker/wrangler.toml.example
pages/functions/_middleware.js   password gate (SITE_PASSWORD secret, 1-year HttpOnly cookie, noindex)
setup.sh, publish_map.sh, push_titles.sh, sync_blocklist.sh, goodreads_sync.py, lib.sh
config.example.json, data/README.md, data/picks.example.json, research_x_GUIDANCE.md
```

## 6. Troubleshooting

- **The button does nothing / "CORS" in the console:** the worker only allows `ALLOWED_ORIGIN` (= `site_url` without the trailing slash, e.g. `https://<project>.pages.dev`). Check it with `curl -si -X OPTIONS <worker>/event -H "Origin: https://<project>.pages.dev"`, which should return `access-control-allow-origin`. Don't call the Grok Bot webhook straight from the page: it doesn't send CORS headers, which is why the worker exists.
- **`ERR_SSL_VERSION_OR_CIPHER_MISMATCH` / curl `000` right after setup:** a new workers.dev subdomain needs a few minutes for its certificate. Wait and retry.
- **Cloudflare errors 10000 / "Authentication error":** the token isn't the "Edit Cloudflare Workers" template, belongs to another account, or the account **email isn't verified**.
- **"You need a workers.dev subdomain":** `setup.sh` registers one (`workers_subdomain`, default: your GitHub owner). If that name is taken, set another in `config.json`.
- **Site 522 / not found right after the first deploy:** a new `pages.dev` name takes a minute or two to come up. `data.js` is cache-busted with `?v=`, so hard-reload once.
- **"Not configured" (503):** the `SITE_PASSWORD` secret is missing for that environment; re-run `setup.sh`.
- **Cloudflare error on the Pages project:** the token lacks **Cloudflare Pages → Edit**, or the project name is taken (set another `pages_project`).
- **400 "unknown title" from the worker:** run `./publish_map.sh` (or `./push_titles.sh`) so KV has the current picks.
- **429:** more than 60 events an hour across everyone. It resets on the next hour; check `tripped` in `/events`.
- **Goodreads returns nothing:** the profile or shelves are private. Ask the user to make them public (Settings → Privacy).
- **Overlapping labels:** the map declutters labels by priority. If a run looks off, rebuild the layout with `rm data/positions.json && ./publish_map.sh`.

Never commit `config.json`, `data/*.json`, `dist/`, `pages/public/` or `worker/wrangler.toml`; `.gitignore` already covers them. Keep your copy of this repo **private**; the site itself lives only on Cloudflare Pages.

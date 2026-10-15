# Data files (per user; created by setup.sh / the bot, git-ignored in your private copy)

| file | written by | format |
|---|---|---|
| `shelves.json` | `goodreads_sync.py` | `{"currently-reading":[book],"read":[book],"to-read":[book]}`, book = `{"title","author","year","rating"}` (rating "0"–"5") |
| `picks.json` | **the bot** (research) | list of picks, see below |
| `books.json` | the bot (optional) | `{"<short title>": {"cluster":"phil","note":"one line about this shelved book"}}` — assigns shelved books to clusters |
| `edges.json` | the bot (optional) | `[["Book A","Book B","label, e.g. responds to"], ...]` between shelved books |
| `blocklist.json` | `sync_blocklist.sh` / webhook routine | `[{"title","author","at"}]` — 👎, never suggested again |
| `wantlist.json` | `sync_blocklist.sh` / webhook routine | `[{"title","author","at"}]` — 👍 "Want to read" |
| `positions.json` | `layout.py` | precomputed node positions |

## picks.json schema
Each entry is a 10-element array (empty example: `[]`):
```
[ title, author, year, fit_rating_1_to_10, cluster_key, why_one_sentence,
  [[ "shelved book short title", "relation label" ], ...],
  source_url, kind ("s" = suggestion, "w" = wildcard), cover_url_or_null ]
```
Example:
```json
[["The Origin of Species","Charles Darwin",1859,8,"sci","The founding argument for evolution by natural selection.",
  [["Some Book On The Shelf","same era"]],"https://openlibrary.org/works/OL450063W","s",null]]
```
Rules for the bot: not already shelved, not in blocklist.json, verified (Open Library author + year), cover eyeballed, `cluster_key` must exist in config.json `clusters` (use `wild` for wildcards).

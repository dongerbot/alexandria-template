# research_x: no script. The weekly scout does this.

How the scout should find new suggestions (instead of a research_x.py):
1. Search X (X search tools) for thoughtful readers on the user's themes: the user's own themes (read them off data/shelves.json and config.json clusters),
   e.g. philosophy, progress studies, founders. Look for "book rec", "reading list", "best books of <year>".
   Also check curated lists that match the user (publisher catalogs, well-known bookshelves).
2. Keep only books that are NOT in data/shelves.json, data/picks.json, or data/blocklist.json (match on title before ':'), and not in data/wantlist.json.
3. Verify each on Open Library (author + first-publish year) and get a cover (covers.openlibrary.org/b/id/<id>-L.jpg; eyeball it).
4. Append entries to picks.json in the existing format:
   [title, author, year, rating 1-10, cluster key, why, [[shelved book, relation label], ...], source URL, "s"|"w", cover URL]
   (10th element = cover URL or null; see data/README.md).
5. Run ./publish_map.sh (rebuilds, refreshes the worker's title list, republishes). Delete data/positions.json first if books were added, so the layout is recomputed.
State lives only in data/ (picks.json, blocklist.json, wantlist.json, shelves.json).

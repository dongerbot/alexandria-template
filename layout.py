#!/usr/bin/env python3
"""Precompute stable node positions: run the vis-network physics once in headless Chromium (needs: pip install playwright && playwright install chromium)."""
import json,subprocess,pathlib,os
os.chdir(os.path.dirname(os.path.abspath(__file__)))
from playwright.sync_api import sync_playwright
p=pathlib.Path("data/positions.json"); p.unlink(missing_ok=True)
subprocess.run(["python3","make_site.py"],check=True)
with sync_playwright() as pw:
  b=pw.chromium.launch();pg=b.new_page();pg.goto(pathlib.Path("dist/index.html").resolve().as_uri());pg.wait_for_function("window.MAP_READY",timeout=120000)
  pos=pg.evaluate("ALEX.net.getPositions()");b.close()
json.dump({k:[round(v["x"]),round(v["y"])] for k,v in pos.items()},open(p,"w"))
subprocess.run(["python3","make_site.py"],check=True); print("positions",len(pos))

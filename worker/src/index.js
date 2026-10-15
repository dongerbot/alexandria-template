const ORIGINS = env => String(env.ALLOWED_ORIGIN || "").split(",").map(s => s.trim()).filter(Boolean);
const TYPES = new Set(["thumbs_down", "thumbs_up", "undo", "reading", "note", "ping"]);
const LIMIT = 60; // events per hour, global
const corsFor = (env, req) => { const o = req.headers.get("Origin") || ""; const ok = ORIGINS(env); return { "Access-Control-Allow-Origin": ok.includes(o) ? o : (ok[0] || ""), "Access-Control-Allow-Methods": "POST, GET, OPTIONS", "Access-Control-Allow-Headers": "Content-Type", "Access-Control-Max-Age": "86400", "Vary": "Origin" }; };
const norm = s => String(s || "").toLowerCase().replace(/[’']/g, "'").trim();

export default {
  async fetch(req, env, ctx) {
    const cors = corsFor(env, req);
    const J = (o, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { "Content-Type": "application/json", ...cors } });
    const url = new URL(req.url);
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
    if (url.pathname === "/events" && req.method === "GET") {
      if (!env.READ_KEY || url.searchParams.get("key") !== env.READ_KEY) return J({ error: "unauthorized" }, 401);
      const out = []; let cursor;
      do { const l = await env.KV.list({ prefix: "ev:", cursor }); for (const k of l.keys) out.push(JSON.parse(await env.KV.get(k.name))); cursor = l.list_complete ? null : l.cursor; } while (cursor);
      return J({ tripped: await env.KV.get("tripped"), count: out.length, events: out });
    }
    if (url.pathname !== "/event" || req.method !== "POST") return J({ error: "not found" }, 404);
    let b; try { b = await req.json(); } catch { return J({ error: "bad json" }, 400); }
    const type = String(b.type || "");
    if (!TYPES.has(type)) return J({ error: "bad type" }, 400);
    let title = "", author = "", note = String(b.note || "").slice(0, 1000);
    if (type !== "ping") {
      const titles = JSON.parse((await env.KV.get("titles")) || "[]");
      const hit = titles.find(t => norm(t.title) === norm(b.title) || norm(t.short) === norm(b.title));
      if (!hit) return J({ error: "unknown title" }, 400);
      title = hit.title; author = hit.author;
    }
    const hour = new Date().toISOString().slice(0, 13), rk = "rate:" + hour;
    const n = parseInt((await env.KV.get(rk)) || "0") + 1;
    if (n > LIMIT) { ctx.waitUntil(env.KV.put("tripped", new Date().toISOString())); return J({ error: "rate limited" }, 429); }
    await env.KV.put(rk, String(n), { expirationTtl: 7200 });
    const ev = { type, title, author, note, ts: new Date().toISOString(), origin: req.headers.get("Origin") || "" };
    const id = "ev:" + ev.ts + ":" + crypto.randomUUID().slice(0, 8);
    await env.KV.put(id, JSON.stringify(ev));
    const fwd = fetch(env.WEBHOOK_URL, { method: "POST", headers: { "Content-Type": "application/json", Authorization: "Bearer " + env.WEBHOOK_KEY },
      body: JSON.stringify(type === "ping" ? { action: "ping" } : { action: type, title, author, note }) })
      .then(async r => env.KV.put(id, JSON.stringify({ ...ev, forwarded: r.status }))).catch(e => env.KV.put(id, JSON.stringify({ ...ev, forwarded: "error " + e })));
    ctx.waitUntil(fwd);
    return J({ ok: true, id });
  }
};

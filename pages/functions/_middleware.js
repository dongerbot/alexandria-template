// Password gate for the whole site (noindex, 1-year cookie). setup.sh sets the SITE_PASSWORD Pages secret.
const enc = new TextEncoder();
async function tok(pw) {
  const k = await crypto.subtle.importKey("raw", enc.encode(pw), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const s = await crypto.subtle.sign("HMAC", k, enc.encode("alexandria-session-v1"));
  return [...new Uint8Array(s)].map(b => b.toString(16).padStart(2, "0")).join("");
}
const page = (err, TITLE = "Alexandria") => new Response(`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>${TITLE}</title>
<style>body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#0f0f10;color:#eee;font-family:system-ui,sans-serif}
form{display:flex;flex-direction:column;gap:12px;width:280px}h1{font-weight:600;font-size:22px;margin:0 0 4px}
input,button{font:inherit;padding:12px;border-radius:10px;border:1px solid #333;background:#1a1a1c;color:#eee}button{background:#eee;color:#111;border:0;cursor:pointer}
.e{color:#f77;font-size:14px}</style></head><body><form method="POST"><h1>${TITLE}</h1>
<input type="password" name="password" placeholder="Password" autofocus autocomplete="current-password">
<button>Open map</button>${err ? '<div class="e">Wrong password</div>' : ""}</form></body></html>`,
  { status: err ? 401 : 200, headers: { "content-type": "text/html;charset=utf-8", "cache-control": "no-store", "x-robots-tag": "noindex" } });
export async function onRequest({ request, env, next }) {
  const pw = env.SITE_PASSWORD;
  if (!pw) return new Response("Not configured", { status: 503 });
  const good = await tok(pw);
  const c = request.headers.get("Cookie") || "";
  if (c.split(/;\s*/).includes("alex_auth=" + good)) {
    const r = await next(); const h = new Response(r.body, r); h.headers.set("x-robots-tag", "noindex"); return h;
  }
  if (request.method === "POST") {
    const f = await request.formData().catch(() => null);
    if (f && f.get("password") === pw) {
      const u = new URL(request.url);
      return new Response(null, { status: 303, headers: { Location: u.pathname + u.search,
        "Set-Cookie": `alex_auth=${good}; Max-Age=31536000; Path=/; HttpOnly; Secure; SameSite=Lax` } });
    }
    return page(true);
  }
  return page(false);
}

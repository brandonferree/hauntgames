// Cloudflare Pages advanced-mode Worker for the HRF fork.
//
// Serves the deployment's static files (index.html + the minified game JS) and
// falls back to https://hrf.im for anything missing (art, fonts) — the same
// local-first + /hrf-prefix logic as serve.js. Mirrored assets bundled into the
// deploy take precedence automatically.

const UPSTREAM = 'https://hrf.im';

// Try the path as-is, then with a /hrf prefix (covers /omen.png -> /hrf/omen.png,
// /fonts/x.woff2 -> /hrf/fonts/x.woff2). Absolute /hrf/* paths pass through unchanged.
function candidates(pathname) {
  const list = [pathname];
  if (!pathname.startsWith('/hrf/')) list.push('/hrf' + pathname);
  return list;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // 1) Static asset from the deployment (local-first).
    // Pages serves index.html (200) for unknown paths, so a 404 check isn't enough:
    // if it handed back HTML for a request that wanted a non-HTML file, that's the
    // SPA fallback, not a real asset -> treat as a miss and proxy.
    const assetRes = await env.ASSETS.fetch(request);
    const hasExt = /\.[a-z0-9]+$/i.test(url.pathname);
    const wantsHtml = !hasExt || url.pathname === '/' || url.pathname.endsWith('.html');
    const gotHtml = (assetRes.headers.get('content-type') || '').includes('text/html');
    if (assetRes.ok && !(gotHtml && !wantsHtml)) return assetRes;

    // 2) Fallback proxy to hrf.im.
    for (const p of candidates(url.pathname)) {
      const upstream = await fetch(UPSTREAM + p, { cf: { cacheTtl: 3600, cacheEverything: true } });
      if (upstream.ok) {
        const headers = new Headers(upstream.headers);
        headers.set('cache-control', 'public, max-age=3600');
        return new Response(upstream.body, { status: 200, headers });
      }
    }

    return new Response('Not found: ' + url.pathname, {
      status: 404,
      headers: { 'content-type': 'text/plain; charset=utf-8' },
    });
  },
};

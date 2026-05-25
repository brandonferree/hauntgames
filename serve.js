// Local-first dev server for the HRF fork.
//
// Serves files from ./haunt-roll-fail. For anything not found on disk it falls
// back to https://hrf.im (Option A). Local files always win, so you can mirror
// art into ./haunt-roll-fail/hrf/... later (Option B) with no change here.
//
// Each request path is tried as-is and again with a "/hrf" prefix, on both
// disk and upstream. That covers absolute game art ("/hrf/webp2/...") and the
// few CSS-relative root images ("omen.png" -> "/hrf/omen.png").
//
//   node serve.js            # http://localhost:8080
//   PORT=3000 node serve.js

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, 'haunt-roll-fail');
const UPSTREAM = 'https://hrf.im';
const PORT = process.env.PORT || 8080;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.webp': 'image/webp',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.mp3': 'audio/mpeg',
  '.ogg': 'audio/ogg',
  '.wav': 'audio/wav',
  '.txt': 'text/plain; charset=utf-8',
};

const mime = (p) => MIME[path.extname(p).toLowerCase()] || 'application/octet-stream';

// Try the path as given, then with a /hrf prefix.
function candidates(reqPath) {
  const list = [reqPath];
  if (!reqPath.startsWith('/hrf/')) list.push('/hrf' + reqPath);
  return list;
}

// Map a URL path to a file under ROOT, refusing traversal outside it.
function localFile(reqPath) {
  const rel = decodeURIComponent(reqPath).replace(/^\/+/, '');
  const abs = path.join(ROOT, rel);
  if (abs !== ROOT && !abs.startsWith(ROOT + path.sep)) return null;
  try {
    if (fs.statSync(abs).isFile()) return abs;
  } catch {}
  return null;
}

const remoteCache = new Map(); // path -> { buf, ct }

async function fetchRemote(reqPath) {
  if (remoteCache.has(reqPath)) return remoteCache.get(reqPath);
  try {
    const r = await fetch(UPSTREAM + reqPath);
    if (r.ok) {
      const hit = {
        buf: Buffer.from(await r.arrayBuffer()),
        ct: r.headers.get('content-type') || mime(reqPath),
      };
      remoteCache.set(reqPath, hit);
      return hit;
    }
  } catch {}
  return null;
}

const noStore = (p) => /\.(html|js|mjs|map)$/i.test(p);

const server = http.createServer(async (req, res) => {
  let reqPath = decodeURI(req.url.split('?')[0]);
  if (reqPath === '/' || reqPath === '') reqPath = '/index.html';

  const tried = candidates(reqPath);

  for (const p of tried) {
    const file = localFile(p);
    if (file) {
      const headers = { 'content-type': mime(file) };
      if (noStore(file)) headers['cache-control'] = 'no-store';
      res.writeHead(200, headers);
      fs.createReadStream(file).pipe(res);
      return;
    }
  }

  for (const p of tried) {
    const hit = await fetchRemote(p);
    if (hit) {
      res.writeHead(200, { 'content-type': hit.ct, 'cache-control': 'public, max-age=3600' });
      res.end(hit.buf);
      return;
    }
  }

  res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
  res.end('404 Not Found: ' + reqPath);
});

server.listen(PORT, () => {
  console.log(`HRF dev server -> http://localhost:${PORT}`);
  console.log(`  serving : ${ROOT}`);
  console.log(`  fallback: ${UPSTREAM} (missing assets, incl. /hrf/*)`);
});

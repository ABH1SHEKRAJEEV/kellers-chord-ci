/**
 * HTTP server for Xcode for Windows.
 *
 * Zero dependencies: uses `node:http` and `node:fs` only, matching the constraint
 * that this tool must install nothing and make no network calls. It binds to
 * loopback by default so the workspace is never exposed beyond this machine.
 */

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { Workspace } from './workspace.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC_DIR = path.join(__dirname, '..', 'public');

/** MIME types for the static UI. */
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.json': 'application/json; charset=utf-8',
  '.ico': 'image/x-icon'
};

/** Read a JSON request body with a size cap. */
function readBody(req, limit = 8 * 1024 * 1024) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (c) => {
      size += c.length;
      if (size > limit) {
        reject(Object.assign(new Error('Request body too large.'), { statusCode: 413 }));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

/** Send JSON with no caching. */
function sendJson(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store'
  });
  res.end(body);
}

/**
 * Start the server.
 *
 * @param {{root: string, port?: number, host?: string}} options
 */
export function createServer(options) {
  const workspace = new Workspace(options.root);

  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url ?? '/', 'http://localhost');
    const pathname = decodeURIComponent(url.pathname);

    try {
      // ── Static UI ────────────────────────────────────────────────────────
      if (req.method === 'GET' && !pathname.startsWith('/api/')) {
        const rel = pathname === '/' ? 'index.html' : pathname.replace(/^\/+/, '');
        const abs = path.join(PUBLIC_DIR, rel);
        const relative = path.relative(PUBLIC_DIR, abs);
        if (relative.startsWith('..') || path.isAbsolute(relative)) {
          sendJson(res, 403, { error: 'Forbidden.' });
          return;
        }
        if (!fs.existsSync(abs) || !fs.statSync(abs).isFile()) {
          sendJson(res, 404, { error: 'Not found.' });
          return;
        }
        const ext = path.extname(abs).toLowerCase();
        const body = fs.readFileSync(abs);
        res.writeHead(200, {
          'content-type': MIME[ext] ?? 'application/octet-stream',
          'content-length': body.length,
          'cache-control': 'no-store'
        });
        res.end(body);
        return;
      }

      // ── API ──────────────────────────────────────────────────────────────
      if (pathname === '/api/overview') {
        sendJson(res, 200, workspace.overview());
        return;
      }

      if (pathname === '/api/tree') {
        sendJson(res, 200, { root: workspace.root, tree: workspace.listTree() });
        return;
      }

      if (pathname === '/api/file' && req.method === 'PUT') {
        const target = url.searchParams.get('path');
        if (!target) { sendJson(res, 400, { error: 'Missing ?path=' }); return; }
        const body = await readBody(req);
        const parsed = JSON.parse(body || '{}');
        if (typeof parsed.content !== 'string') {
          sendJson(res, 400, { error: 'Body must be {"content": "<text>"}.' });
          return;
        }
        sendJson(res, 200, workspace.writeFile(target, parsed.content));
        return;
      }

      if (pathname === '/api/file') {
        const target = url.searchParams.get('path');
        if (!target) { sendJson(res, 400, { error: 'Missing ?path=' }); return; }
        const content = workspace.readFile(target);
        sendJson(res, 200, { path: target, content });
        return;
      }

      if (pathname === '/api/diagnostics') {
        sendJson(res, 200, workspace.diagnostics());
        return;
      }

      if (pathname === '/api/symbols') {
        const target = url.searchParams.get('path');
        if (!target) { sendJson(res, 400, { error: 'Missing ?path=' }); return; }
        sendJson(res, 200, workspace.symbols(target));
        return;
      }

      if (pathname === '/api/manifest') {
        sendJson(res, 200, workspace.manifest());
        return;
      }

      sendJson(res, 404, { error: `No route for ${req.method} ${pathname}` });
    } catch (err) {
      const status = err && typeof err === 'object' && 'statusCode' in err
        ? Number(err.statusCode)
        : 500;
      sendJson(res, status, { error: err instanceof Error ? err.message : String(err) });
    }
  });

  return { server, workspace };
}

/** CLI entry: `node src/server.mjs [--root <dir>] [--port <n>] [--open]` */
function main() {
  const argv = process.argv.slice(2);
  const flag = (name, fallback) => {
    const i = argv.indexOf(name);
    return i !== -1 && argv[i + 1] ? argv[i + 1] : fallback;
  };

  const root = path.resolve(flag('--root', process.cwd()));
  const port = Number(flag('--port', '0')) || 0;
  const host = flag('--host', '127.0.0.1');

  let built;
  try {
    built = createServer({ root, port, host });
  } catch (err) {
    console.error(`Cannot open workspace: ${err instanceof Error ? err.message : err}`);
    process.exit(1);
  }

  built.server.listen(port, host, () => {
    const addr = built.server.address();
    const actual = typeof addr === 'object' && addr ? addr.port : port;
    const url = `http://${host}:${actual}/`;
    console.log(`Xcode for Windows`);
    console.log(`  workspace: ${built.workspace.root}`);
    console.log(`  listening: ${url}`);
    console.log(`  press Ctrl+C to stop`);
  });

  const shutdown = () => {
    built.server.close(() => process.exit(0));
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

// Run the CLI only when this module is the process entry point. Comparing
// `import.meta.url` to `process.argv[1]` directly is unreliable on Windows
// because of path separators and URL encoding, so normalise both to POSIX form.
const isEntryPoint = (() => {
  if (!process.argv[1]) return false;
  const entry = pathToFileURL(path.resolve(process.argv[1])).href;
  return import.meta.url === entry;
})();

if (isEntryPoint) {
  main();
}

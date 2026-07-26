/**
 * Auth Relay Server
 *
 * Zero-dependency Node.js server that relays auth requests between the
 * Android Migo demo app and a WeChat proxy script.
 *
 * Flow:
 *   Android (HTTP POST /auth/request)
 *     -> relay holds connection
 *     -> WeChat proxy (HTTP GET /auth/pending, long-poll)
 *     -> proxy calls real wx.* API
 *     -> proxy posts result (HTTP POST /auth/response)
 *     -> relay responds to Android
 *
 * Usage:
 *   node relay-server.mjs [port]
 *
 * Default port: 9527
 */

import http from 'node:http';

const PORT = parseInt(process.argv[2], 10) || 9527;
const AUTH_REQUEST_TIMEOUT_MS = 30000;
const LONG_POLL_TIMEOUT_MS = 60000;

/**
 * Pending requests from Android, waiting for WeChat to process.
 * @type {Array<{id: string, action: string, params: object, gameId: string, androidRes: http.ServerResponse, timeout: NodeJS.Timeout, dispatched: boolean}>}
 */
let pendingRequests = [];

/**
 * WeChat proxy clients waiting for the next request (long-poll).
 * @type {Array<{res: http.ServerResponse, timeout: NodeJS.Timeout, gameId: string}>}
 */
let waitingClients = [];

/**
 * Check if two gameIds match.
 * Rules: if either side is empty/undefined, it matches anything (backwards compat).
 * Otherwise both must be equal.
 */
function gameIdMatches(a, b) {
  if (!a || !b) return true;
  return a === b;
}

let requestCounter = 0;

function generateId() {
  return `${Date.now()}_${++requestCounter}`;
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => {
      try {
        const raw = Buffer.concat(chunks).toString('utf-8').trim();
        if (!raw) {
          resolve({});
          return;
        }
        resolve(JSON.parse(raw));
      } catch (e) {
        reject(new Error('Invalid JSON body'));
      }
    });
    req.on('error', reject);
  });
}

function jsonResponse(res, statusCode, data) {
  const body = JSON.stringify(data);
  res.writeHead(statusCode, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  });
  res.end(body);
}

function log(msg) {
  const ts = new Date().toISOString().slice(11, 23);
  console.log(`[${ts}] ${msg}`);
}

// ── Route handlers ─────────────────────────────────────────────

/**
 * POST /auth/request — Android sends an auth request.
 * The response is held until the WeChat proxy processes it (or 30s timeout).
 */
async function handleAuthRequest(req, res) {
  const data = await readBody(req);
  const action = typeof data.action === 'string' ? data.action.trim() : '';
  if (!action) {
    jsonResponse(res, 400, { error: 'invalid action' });
    return;
  }

  const gameId = typeof data.gameId === 'string' ? data.gameId.trim() : '';
  const id = generateId();
  const tag = gameId ? `[${id}] <${gameId}> ${action}` : `[${id}] ${action}`;

  log(`<- Android  ${tag}`);

  const pending = {
    id,
    action,
    gameId,
    params: data.params || {},
    androidRes: res,
    dispatched: false,
    timeout: setTimeout(() => {
      pendingRequests = pendingRequests.filter((r) => r.id !== id);
      if (!res.writableEnded) {
        log(`!! Timeout  ${tag}`);
        jsonResponse(res, 504, {
          error: 'relay timeout: WeChat proxy did not respond within 30s',
        });
      }
    }, AUTH_REQUEST_TIMEOUT_MS),
  };

  req.on('close', () => {
    if (res.writableEnded) {
      return;
    }
    clearTimeout(pending.timeout);
    pendingRequests = pendingRequests.filter((r) => r.id !== id);
    log(`xx Android closed ${tag}`);
  });

  // If a matching WeChat client is already waiting, dispatch immediately
  const clientIdx = waitingClients.findIndex((c) => gameIdMatches(c.gameId, gameId));
  if (clientIdx !== -1) {
    const client = waitingClients.splice(clientIdx, 1)[0];
    clearTimeout(client.timeout);
    pending.dispatched = true;
    log(`-> WeChat   ${tag} (immediate)`);
    jsonResponse(client.res, 200, {
      id: pending.id,
      action: pending.action,
      params: pending.params,
    });
  }

  pendingRequests.push(pending);
}

/**
 * GET /auth/pending — WeChat proxy long-polls for the next request.
 * Returns immediately if a request is pending, otherwise holds up to 60s.
 *
 * Query params:
 *   ?gameId=xxx — only receive requests for this game (optional)
 */
function handleAuthPending(req, res) {
  // Parse gameId from query string: /auth/pending?gameId=xxx
  const qIdx = req.url.indexOf('?');
  const query = qIdx >= 0 ? new URLSearchParams(req.url.slice(qIdx + 1)) : null;
  const gameId = (query && query.get('gameId')) || '';

  // Find the first undispatched request matching this proxy's gameId
  const pending = pendingRequests.find((r) => !r.dispatched && gameIdMatches(r.gameId, gameId));

  if (pending) {
    pending.dispatched = true;
    const tag = pending.gameId ? `[${pending.id}] <${pending.gameId}>` : `[${pending.id}]`;
    log(`-> WeChat   ${tag} ${pending.action}`);
    jsonResponse(res, 200, {
      id: pending.id,
      action: pending.action,
      params: pending.params,
    });
    return;
  }

  // No pending request — long-poll
  const timeout = setTimeout(() => {
    waitingClients = waitingClients.filter((c) => c.res !== res);
    if (!res.writableEnded) {
      res.writeHead(204, {
        'Access-Control-Allow-Origin': '*',
      });
      res.end();
    }
  }, LONG_POLL_TIMEOUT_MS);

  res.on('close', () => {
    waitingClients = waitingClients.filter((c) => c.res !== res);
    clearTimeout(timeout);
  });

  waitingClients.push({ res, timeout, gameId });
}

/**
 * POST /auth/response — WeChat proxy posts the result of a processed request.
 */
async function handleAuthResponse(req, res) {
  const data = await readBody(req);
  const pending = pendingRequests.find((r) => r.id === data.id);

  if (pending) {
    clearTimeout(pending.timeout);
    pendingRequests = pendingRequests.filter((r) => r.id !== data.id);

    log(`<- WeChat   [${data.id}] result received`);

    if (pending.androidRes && !pending.androidRes.writableEnded) {
      log(`-> Android  [${data.id}] responding`);
      jsonResponse(pending.androidRes, 200, data.result);
    }
  } else {
    log(`?? WeChat   [${data.id}] no matching pending request`);
  }

  jsonResponse(res, 200, { ok: true });
}

/**
 * GET /status — Health check / debug info.
 */
function handleStatus(_req, res) {
  jsonResponse(res, 200, {
    pending: pendingRequests.map((r) => ({ id: r.id, action: r.action, gameId: r.gameId || null, dispatched: r.dispatched })),
    waitingProxies: waitingClients.map((c) => ({ gameId: c.gameId || null })),
    totalProcessed: requestCounter,
  });
}

// ── Server ─────────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    });
    res.end();
    return;
  }

  try {
    const pathname = req.url.split('?')[0];
    if (req.method === 'POST' && pathname === '/auth/request') {
      await handleAuthRequest(req, res);
    } else if (req.method === 'GET' && pathname === '/auth/pending') {
      handleAuthPending(req, res);
    } else if (req.method === 'POST' && pathname === '/auth/response') {
      await handleAuthResponse(req, res);
    } else if (req.method === 'GET' && pathname === '/status') {
      handleStatus(req, res);
    } else {
      jsonResponse(res, 404, { error: 'not found' });
    }
  } catch (e) {
    log(`!! Error: ${e.message}`);
    if (!res.writableEnded) {
      jsonResponse(res, 500, { error: e.message });
    }
  }
});

server.listen(PORT, '0.0.0.0', () => {
  log(`Auth relay server listening on http://0.0.0.0:${PORT}`);
  log('');
  log('Endpoints:');
  log(`  POST /auth/request   <- Android sends auth request`);
  log(`  GET  /auth/pending   <- WeChat proxy polls for work`);
  log(`  POST /auth/response  <- WeChat proxy posts result`);
  log(`  GET  /status         <- Health check`);
  log('');
  log('Waiting for connections...');
});

process.on('SIGINT', () => {
  log('Shutting down...');

  for (const pending of pendingRequests) {
    clearTimeout(pending.timeout);
    if (pending.androidRes && !pending.androidRes.writableEnded) {
      jsonResponse(pending.androidRes, 503, { error: 'relay server shutting down' });
    }
  }
  pendingRequests = [];

  for (const client of waitingClients) {
    clearTimeout(client.timeout);
    if (!client.res.writableEnded) {
      client.res.writeHead(503, { 'Access-Control-Allow-Origin': '*' });
      client.res.end();
    }
  }
  waitingClients = [];

  server.close(() => {
    process.exit(0);
  });
});

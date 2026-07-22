import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT || 3000);
const BOT_TOKEN = String(process.env.BOT_TOKEN || 'CHANGE-ME').trim();
const DASHBOARD_ORIGIN = String(process.env.DASHBOARD_ORIGIN || '*').trim();
const DATA_DIR = String(process.env.DATA_DIR || path.join(__dirname, '..', 'data')).trim();
const SUPABASE_URL = String(process.env.SUPABASE_URL || '').replace(/\/$/, '');
const SUPABASE_KEY = String(process.env.SUPABASE_SERVICE_ROLE_KEY || '').trim();
const EA_STALE_MS = 15_000;
const MAX_SCANS = 20_000;
const MAX_TRADES = 3_000;
const MAX_EVENTS = 2_000;

export const nowIso = () => new Date().toISOString();

function safeNumber(value, fallback = 0) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function safeInteger(value, fallback = 0) {
  return Math.trunc(safeNumber(value, fallback));
}

function clampArray(items, limit) {
  if (items.length > limit) items.splice(limit);
}

function loadJsonLines(filename, limit) {
  try {
    if (!fs.existsSync(filename)) return [];
    const lines = fs.readFileSync(filename, 'utf8').split(/\r?\n/).filter(Boolean);
    return lines.slice(-limit).map(line => JSON.parse(line)).reverse();
  } catch (error) {
    console.error(`Could not load ${filename}:`, error.message);
    return [];
  }
}

function appendJsonLine(filename, record) {
  try {
    fs.mkdirSync(path.dirname(filename), { recursive: true });
    fs.appendFileSync(filename, `${JSON.stringify(record)}\n`, 'utf8');
  } catch (error) {
    console.error(`Could not persist ${filename}:`, error.message);
  }
}

const files = {
  scans: path.join(DATA_DIR, 'scans.jsonl'),
  trades: path.join(DATA_DIR, 'trades.jsonl'),
  events: path.join(DATA_DIR, 'events.jsonl')
};

function dedupeById(items) {
  const seen = new Set();
  return items.filter(item => {
    const id = item?.id;
    if (!id || seen.has(id)) return false;
    seen.add(id);
    return true;
  });
}

const scans = loadJsonLines(files.scans, MAX_SCANS);
const trades = dedupeById(loadJsonLines(files.trades, MAX_TRADES));
const events = loadJsonLines(files.events, MAX_EVENTS);

const state = {
  version: '1.1.0',
  service: 'EVE MOMENTUM BURST',
  mode: 'FLIPPER-MODE LIVE BURST',
  startedAt: nowIso(),
  control: {
    autonomous: String(process.env.AUTO_ENABLED || 'true').toLowerCase() !== 'false',
    emergency: false,
    manualNewsLock: false
  },
  command: {
    id: 0,
    action: 'NONE',
    createdAt: nowIso(),
    consumedAt: null,
    result: null
  },
  ea: {
    online: false,
    lastSeenAt: null,
    account: null,
    symbol: null,
    version: null,
    balance: null,
    equity: null,
    margin: null,
    freeMargin: null,
    marginLevel: null,
    bid: null,
    ask: null,
    spreadPoints: null,
    medianSpreadPoints: null,
    terminalConnected: false,
    algoAllowed: false,
    autonomous: false,
    emergency: false,
    positionOpen: false,
    positionCount: 0,
    pendingCount: 0,
    side: 'NONE',
    totalLots: 0,
    averageEntry: null,
    currentPrice: null,
    protectedStop: null,
    floatingProfit: 0,
    peakBasketProfit: 0,
    basketMae: 0,
    basketTargetMoney: 0,
    basketTrailStartMoney: 0,
    basketGivebackMoney: 0,
    basketStartedAt: null,
    positionsOpened: 0,
    maxConcurrentPositions: 0,
    closePending: false,
    closeReason: null,
    closeAttempts: 0,
    lastCloseRetcode: 0,
    lastCloseResult: null,
    dailyPnl: 0,
    basketsToday: 0,
    consecutiveLosses: 0,
    momentumState: 'WARMING',
    liveDirection: 'NONE',
    buyScore: 0,
    sellScore: 0,
    velocity1s: 0,
    velocity3s: 0,
    velocity10s: 0,
    tickRateRatio: 0,
    acceleration: 0,
    bodyAtr: 0,
    extensionAtr: 0,
    lastEvent: 'Waiting for EA heartbeat',
    consumedCommandId: 0
  },
  latestScan: scans[0] || null,
  lastTrade: trades[0] || null
};

function addEvent(type, message, data = null) {
  const record = { id: `${Date.now()}-${Math.random().toString(16).slice(2)}`, at: nowIso(), type, message, data };
  events.unshift(record);
  clampArray(events, MAX_EVENTS);
  appendJsonLine(files.events, record);
  void supabaseInsert('eve_momentum_events', record);
  return record;
}

async function supabaseInsert(table, record) {
  if (!SUPABASE_URL || !SUPABASE_KEY) return;
  try {
    const response = await fetch(`${SUPABASE_URL}/rest/v1/${table}?on_conflict=id`, {
      method: 'POST',
      headers: {
        apikey: SUPABASE_KEY,
        Authorization: `Bearer ${SUPABASE_KEY}`,
        'Content-Type': 'application/json',
        Prefer: 'resolution=merge-duplicates,return=minimal'
      },
      body: JSON.stringify(record)
    });
    if (!response.ok) console.error(`Supabase ${table} insert failed:`, response.status, await response.text());
  } catch (error) {
    console.error(`Supabase ${table} insert failed:`, error.message);
  }
}

function refreshEaOnline() {
  state.ea.online = Boolean(state.ea.lastSeenAt && Date.now() - Date.parse(state.ea.lastSeenAt) < EA_STALE_MS);
  return state.ea.online;
}

function commandPending() {
  return state.command.action !== 'NONE' && !state.command.consumedAt;
}

function queueCommand(action, source = 'dashboard') {
  state.command = {
    id: Math.max(Date.now(), Number(state.command.id || 0) + 1),
    action,
    source,
    createdAt: nowIso(),
    consumedAt: null,
    result: null
  };
  addEvent('command', `${action} queued`, { id: state.command.id, source });
  return state.command;
}

export function calculateStats(inputTrades) {
  const completed = inputTrades.filter(item => item && item.status !== 'OPEN');
  const pnls = completed.map(item => safeNumber(item.netProfit));
  const wins = pnls.filter(value => value > 0);
  const losses = pnls.filter(value => value < 0);
  const grossProfit = wins.reduce((sum, value) => sum + value, 0);
  const grossLossAbs = Math.abs(losses.reduce((sum, value) => sum + value, 0));
  const netProfit = pnls.reduce((sum, value) => sum + value, 0);
  const average = pnls.length ? netProfit / pnls.length : 0;
  const avgWinner = wins.length ? grossProfit / wins.length : 0;
  const avgLoser = losses.length ? losses.reduce((sum, value) => sum + value, 0) / losses.length : 0;
  const profitFactor = grossLossAbs > 0 ? grossProfit / grossLossAbs : grossProfit > 0 ? 999 : 0;
  const totalLegs = completed.reduce((sum, item) => sum + safeInteger(item.positionsOpened, 1), 0);
  const totalDuration = completed.reduce((sum, item) => sum + safeInteger(item.durationSeconds), 0);

  const bySide = ['BUY', 'SELL'].map(side => {
    const subset = completed.filter(item => item.side === side);
    const sideNet = subset.reduce((sum, item) => sum + safeNumber(item.netProfit), 0);
    const sideWins = subset.filter(item => safeNumber(item.netProfit) > 0).length;
    return { side, baskets: subset.length, wins: sideWins, winRate: subset.length ? sideWins / subset.length * 100 : 0, netProfit: sideNet };
  });

  const scoreBands = [
    { label: '0-5', min: 0, max: 5 },
    { label: '6-7', min: 6, max: 7 },
    { label: '8-9', min: 8, max: 9 },
    { label: '10-11', min: 10, max: 11 }
  ].map(band => {
    const subset = completed.filter(item => safeNumber(item.entryScore, -1) >= band.min && safeNumber(item.entryScore, -1) <= band.max);
    const bandNet = subset.reduce((sum, item) => sum + safeNumber(item.netProfit), 0);
    const bandWins = subset.filter(item => safeNumber(item.netProfit) > 0).length;
    return { ...band, baskets: subset.length, winRate: subset.length ? bandWins / subset.length * 100 : 0, netProfit: bandNet };
  });

  return {
    trades: completed.length,
    baskets: completed.length,
    totalLegs,
    averageLegs: completed.length ? totalLegs / completed.length : 0,
    averageDurationSeconds: completed.length ? totalDuration / completed.length : 0,
    wins: wins.length,
    losses: losses.length,
    winRate: completed.length ? wins.length / completed.length * 100 : 0,
    netProfit,
    grossProfit,
    grossLoss: -grossLossAbs,
    profitFactor,
    average,
    avgWinner,
    avgLoser,
    bestTrade: pnls.length ? Math.max(...pnls) : 0,
    worstTrade: pnls.length ? Math.min(...pnls) : 0,
    bySide,
    scoreBands
  };
}

export function csvEscape(value) {
  const text = value === null || value === undefined ? '' : String(value);
  return /[",\n\r]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

function csvData(rows) {
  if (!rows.length) return 'No data\n';
  const headers = [...new Set(rows.flatMap(row => Object.keys(row)))];
  return [headers.join(','), ...rows.map(row => headers.map(key => csvEscape(typeof row[key] === 'object' ? JSON.stringify(row[key]) : row[key])).join(','))].join('\n');
}

function corsOrigin(request) {
  if (DASHBOARD_ORIGIN === '*') return '*';
  const allowed = DASHBOARD_ORIGIN.split(',').map(value => value.trim());
  const incoming = request.headers.origin || '';
  return allowed.includes(incoming) ? incoming : allowed[0] || '*';
}

function standardHeaders(request, contentType) {
  return {
    'Content-Type': contentType,
    'Access-Control-Allow-Origin': corsOrigin(request),
    'Access-Control-Allow-Headers': 'Content-Type, X-Bot-Token',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Cache-Control': 'no-store'
  };
}

function sendJson(request, response, status, payload) {
  response.writeHead(status, standardHeaders(request, 'application/json; charset=utf-8'));
  response.end(JSON.stringify(payload));
}

function sendText(request, response, status, text, contentType = 'text/plain; charset=utf-8', extraHeaders = {}) {
  response.writeHead(status, { ...standardHeaders(request, contentType), ...extraHeaders });
  response.end(text);
}

async function readJson(request) {
  const chunks = [];
  let total = 0;
  for await (const chunk of request) {
    total += chunk.length;
    if (total > 1_000_000) throw new Error('Request body too large');
    chunks.push(chunk);
  }
  if (!chunks.length) return {};
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

function tokenFrom(request, url, body = {}) {
  return String(request.headers['x-bot-token'] || url.searchParams.get('token') || body.token || '').trim();
}

function authorised(request, url, body) {
  if (!BOT_TOKEN || BOT_TOKEN === 'CHANGE-ME') return { ok: false, status: 503, error: 'BOT_TOKEN has not been configured in Railway Variables' };
  if (tokenFrom(request, url, body) !== BOT_TOKEN) return { ok: false, status: 401, error: 'Unauthorised: BOT_TOKEN does not match' };
  return { ok: true };
}

function serveStatic(request, response, pathname) {
  const map = {
    '/': ['index.html', 'text/html; charset=utf-8'],
    '/index.html': ['index.html', 'text/html; charset=utf-8'],
    '/app.js': ['app.js', 'text/javascript; charset=utf-8'],
    '/styles.css': ['styles.css', 'text/css; charset=utf-8']
  };
  if (!map[pathname]) return false;
  const [filename, type] = map[pathname];
  const file = path.join(__dirname, '..', 'public', filename);
  sendText(request, response, 200, fs.readFileSync(file), type, { 'Cache-Control': 'public, max-age=30' });
  return true;
}

export function createHttpServer() {
  return http.createServer(async (request, response) => {
    try {
      const url = new URL(request.url, `http://${request.headers.host || 'localhost'}`);
      const pathname = url.pathname;
      if (request.method === 'OPTIONS') return sendText(request, response, 204, '');
      if (request.method === 'GET' && serveStatic(request, response, pathname)) return;

      if (request.method === 'GET' && pathname === '/health') {
        refreshEaOnline();
        return sendJson(request, response, 200, {
          ok: true,
          service: state.service,
          version: state.version,
          mode: state.mode,
          railway: 'ONLINE',
          eaOnline: state.ea.online,
          autonomous: state.control.autonomous,
          now: nowIso(),
          persistentDataDir: DATA_DIR,
          supabaseEnabled: Boolean(SUPABASE_URL && SUPABASE_KEY)
        });
      }

      let body = {};
      if (request.method === 'POST') body = await readJson(request);
      const auth = authorised(request, url, body);
      if (!auth.ok) return sendJson(request, response, auth.status, { ok: false, error: auth.error });

      if (request.method === 'GET' && pathname === '/api/state') {
        refreshEaOnline();
        return sendJson(request, response, 200, {
          ok: true,
          state,
          performance: calculateStats(trades),
          recentScans: scans.slice(0, 120),
          recentTrades: trades.slice(0, 100),
          recentEvents: events.slice(0, 100)
        });
      }

      if (request.method === 'GET' && pathname === '/api/ea/control') {
        refreshEaOnline();
        const command = commandPending() ? state.command : { id: 0, action: 'NONE' };
        return sendText(request, response, 200, [
          `command_id=${command.id || 0}`,
          `action=${command.action || 'NONE'}`,
          `autonomous=${state.control.autonomous ? 'true' : 'false'}`,
          `emergency=${state.control.emergency ? 'true' : 'false'}`,
          `manual_news_lock=${state.control.manualNewsLock ? 'true' : 'false'}`
        ].join('\n'));
      }

      if (request.method === 'POST' && pathname === '/api/ea/heartbeat') {
        state.ea = { ...state.ea, ...body, online: true, lastSeenAt: nowIso() };
        for (const key of ['balance', 'equity', 'floatingProfit', 'peakBasketProfit', 'basketMae', 'totalLots', 'dailyPnl']) {
          state.ea[key] = safeNumber(state.ea[key], key === 'balance' || key === 'equity' ? null : 0);
        }
        const consumed = safeNumber(state.ea.consumedCommandId);
        if (commandPending() && consumed >= state.command.id) {
          state.command.consumedAt = nowIso();
          state.command.result = state.ea.lastCommandResult || state.ea.lastEvent || 'Consumed by EA';
          addEvent('command', `${state.command.action} consumed by EA`, { id: state.command.id, result: state.command.result });
        }
        return sendJson(request, response, 200, { ok: true, receivedAt: state.ea.lastSeenAt });
      }

      if (request.method === 'POST' && pathname === '/api/ea/scan') {
        const record = { id: body.id || `${Date.now()}-${Math.random().toString(16).slice(2)}`, receivedAt: nowIso(), ...body };
        scans.unshift(record);
        clampArray(scans, MAX_SCANS);
        state.latestScan = record;
        appendJsonLine(files.scans, record);
        void supabaseInsert('eve_momentum_scans', record);
        return sendJson(request, response, 200, { ok: true, id: record.id });
      }

      if (request.method === 'POST' && pathname === '/api/ea/trade') {
        const record = { id: body.id || `${Date.now()}-${Math.random().toString(16).slice(2)}`, receivedAt: nowIso(), ...body };
        const existingIndex = trades.findIndex(item => item.id === record.id);
        if (existingIndex >= 0) trades.splice(existingIndex, 1);
        trades.unshift(record);
        clampArray(trades, MAX_TRADES);
        state.lastTrade = record;
        appendJsonLine(files.trades, record);
        void supabaseInsert('eve_momentum_trades', record);
        addEvent('trade', `${record.side || 'BASKET'} basket closed ${safeNumber(record.netProfit).toFixed(2)}`, {
          positionsOpened: record.positionsOpened,
          exitReason: record.exitReason,
          netProfit: record.netProfit
        });
        return sendJson(request, response, 200, { ok: true, id: record.id, performance: calculateStats(trades) });
      }

      if (request.method === 'POST' && pathname === '/api/ea/event') {
        const record = addEvent(body.type || 'ea', body.message || 'EA event', body.data || null);
        return sendJson(request, response, 200, { ok: true, id: record.id });
      }

      if (request.method === 'POST' && pathname === '/api/command') {
        const action = String(body.action || '').toUpperCase();
        if (action === 'ENABLE_AUTO') {
          state.control.autonomous = true;
          state.control.emergency = false;
          addEvent('control', 'Autonomous mode enabled');
          return sendJson(request, response, 200, { ok: true, autonomous: true });
        }
        if (action === 'DISABLE_AUTO') {
          state.control.autonomous = false;
          addEvent('control', 'Autonomous mode disabled');
          return sendJson(request, response, 200, { ok: true, autonomous: false });
        }
        if (action === 'NEWS_LOCK_ON') {
          state.control.manualNewsLock = true;
          addEvent('control', 'Manual news lock enabled');
          return sendJson(request, response, 200, { ok: true, manualNewsLock: true });
        }
        if (action === 'NEWS_LOCK_OFF') {
          state.control.manualNewsLock = false;
          addEvent('control', 'Manual news lock disabled');
          return sendJson(request, response, 200, { ok: true, manualNewsLock: false });
        }
        if (action === 'EMERGENCY_STOP') {
          state.control.autonomous = false;
          state.control.emergency = true;
          return sendJson(request, response, 200, { ok: true, command: queueCommand(action) });
        }
        if (action === 'RESET_EMERGENCY') {
          state.control.emergency = false;
          return sendJson(request, response, 200, { ok: true, command: queueCommand(action) });
        }
        const supported = new Set(['CLOSE_BASKET', 'CLOSE_POSITION', 'PAUSE_EA', 'RESUME_EA', 'PAUSE_ADDING', 'RESUME_ADDING']);
        if (!supported.has(action)) return sendJson(request, response, 400, { ok: false, error: 'Unsupported command' });
        return sendJson(request, response, 200, { ok: true, command: queueCommand(action) });
      }

      if (request.method === 'GET' && pathname === '/api/export/scans.csv') {
        return sendText(request, response, 200, csvData(scans.slice().reverse()), 'text/csv; charset=utf-8', { 'Content-Disposition': 'attachment; filename="eve-momentum-live-scans.csv"' });
      }
      if (request.method === 'GET' && pathname === '/api/export/trades.csv') {
        return sendText(request, response, 200, csvData(trades.slice().reverse()), 'text/csv; charset=utf-8', { 'Content-Disposition': 'attachment; filename="eve-momentum-baskets.csv"' });
      }
      if (request.method === 'GET' && pathname === '/api/export/events.csv') {
        return sendText(request, response, 200, csvData(events.slice().reverse()), 'text/csv; charset=utf-8', { 'Content-Disposition': 'attachment; filename="eve-momentum-events.csv"' });
      }

      return sendJson(request, response, 404, { ok: false, error: 'Not found' });
    } catch (error) {
      console.error(error);
      return sendJson(request, response, 500, { ok: false, error: error.message || 'Internal server error' });
    }
  });
}

if (process.env.NODE_ENV !== 'test') {
  const server = createHttpServer();
  server.listen(PORT, () => {
    console.log(`${state.service} v${state.version} ${state.mode} listening on port ${PORT}`);
    addEvent('system', `Railway service started v${state.version} - ${state.mode}`);
  });
}

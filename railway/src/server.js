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
const EA_DELAYED_MS = 20_000;
const EA_OFFLINE_MS = 60_000;
const MAX = { scans: 40_000, baskets: 5_000, legs: 30_000, orders: 30_000, banks: 10_000, events: 5_000 };

export const nowIso = () => new Date().toISOString();
const safeNumber = (value, fallback = 0) => Number.isFinite(Number(value)) ? Number(value) : fallback;
const safeInteger = (value, fallback = 0) => Math.trunc(safeNumber(value, fallback));
const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

function clampArray(items, limit) { if (items.length > limit) items.splice(limit); }
function appendJsonLine(filename, record) {
  try {
    fs.mkdirSync(path.dirname(filename), { recursive: true });
    fs.appendFileSync(filename, `${JSON.stringify(record)}\n`, 'utf8');
  } catch (error) { console.error(`Persist failed ${filename}:`, error.message); }
}
function loadJsonLines(filename, limit) {
  try {
    if (!fs.existsSync(filename)) return [];
    return fs.readFileSync(filename, 'utf8').split(/\r?\n/).filter(Boolean).slice(-limit).map(line => JSON.parse(line)).reverse();
  } catch (error) { console.error(`Load failed ${filename}:`, error.message); return []; }
}
function loadJson(filename, fallback) {
  try { return fs.existsSync(filename) ? JSON.parse(fs.readFileSync(filename, 'utf8')) : fallback; }
  catch { return fallback; }
}
function saveJson(filename, value) {
  fs.mkdirSync(path.dirname(filename), { recursive: true });
  fs.writeFileSync(filename, JSON.stringify(value, null, 2), 'utf8');
}
function dedupe(items) {
  const seen = new Set();
  return items.filter(item => item?.id && !seen.has(item.id) && seen.add(item.id));
}

const files = {
  scans: path.join(DATA_DIR, 'scans.jsonl'), baskets: path.join(DATA_DIR, 'baskets.jsonl'),
  legs: path.join(DATA_DIR, 'legs.jsonl'), orders: path.join(DATA_DIR, 'orders.jsonl'),
  banks: path.join(DATA_DIR, 'bank-decisions.jsonl'), events: path.join(DATA_DIR, 'events.jsonl'),
  settings: path.join(DATA_DIR, 'settings.json'), legacyTrades: path.join(DATA_DIR, 'trades.jsonl')
};
const scans = loadJsonLines(files.scans, MAX.scans);
const baskets = dedupe([...loadJsonLines(files.baskets, MAX.baskets), ...loadJsonLines(files.legacyTrades, MAX.baskets)]);
const legs = loadJsonLines(files.legs, MAX.legs);
const orders = loadJsonLines(files.orders, MAX.orders);
const banks = loadJsonLines(files.banks, MAX.banks);
const events = loadJsonLines(files.events, MAX.events);

export const DEFAULT_SETTINGS = Object.freeze({
  version: 1,
  testingMode: true,
  fixedLot: 0.01,
  useEquityScaling: false,
  equityPer001Lot: 1000,
  initialPositions: 1,
  maxPositions: 20,
  maxTotalLots: 0.20
});

export function validateSettings(input = {}, current = DEFAULT_SETTINGS) {
  const currentTestingMode = current.testingMode === undefined ? true : Boolean(current.testingMode);
  const next = {
    version: safeInteger(current.version, 1),
    testingMode: input.testingMode === undefined ? currentTestingMode : Boolean(input.testingMode),
    fixedLot: clamp(safeNumber(input.fixedLot, current.fixedLot), 0.01, 100),
    useEquityScaling: input.useEquityScaling === undefined ? Boolean(current.useEquityScaling) : Boolean(input.useEquityScaling),
    equityPer001Lot: clamp(safeNumber(input.equityPer001Lot, current.equityPer001Lot), 10, 10_000_000),
    initialPositions: clamp(safeInteger(input.initialPositions, current.initialPositions), 1, 20),
    maxPositions: clamp(safeInteger(input.maxPositions, current.maxPositions), 1, 100),
    maxTotalLots: clamp(safeNumber(input.maxTotalLots, current.maxTotalLots), 0.01, 100)
  };
  if (next.initialPositions > next.maxPositions) next.initialPositions = next.maxPositions;
  if (next.maxTotalLots < next.fixedLot) next.maxTotalLots = next.fixedLot;
  return next;
}
let settings = validateSettings(loadJson(files.settings, DEFAULT_SETTINGS));

const state = {
  version: '2.0.3', service: 'EVE MOMENTUM BURST', mode: 'DEMO TEST MODE + TRANSACTION-SAFE STRADDLE/LADDER', startedAt: nowIso(),
  control: { autonomous: String(process.env.AUTO_ENABLED || 'true').toLowerCase() !== 'false', emergency: false, manualNewsLock: false },
  command: { id: 0, action: 'NONE', createdAt: nowIso(), consumedAt: null, result: null },
  ea: {
    online: false, connectionStatus: 'OFFLINE', lastSeenAt: null, account: null, symbol: null, version: null,
    balance: null, equity: null, margin: null, freeMargin: null, marginLevel: null,
    bid: null, ask: null, spreadPoints: null, medianSpreadPoints: null,
    terminalConnected: false, algoAllowed: false, autonomous: false, emergency: false,
    engineState: 'WARMING', bracketState: 'NONE', bracketBuyPrice: 0, bracketSellPrice: 0,
    positionOpen: false, positionCount: 0, pendingCount: 0, side: 'NONE', totalLots: 0,
    averageEntry: null, currentPrice: null, protectedStop: null, floatingProfit: 0, peakBasketProfit: 0, basketMae: 0,
    basketStartedAt: null, positionsOpened: 0, maxConcurrentPositions: 0,
    newestTicket: 0, newestLegProfit: 0, newestLegPeak: 0, newestLegAgeSeconds: 0,
    bankCandidate: false, bankReason: '', closePending: false, closeReason: null, closeAttempts: 0,
    dailyPnl: 0, basketsToday: 0, consecutiveLosses: 0,
    momentumState: 'WARMING', liveDirection: 'NONE', buyScore: 0, sellScore: 0,
    velocity1s: 0, velocity3s: 0, velocity10s: 0, tickRateRatio: 0, acceleration: 0, bodyAtr: 0, extensionAtr: 0,
    settingsVersion: 0, lastEvent: 'Waiting for EA heartbeat', consumedCommandId: 0
  },
  latestScan: scans[0] || null, lastBasket: baskets[0] || null
};

async function supabaseInsert(table, record) {
  if (!SUPABASE_URL || !SUPABASE_KEY) return;
  try {
    const response = await fetch(`${SUPABASE_URL}/rest/v1/${table}?on_conflict=id`, {
      method: 'POST', headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}`, 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify({ id: record.id, captured_at: record.receivedAt || record.at || nowIso(), payload: record })
    });
    if (!response.ok) console.error(`Supabase ${table}:`, response.status, await response.text());
  } catch (error) { console.error(`Supabase ${table}:`, error.message); }
}
function addEvent(type, message, data = null) {
  const record = { id: `${Date.now()}-${Math.random().toString(16).slice(2)}`, at: nowIso(), type, message, data };
  events.unshift(record); clampArray(events, MAX.events); appendJsonLine(files.events, record); void supabaseInsert('eve_momentum_events', record); return record;
}
function addRecord(collection, file, limit, table, body) {
  const record = { id: body.id || `${Date.now()}-${Math.random().toString(16).slice(2)}`, receivedAt: nowIso(), ...body };
  collection.unshift(record); clampArray(collection, limit); appendJsonLine(file, record); void supabaseInsert(table, record); return record;
}
function upsertBasket(body) {
  const record = { id: body.id || `${Date.now()}-${Math.random().toString(16).slice(2)}`, receivedAt: nowIso(), ...body };
  const index = baskets.findIndex(item => item.id === record.id); if (index >= 0) baskets.splice(index, 1);
  baskets.unshift(record); clampArray(baskets, MAX.baskets); appendJsonLine(files.baskets, record); void supabaseInsert('eve_momentum_baskets', record); state.lastBasket = record; return record;
}
function refreshEaConnection() {
  const age = state.ea.lastSeenAt ? Date.now() - Date.parse(state.ea.lastSeenAt) : Infinity;
  state.ea.connectionStatus = age < EA_DELAYED_MS ? 'CONNECTED' : age < EA_OFFLINE_MS ? 'DELAYED' : 'OFFLINE';
  state.ea.online = state.ea.connectionStatus !== 'OFFLINE'; return state.ea.connectionStatus;
}
function queueCommand(action, source = 'dashboard') {
  state.command = { id: Math.max(Date.now(), Number(state.command.id || 0) + 1), action, source, createdAt: nowIso(), consumedAt: null, result: null };
  addEvent('command', `${action} queued`, { id: state.command.id, source }); return state.command;
}
function commandPending() { return state.command.action !== 'NONE' && !state.command.consumedAt; }

function groupStats(completed, selector) {
  const map = new Map();
  for (const basket of completed) {
    const key = String(selector(basket) ?? 'UNKNOWN');
    const row = map.get(key) || { key, baskets: 0, wins: 0, netProfit: 0, grossProfit: 0, grossLoss: 0 };
    const pnl = safeNumber(basket.netProfit); row.baskets++; row.netProfit += pnl;
    if (pnl > 0) { row.wins++; row.grossProfit += pnl; } else if (pnl < 0) row.grossLoss += pnl;
    map.set(key, row);
  }
  return [...map.values()].map(row => ({ ...row, winRate: row.baskets ? row.wins / row.baskets * 100 : 0, profitFactor: row.grossLoss < 0 ? row.grossProfit / Math.abs(row.grossLoss) : row.grossProfit > 0 ? 999 : 0 })).sort((a, b) => b.baskets - a.baskets);
}

export function calculatePerformance(inputBaskets) {
  const completed = inputBaskets.filter(item => item && item.status !== 'OPEN');
  const pnls = completed.map(item => safeNumber(item.netProfit));
  const wins = pnls.filter(value => value > 0), losses = pnls.filter(value => value < 0);
  const grossProfit = wins.reduce((a, b) => a + b, 0), grossLossAbs = Math.abs(losses.reduce((a, b) => a + b, 0));
  const netProfit = pnls.reduce((a, b) => a + b, 0), totalLegs = completed.reduce((sum, item) => sum + safeInteger(item.positionsOpened, 0), 0);
  const totalDuration = completed.reduce((sum, item) => sum + safeInteger(item.durationSeconds), 0);
  const totalGiveback = completed.reduce((sum, item) => sum + Math.max(0, safeNumber(item.profitGiveback, safeNumber(item.peakBasketProfit) - safeNumber(item.netProfit))), 0);
  const totalMae = completed.reduce((sum, item) => sum + Math.abs(Math.min(0, safeNumber(item.mae))), 0);
  return {
    summary: {
      baskets: completed.length, totalLegs, averageLegs: completed.length ? totalLegs / completed.length : 0,
      wins: wins.length, losses: losses.length, winRate: completed.length ? wins.length / completed.length * 100 : 0,
      netProfit, grossProfit, grossLoss: -grossLossAbs, profitFactor: grossLossAbs ? grossProfit / grossLossAbs : grossProfit > 0 ? 999 : 0,
      averageBasket: completed.length ? netProfit / completed.length : 0,
      averageDurationSeconds: completed.length ? totalDuration / completed.length : 0,
      bestBasket: pnls.length ? Math.max(...pnls) : 0, worstBasket: pnls.length ? Math.min(...pnls) : 0,
      averageGiveback: completed.length ? totalGiveback / completed.length : 0,
      averageMaxDrawdown: completed.length ? totalMae / completed.length : 0,
      peakFloatingProfit: completed.reduce((max, item) => Math.max(max, safeNumber(item.peakBasketProfit)), 0),
      reversalSuccessRate: (() => { const r = completed.filter(item => item.reversalTriggered); return r.length ? r.filter(item => safeNumber(item.netProfit) > 0).length / r.length * 100 : 0; })()
    },
    bySide: groupStats(completed, item => item.side),
    byRegime: groupStats(completed, item => item.entryRegime),
    byBankReason: groupStats(completed, item => item.exitReason),
    byHour: groupStats(completed, item => { const d = new Date(safeNumber(item.entryTime)); return Number.isNaN(d.getTime()) ? 'UNKNOWN' : String(d.getUTCHours()).padStart(2, '0') + ':00 UTC'; }),
    byLot: groupStats(completed, item => Number(safeNumber(item.lotPerLeg)).toFixed(2)),
    byLegCount: groupStats(completed, item => { const n = safeInteger(item.positionsOpened); return n <= 3 ? '1-3' : n <= 7 ? '4-7' : n <= 12 ? '8-12' : '13+'; })
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
  const allowed = DASHBOARD_ORIGIN.split(',').map(v => v.trim()), incoming = request.headers.origin || '';
  return allowed.includes(incoming) ? incoming : allowed[0] || '*';
}
function headers(request, contentType) { return { 'Content-Type': contentType, 'Access-Control-Allow-Origin': corsOrigin(request), 'Access-Control-Allow-Headers': 'Content-Type, X-Bot-Token', 'Access-Control-Allow-Methods': 'GET, POST, OPTIONS', 'Cache-Control': 'no-store' }; }
function sendJson(request, response, status, payload) { response.writeHead(status, headers(request, 'application/json; charset=utf-8')); response.end(JSON.stringify(payload)); }
function sendText(request, response, status, text, contentType = 'text/plain; charset=utf-8', extra = {}) { response.writeHead(status, { ...headers(request, contentType), ...extra }); response.end(text); }
async function readJson(request) {
  const chunks = []; let total = 0;
  for await (const chunk of request) { total += chunk.length; if (total > 1_500_000) throw new Error('Request body too large'); chunks.push(chunk); }
  return chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {};
}
function tokenFrom(request, url, body = {}) { return String(request.headers['x-bot-token'] || url.searchParams.get('token') || body.token || '').trim(); }
function authorised(request, url, body) {
  if (!BOT_TOKEN || BOT_TOKEN === 'CHANGE-ME') return { ok: false, status: 503, error: 'BOT_TOKEN has not been configured in Railway Variables' };
  if (tokenFrom(request, url, body) !== BOT_TOKEN) return { ok: false, status: 401, error: 'Unauthorised: BOT_TOKEN does not match' };
  return { ok: true };
}
function serveStatic(request, response, pathname) {
  const map = { '/': ['index.html', 'text/html; charset=utf-8'], '/index.html': ['index.html', 'text/html; charset=utf-8'], '/app.js': ['app.js', 'text/javascript; charset=utf-8'], '/styles.css': ['styles.css', 'text/css; charset=utf-8'] };
  if (!map[pathname]) return false;
  const [filename, type] = map[pathname]; sendText(request, response, 200, fs.readFileSync(path.join(__dirname, '..', 'public', filename)), type, { 'Cache-Control': 'public, max-age=30' }); return true;
}

export function createHttpServer() {
  return http.createServer(async (request, response) => {
    try {
      const url = new URL(request.url, `http://${request.headers.host || 'localhost'}`), pathname = url.pathname;
      if (request.method === 'OPTIONS') return sendText(request, response, 204, '');
      if (request.method === 'GET' && serveStatic(request, response, pathname)) return;
      if (request.method === 'GET' && pathname === '/health') {
        refreshEaConnection(); return sendJson(request, response, 200, { ok: true, service: state.service, version: state.version, mode: state.mode, railway: 'ONLINE', eaStatus: state.ea.connectionStatus, autonomous: state.control.autonomous, now: nowIso(), supabaseEnabled: Boolean(SUPABASE_URL && SUPABASE_KEY) });
      }
      let body = {}; if (request.method === 'POST') body = await readJson(request);
      const auth = authorised(request, url, body); if (!auth.ok) return sendJson(request, response, auth.status, { ok: false, error: auth.error });

      if (request.method === 'GET' && pathname === '/api/state') {
        refreshEaConnection(); return sendJson(request, response, 200, { ok: true, state, settings, performance: calculatePerformance(baskets), recentScans: scans.slice(0, 150), recentBaskets: baskets.slice(0, 150), recentLegs: legs.slice(0, 250), recentOrders: orders.slice(0, 250), recentBanks: banks.slice(0, 150), recentEvents: events.slice(0, 150) });
      }
      if (request.method === 'GET' && pathname === '/api/settings') return sendJson(request, response, 200, { ok: true, settings });
      if (request.method === 'POST' && pathname === '/api/settings') {
        const validated = validateSettings(body, settings); settings = { ...validated, version: safeInteger(settings.version, 1) + 1, updatedAt: nowIso() }; saveJson(files.settings, settings);
        addEvent('settings', 'Trading settings updated', settings); return sendJson(request, response, 200, { ok: true, settings });
      }
      if (request.method === 'GET' && pathname === '/api/ea/control') {
        refreshEaConnection(); const command = commandPending() ? state.command : { id: 0, action: 'NONE' };
        return sendText(request, response, 200, [
          `command_id=${command.id || 0}`, `action=${command.action || 'NONE'}`, `autonomous=${state.control.autonomous ? 'true' : 'false'}`,
          `emergency=${state.control.emergency ? 'true' : 'false'}`, `manual_news_lock=${state.control.manualNewsLock ? 'true' : 'false'}`,
          `settings_version=${settings.version}`, `testing_mode=${settings.testingMode ? 'true' : 'false'}`, `fixed_lot=${settings.fixedLot}`, `use_equity_scaling=${settings.useEquityScaling ? 'true' : 'false'}`,
          `equity_per_001_lot=${settings.equityPer001Lot}`, `initial_positions=${settings.initialPositions}`, `max_positions=${settings.maxPositions}`, `max_total_lots=${settings.maxTotalLots}`
        ].join('\n'));
      }
      if (request.method === 'POST' && pathname === '/api/ea/heartbeat') {
        state.ea = { ...state.ea, ...body, online: true, connectionStatus: 'CONNECTED', lastSeenAt: nowIso() };
        for (const key of ['balance','equity','margin','freeMargin','floatingProfit','peakBasketProfit','basketMae','totalLots','dailyPnl','newestLegProfit','newestLegPeak']) state.ea[key] = safeNumber(state.ea[key], 0);
        const consumed = safeNumber(state.ea.consumedCommandId); if (commandPending() && consumed >= state.command.id) { state.command.consumedAt = nowIso(); state.command.result = state.ea.lastCommandResult || state.ea.lastEvent || 'Consumed'; addEvent('command', `${state.command.action} consumed`, { id: state.command.id, result: state.command.result }); }
        return sendJson(request, response, 200, { ok: true, receivedAt: state.ea.lastSeenAt });
      }
      if (request.method === 'POST' && pathname === '/api/ea/scan') { const r = addRecord(scans, files.scans, MAX.scans, 'eve_momentum_scans', body); state.latestScan = r; return sendJson(request, response, 200, { ok: true, id: r.id }); }
      if (request.method === 'POST' && pathname === '/api/ea/basket') { const r = upsertBasket(body); addEvent('basket', `${r.side || 'BASKET'} closed ${safeNumber(r.netProfit).toFixed(2)}`, { exitReason: r.exitReason, positionsOpened: r.positionsOpened }); return sendJson(request, response, 200, { ok: true, id: r.id, performance: calculatePerformance(baskets) }); }
      if (request.method === 'POST' && pathname === '/api/ea/leg') { const r = addRecord(legs, files.legs, MAX.legs, 'eve_momentum_legs', body); return sendJson(request, response, 200, { ok: true, id: r.id }); }
      if (request.method === 'POST' && pathname === '/api/ea/order') { const r = addRecord(orders, files.orders, MAX.orders, 'eve_momentum_orders', body); return sendJson(request, response, 200, { ok: true, id: r.id }); }
      if (request.method === 'POST' && pathname === '/api/ea/bank') { const r = addRecord(banks, files.banks, MAX.banks, 'eve_momentum_bank_decisions', body); return sendJson(request, response, 200, { ok: true, id: r.id }); }
      if (request.method === 'POST' && pathname === '/api/ea/event') { const r = addEvent(body.type || 'ea', body.message || 'EA event', body.data || null); return sendJson(request, response, 200, { ok: true, id: r.id }); }
      if (request.method === 'POST' && pathname === '/api/command') {
        const action = String(body.action || '').toUpperCase();
        if (action === 'ENABLE_AUTO') { state.control.autonomous = true; state.control.emergency = false; addEvent('control', 'Autonomous enabled'); return sendJson(request, response, 200, { ok: true }); }
        if (action === 'DISABLE_AUTO') { state.control.autonomous = false; addEvent('control', 'Autonomous disabled'); return sendJson(request, response, 200, { ok: true }); }
        if (action === 'NEWS_LOCK_ON') { state.control.manualNewsLock = true; addEvent('control', 'News lock enabled'); return sendJson(request, response, 200, { ok: true }); }
        if (action === 'NEWS_LOCK_OFF') { state.control.manualNewsLock = false; addEvent('control', 'News lock disabled'); return sendJson(request, response, 200, { ok: true }); }
        if (action === 'EMERGENCY_STOP') { state.control.autonomous = false; state.control.emergency = true; return sendJson(request, response, 200, { ok: true, command: queueCommand(action) }); }
        if (action === 'RESET_EMERGENCY') { state.control.emergency = false; return sendJson(request, response, 200, { ok: true, command: queueCommand(action) }); }
        const supported = new Set(['CLOSE_BASKET','CLOSE_POSITION','PAUSE_EA','RESUME_EA','PAUSE_ADDING','RESUME_ADDING','REBUILD_BRACKET','RESET_TEST_COUNTERS']);
        if (!supported.has(action)) return sendJson(request, response, 400, { ok: false, error: 'Unsupported command' });
        return sendJson(request, response, 200, { ok: true, command: queueCommand(action) });
      }
      const exports = { scans, baskets, legs, orders, banks, events };
      const match = pathname.match(/^\/api\/export\/(scans|baskets|legs|orders|banks|events)\.csv$/);
      if (request.method === 'GET' && match) return sendText(request, response, 200, csvData(exports[match[1]].slice().reverse()), 'text/csv; charset=utf-8', { 'Content-Disposition': `attachment; filename="eve-momentum-${match[1]}.csv"` });
      return sendJson(request, response, 404, { ok: false, error: 'Not found' });
    } catch (error) { console.error(error); return sendJson(request, response, 500, { ok: false, error: error.message || 'Internal server error' }); }
  });
}

if (process.env.NODE_ENV !== 'test') createHttpServer().listen(PORT, () => { console.log(`${state.service} v${state.version} listening on ${PORT}`); addEvent('system', `Railway started v${state.version} - ${state.mode}`); });

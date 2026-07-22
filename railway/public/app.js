const $ = id => document.getElementById(id);
let token = localStorage.getItem('eveMomentumToken') || '';
let timer = null;
$('token').value = token;

const money = value => `${Number(value || 0) < 0 ? '-' : ''}$${Math.abs(Number(value || 0)).toFixed(2)}`;
const number = (value, digits = 2) => Number.isFinite(Number(value)) ? Number(value).toFixed(digits) : '—';
const when = value => value ? new Date(value).toLocaleString() : '—';
const classForDecision = value => value === 'BUY' ? 'good-text' : value === 'SELL' ? 'bad-text' : 'warn-text';

function setText(id, value) { $(id).textContent = value; }
function setClass(id, base, extra) { $(id).className = `${base} ${extra}`.trim(); }
function authUrl(path) { return `${path}${path.includes('?') ? '&' : '?'}token=${encodeURIComponent(token)}`; }

async function request(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: { 'Content-Type': 'application/json', 'x-bot-token': token, ...(options.headers || {}) }
  });
  const payload = await response.json().catch(() => ({ ok: false, error: `HTTP ${response.status}` }));
  if (!response.ok) throw new Error(payload.error || `HTTP ${response.status}`);
  return payload;
}

function render(data) {
  const { state, performance, recentScans, recentTrades, recentEvents } = data;
  const ea = state.ea || {};
  const scan = state.latestScan || {};
  const online = Boolean(ea.online);

  setText('railway', 'ONLINE');
  setText('version', `v${state.version}`);
  setText('eaStatus', online ? 'CONNECTED' : 'OFFLINE');
  setText('eaDetail', online ? `${ea.account || ''} • ${ea.symbol || ''} • EA ${ea.version || ''}` : 'No heartbeat within 15 seconds');
  $('eaStatus').className = online ? 'good-text' : 'bad-text';
  setText('systemBadge', online ? 'SYSTEM ONLINE' : 'EA OFFLINE');
  setClass('systemBadge', 'badge', online ? 'good' : 'bad');

  const decision = scan.decision || 'WAIT';
  setText('decision', decision);
  $('decision').className = classForDecision(decision);
  setText('decisionDetail', `${scan.buyScore ?? 0}/11 BUY • ${scan.sellScore ?? 0}/11 SELL`);
  setText('regime', scan.regime || 'WAIT');
  setText('regimeDetail', scan.regimeReason || 'No market classification');
  $('regime').className = scan.regime === 'HIGH_MOMENTUM' ? 'good-text' : scan.regime === 'CHAOTIC' ? 'bad-text' : 'warn-text';

  setText('autoTitle', state.control.autonomous ? 'AUTONOMOUS ON' : 'AUTONOMOUS OFF');
  $('autoTitle').className = state.control.autonomous ? 'good-text' : 'bad-text';
  setText('scanTime', scan.barTime ? `Closed M1: ${when(scan.barTime)}` : 'No scan received');
  setText('blockReason', scan.blockReason || 'Waiting for a fresh closed M1 candle.');
  setText('buyScore', `${scan.buyScore ?? 0}/11`);
  setText('sellScore', `${scan.sellScore ?? 0}/11`);
  setText('scoreGap', Math.abs(Number(scan.buyScore || 0) - Number(scan.sellScore || 0)));
  setText('m5Confirm', scan.m5Confirmation || '—');
  setText('spread', Number.isFinite(Number(scan.spreadPoints)) ? `${number(scan.spreadPoints, 1)} pts` : '—');
  setText('extension', Number.isFinite(Number(scan.extensionAtr)) ? `${number(scan.extensionAtr, 2)} ATR` : '—');

  setText('positionTitle', ea.positionOpen ? `${ea.side} ${number(ea.volume, 2)} LOT` : 'NONE');
  setText('positionState', ea.closePending ? 'CLOSE PENDING' : ea.positionOpen ? 'ACTIVE' : 'IDLE');
  setClass('positionState', 'badge', ea.closePending ? 'warn' : ea.positionOpen ? 'good' : 'neutral');
  setText('floatingProfit', money(ea.floatingProfit));
  $('floatingProfit').className = `position-profit ${Number(ea.floatingProfit) < 0 ? 'bad-text' : 'good-text'}`;
  setText('entryPrice', number(ea.entryPrice, 2));
  setText('currentPrice', number(ea.currentPrice, 2));
  setText('sl', number(ea.sl, 2));
  setText('tp', number(ea.tp, 2));
  setText('mfe', money(ea.mfe));
  setText('mae', money(ea.mae));
  setText('closeInfo', ea.closePending ? `Close pending: ${ea.closeReason || 'requested'} • attempts ${ea.closeAttempts || 0} • ${ea.lastCloseResult || ''}` : 'No close pending.');

  setText('balance', money(ea.balance));
  setText('equity', money(ea.equity));
  setText('dailyPnl', money(ea.dailyPnl));
  setText('tradesToday', String(ea.tradesToday ?? 0));
  setText('lossStreak', String(ea.consecutiveLosses ?? 0));
  setText('algo', ea.algoAllowed ? 'ALLOWED' : 'BLOCKED');
  $('algo').className = ea.algoAllowed ? 'good-text' : 'bad-text';
  setText('lastEvent', ea.lastEvent || 'No EA event.');

  setText('statTrades', performance.trades);
  setText('statWinRate', `${number(performance.winRate, 1)}%`);
  setText('statNet', money(performance.netProfit));
  setText('statPf', performance.profitFactor === 999 ? '∞' : number(performance.profitFactor, 2));
  setText('statAvg', money(performance.average));
  setText('statWorst', money(performance.worstTrade));

  $('scanRows').innerHTML = (recentScans || []).slice(0, 30).map(row => `<tr><td>${when(row.barTime || row.receivedAt)}</td><td class="${classForDecision(row.decision)}">${row.decision || 'WAIT'}</td><td>${row.buyScore ?? 0}</td><td>${row.sellScore ?? 0}</td><td>${row.regime || '—'}</td><td>${escapeHtml(row.blockReason || '')}</td></tr>`).join('') || '<tr><td colspan="6">No scans received yet.</td></tr>';
  $('tradeRows').innerHTML = (recentTrades || []).slice(0, 30).map(row => `<tr><td>${when(row.exitTime || row.receivedAt)}</td><td>${row.side || '—'}</td><td>${row.entryScore ?? '—'}</td><td>${number(row.entryPrice, 2)}</td><td>${number(row.exitPrice, 2)}</td><td class="${Number(row.netProfit) >= 0 ? 'good-text' : 'bad-text'}">${money(row.netProfit)}</td><td>${money(row.mfe)}</td><td>${money(row.mae)}</td><td>${escapeHtml(row.exitReason || '')}</td></tr>`).join('') || '<tr><td colspan="9">No completed trades yet.</td></tr>';
  $('eventRows').innerHTML = (recentEvents || []).slice(0, 40).map(row => `<div class="event"><span>${when(row.at)}</span><span>${escapeHtml(row.type || '')}</span><div>${escapeHtml(row.message || '')}</div></div>`).join('') || '<div class="notice">No events yet.</div>';

  $('exportTrades').href = authUrl('/api/export/trades.csv');
  $('exportScans').href = authUrl('/api/export/scans.csv');
}

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>'"]/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[char]));
}

async function refresh() {
  if (!token) return;
  try {
    const data = await request('/api/state');
    render(data);
    setText('message', 'Connected and authorised.');
    $('message').className = 'message good-text';
  } catch (error) {
    setText('message', error.message);
    $('message').className = 'message bad-text';
    setText('systemBadge', 'NOT AUTHORISED');
    setClass('systemBadge', 'badge', 'bad');
  }
}

$('connect').addEventListener('click', () => {
  token = $('token').value.trim();
  localStorage.setItem('eveMomentumToken', token);
  clearInterval(timer);
  refresh();
  timer = setInterval(refresh, 2000);
});

document.querySelectorAll('[data-action]').forEach(button => button.addEventListener('click', async () => {
  if (!token) return;
  button.disabled = true;
  try {
    const result = await request('/api/command', { method: 'POST', body: JSON.stringify({ action: button.dataset.action }) });
    setText('message', result.command ? `${result.command.action} sent to MT5.` : `${button.dataset.action} applied.`);
    $('message').className = 'message good-text';
    await refresh();
  } catch (error) {
    setText('message', error.message);
    $('message').className = 'message bad-text';
  } finally {
    button.disabled = false;
  }
}));

if (token) {
  refresh();
  timer = setInterval(refresh, 2000);
}

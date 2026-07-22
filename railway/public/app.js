const $ = id => document.getElementById(id);
let token = localStorage.getItem('eveMomentumToken') || '';
let timer = null;
$('token').value = token;

const money = value => `${Number(value || 0) < 0 ? '-' : ''}$${Math.abs(Number(value || 0)).toFixed(2)}`;
const number = (value, digits = 2) => Number.isFinite(Number(value)) ? Number(value).toFixed(digits) : '—';
const when = value => value ? new Date(value).toLocaleString() : '—';
const seconds = value => `${Math.max(0, Math.round(Number(value || 0)))}s`;
const classForDirection = value => value === 'BUY' || value === 'BURST' ? 'good-text' : value === 'SELL' || value === 'FLIP' ? 'bad-text' : 'warn-text';

function setText(id, value) { $(id).textContent = value; }
function setClass(id, base, extra) { $(id).className = `${base} ${extra}`.trim(); }
function authUrl(path) { return `${path}${path.includes('?') ? '&' : '?'}token=${encodeURIComponent(token)}`; }
function escapeHtml(value) { return String(value ?? '').replace(/[&<>'"]/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[char])); }

async function request(path, options = {}) {
  const response = await fetch(path, { ...options, headers: { 'Content-Type': 'application/json', 'x-bot-token': token, ...(options.headers || {}) } });
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
  setText('version', `v${state.version} • ${state.mode || 'LIVE BURST'}`);
  setText('eaStatus', online ? 'CONNECTED' : 'OFFLINE');
  setText('eaDetail', online ? `${ea.account || ''} • ${ea.symbol || ''} • EA ${ea.version || ''}` : 'No heartbeat within 15 seconds');
  $('eaStatus').className = online ? 'good-text' : 'bad-text';
  setText('systemBadge', online ? 'SYSTEM ONLINE' : 'EA OFFLINE');
  setClass('systemBadge', 'badge', online ? 'good' : 'bad');

  const momentumState = scan.momentumState || ea.momentumState || 'WARMING';
  setText('momentumState', momentumState);
  $('momentumState').className = momentumState === 'BURST' ? 'good-text' : momentumState === 'FLIP' || momentumState === 'CHAOTIC' ? 'bad-text' : 'warn-text';
  setText('stateDetail', `${scan.watchDirection || ea.liveDirection || 'NONE'} • ${scan.buyScore ?? ea.buyScore ?? 0}/11 BUY • ${scan.sellScore ?? ea.sellScore ?? 0}/11 SELL`);
  setText('regime', scan.regime || 'WAIT');
  setText('regimeDetail', scan.regimeReason || 'No market classification');
  $('regime').className = scan.regime === 'HIGH_MOMENTUM' ? 'good-text' : scan.regime === 'CHAOTIC' ? 'bad-text' : 'warn-text';

  const effectiveAuto = state.control.autonomous && (!online || ea.autonomous !== false);
  setText('autoTitle', effectiveAuto ? 'AUTONOMOUS ON' : state.control.autonomous ? 'AUTONOMOUS PAUSED' : 'AUTONOMOUS OFF');
  $('autoTitle').className = effectiveAuto ? 'good-text' : 'bad-text';
  setText('scanTime', scan.receivedAt ? `Live snapshot: ${when(scan.receivedAt)}` : 'No live snapshot received');
  setText('blockReason', scan.blockReason || 'Live tick engine warming.');
  setText('watchDirection', scan.watchDirection || ea.liveDirection || '—');
  $('watchDirection').className = classForDirection(scan.watchDirection || ea.liveDirection);
  setText('buyScore', `${scan.buyScore ?? ea.buyScore ?? 0}/11`);
  setText('sellScore', `${scan.sellScore ?? ea.sellScore ?? 0}/11`);
  setText('m5Confirm', scan.m5Confirmation || '—');
  setText('velocity1', `${number(scan.velocity1s ?? ea.velocity1s, 3)} ATR/s`);
  setText('velocity3', `${number(scan.velocity3s ?? ea.velocity3s, 3)} ATR/s`);
  setText('tickRate', `×${number(scan.tickRateRatio ?? ea.tickRateRatio, 2)}`);
  setText('extension', `${number(scan.extensionAtr ?? ea.extensionAtr, 2)} / ${number(scan.extensionLimitAtr, 2)} ATR`);

  const positionCount = Number(ea.positionCount || 0);
  const pendingCount = Number(ea.pendingCount || 0);
  setText('basketTitle', positionCount ? `${ea.side || 'BASKET'} BURST` : 'NONE');
  setText('basketState', ea.closePending ? 'CLOSE PENDING' : positionCount ? 'ACTIVE' : 'IDLE');
  setClass('basketState', 'badge', ea.closePending ? 'warn' : positionCount ? 'good' : 'neutral');
  setText('floatingProfit', money(ea.floatingProfit));
  $('floatingProfit').className = `position-profit ${Number(ea.floatingProfit) < 0 ? 'bad-text' : 'good-text'}`;
  setText('positionCounts', `${positionCount} / ${pendingCount}`);
  setText('totalLots', number(ea.totalLots, 2));
  setText('averageEntry', number(ea.averageEntry, 2));
  setText('protectedStop', number(ea.protectedStop, 2));
  setText('peakProfit', money(ea.peakBasketProfit));
  setText('basketMae', money(ea.basketMae));
  setText('basketTarget', money(ea.basketTargetMoney));
  setText('trailStart', money(ea.basketTrailStartMoney));
  setText('giveback', money(ea.basketGivebackMoney));
  const target = Number(ea.basketTargetMoney || 0);
  const progress = target > 0 ? Math.max(0, Math.min(100, Number(ea.floatingProfit || 0) / target * 100)) : 0;
  $('targetProgress').style.width = `${progress}%`;
  setText('closeInfo', ea.closePending ? `Close pending: ${ea.closeReason || 'requested'} • attempts ${ea.closeAttempts || 0} • ${ea.lastCloseResult || ''}` : pendingCount ? 'One continuation stop is waiting. It can only add while the basket is profitable and live momentum remains strong.' : 'No basket close pending.');

  setText('balance', money(ea.balance));
  setText('equity', money(ea.equity));
  setText('dailyPnl', money(ea.dailyPnl));
  setText('basketsToday', String(ea.basketsToday ?? 0));
  setText('lossStreak', String(ea.consecutiveLosses ?? 0));
  setText('algo', ea.algoAllowed ? 'ALLOWED' : 'BLOCKED');
  $('algo').className = ea.algoAllowed ? 'good-text' : 'bad-text';
  setText('spread', Number.isFinite(Number(ea.spreadPoints)) ? `${number(ea.spreadPoints, 1)} pts` : '—');
  setText('bodyAtr', `${number(scan.bodyAtr ?? ea.bodyAtr, 2)} ATR`);
  setText('lastEvent', ea.lastEvent || 'No EA event.');

  setText('statBaskets', performance.baskets ?? performance.trades ?? 0);
  setText('statLegs', performance.totalLegs ?? 0);
  setText('statWinRate', `${number(performance.winRate, 1)}%`);
  setText('statNet', money(performance.netProfit));
  setText('statPf', performance.profitFactor === 999 ? '∞' : number(performance.profitFactor, 2));
  setText('statAvg', money(performance.average));
  setText('statDuration', seconds(performance.averageDurationSeconds));
  setText('statWorst', money(performance.worstTrade));

  $('scanRows').innerHTML = (recentScans || []).slice(0, 50).map(row => `<tr>
    <td>${when(row.receivedAt || row.barTime)}</td>
    <td class="${row.momentumState === 'BURST' ? 'good-text' : row.momentumState === 'FLIP' ? 'bad-text' : 'warn-text'}">${escapeHtml(row.momentumState || row.decision || 'WAIT')}</td>
    <td class="${classForDirection(row.watchDirection)}">${escapeHtml(row.watchDirection || '—')}</td>
    <td>${row.buyScore ?? 0}</td><td>${row.sellScore ?? 0}</td>
    <td>${number(row.velocity1s, 3)}</td><td>${number(row.velocity3s, 3)}</td>
    <td>×${number(row.tickRateRatio, 2)}</td><td>${number(row.extensionAtr, 2)}</td>
    <td>${escapeHtml(row.blockReason || '')}</td></tr>`).join('') || '<tr><td colspan="10">No live momentum snapshots received yet.</td></tr>';

  $('tradeRows').innerHTML = (recentTrades || []).slice(0, 40).map(row => `<tr>
    <td>${when(row.exitTime || row.receivedAt)}</td><td>${escapeHtml(row.side || '—')}</td>
    <td>${row.positionsOpened ?? 1}</td><td>${number(row.volume, 2)}</td><td>${row.entryScore ?? '—'}</td>
    <td>${seconds(row.durationSeconds)}</td><td class="${Number(row.netProfit) >= 0 ? 'good-text' : 'bad-text'}">${money(row.netProfit)}</td>
    <td>${money(row.peakBasketProfit ?? row.mfe)}</td><td>${money(row.mae)}</td><td>${escapeHtml(row.exitReason || '')}</td></tr>`).join('') || '<tr><td colspan="10">No completed baskets yet.</td></tr>';

  $('eventRows').innerHTML = (recentEvents || []).slice(0, 50).map(row => `<div class="event"><span>${when(row.at)}</span><span>${escapeHtml(row.type || '')}</span><div>${escapeHtml(row.message || '')}</div></div>`).join('') || '<div class="notice">No events yet.</div>';
  $('exportTrades').href = authUrl('/api/export/trades.csv');
  $('exportScans').href = authUrl('/api/export/scans.csv');
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
  timer = setInterval(refresh, 1500);
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
  timer = setInterval(refresh, 1500);
}

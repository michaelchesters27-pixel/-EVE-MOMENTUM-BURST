const $ = id => document.getElementById(id);
let token = localStorage.getItem('eveMomentumToken') || '';
let timer = null;
let loadedSettingsVersion = -1;
$('token').value = token;

const money = value => `${Number(value || 0) < 0 ? '-' : ''}$${Math.abs(Number(value || 0)).toFixed(2)}`;
const number = (value, digits = 2) => Number.isFinite(Number(value)) ? Number(value).toFixed(digits) : '—';
const when = value => value ? new Date(value).toLocaleString() : '—';
const seconds = value => `${Math.max(0, Math.round(Number(value || 0)))}s`;
const esc = value => String(value ?? '').replace(/[&<>'"]/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;' }[c]));
const cls = value => Number(value || 0) > 0 ? 'good-text' : Number(value || 0) < 0 ? 'bad-text' : '';
function text(id, value) { const el = $(id); if (el) el.textContent = value; }
function setMoney(id, value) { text(id, money(value)); const el = $(id); if (el) el.className = cls(value); }
function authUrl(path) { return `${path}${path.includes('?') ? '&' : '?'}token=${encodeURIComponent(token)}`; }
async function request(path, options = {}) {
  const response = await fetch(path, { ...options, headers: { 'Content-Type': 'application/json', 'x-bot-token': token, ...(options.headers || {}) } });
  const payload = await response.json().catch(() => ({ ok:false, error:`HTTP ${response.status}` }));
  if (!response.ok) throw new Error(payload.error || `HTTP ${response.status}`);
  return payload;
}
function rows(id, items, render, emptyCols) {
  $(id).innerHTML = items.length ? items.map(render).join('') : `<tr><td colspan="${emptyCols}" class="muted">No records yet</td></tr>`;
}
function statsRows(id, items, includePf = false) {
  rows(id, items || [], r => `<tr><td>${esc(r.key)}</td><td>${r.baskets}</td><td>${number(r.winRate,1)}%</td><td class="${cls(r.netProfit)}">${money(r.netProfit)}</td>${includePf ? `<td>${r.profitFactor >= 999 ? '∞' : number(r.profitFactor,2)}</td>` : ''}</tr>`, includePf ? 5 : 4);
}

function operationalReason(ea, control) {
  if (ea.connectionStatus !== 'CONNECTED') return 'MARKET CLOSED OR NO FRESH MT5 HEARTBEAT — old scan values are ignored.';
  if (!control.autonomous || !ea.autonomous) return 'AUTONOMOUS OFF — no new price-trigger orders will be placed.';
  if (ea.emergency) return 'EMERGENCY STOP ACTIVE.';
  if (String(ea.engineState || '').includes('LEGACY') || String(ea.lastEvent || '').includes('previous EVE')) return ea.lastEvent || 'Removing old EVE orders before v2.06 starts.';
  if (ea.closePending) return ea.closeReason || 'Newest-leg SL triggered — banking the full basket.';
  if (Number(ea.positionCount || 0) > 0) {
    if (String(ea.campaignPhase || '').includes('OCO') || String(ea.engineState || '').includes('PROVISIONAL')) return 'FIRST TRIGGER PROVISIONAL — the opposite stop remains until the second same-side trigger.';
    return `ACTIVE ${ea.campaignCurrentSide || ea.side || ''} LADDER — newest triggered leg SL controls the full-basket exit.`;
  }
  if (Number(ea.bracketBuyPrice || 0) > 0 && Number(ea.bracketSellPrice || 0) > 0) return 'PRICE ENGINE ARMED — BUY STOP and SELL STOP are live. Scores do not control either order.';
  return 'WAITING FOR THE BROKER MARKET TO OPEN AND A FRESH TICK — scores do not control the bracket.';
}

function fillSettings(s, force = false) {
  if (!force && loadedSettingsVersion === Number(s.version)) return;
  loadedSettingsVersion = Number(s.version);
  $('fixedLot').value = number(s.fixedLot, 2);
  $('useEquityScaling').checked = Boolean(s.useEquityScaling);
  $('equityPer001Lot').value = s.equityPer001Lot;
  text('settingsVersion', `Settings v${s.version}`);
}
function render(payload) {
  const { state, settings, performance, recentScans, recentBaskets, recentLegs, recentOrders, recentBanks, recentEvents } = payload;
  const ea = state.ea || {}, control = state.control || {}, scan = state.latestScan || {};
  text('railway','ONLINE'); text('version',`v${state.version} • ${state.mode}`);
  const connectionLabel = ea.connectionStatus === 'DELAYED' && ea.terminalConnected ? 'TELEMETRY DELAYED' : (ea.connectionStatus || 'OFFLINE'); text('eaStatus', connectionLabel); $('eaStatus').className = ea.connectionStatus === 'CONNECTED' ? 'good-text' : ea.connectionStatus === 'DELAYED' ? 'warn-text' : 'bad-text';
  text('eaDetail', ea.account ? `${ea.account} • ${ea.symbol} • EA ${ea.version || '—'}` : 'No heartbeat');
  text('engineState', ea.campaignPhase || ea.engineState || '—'); text('engineDetail', `${ea.lastEvent || 'Waiting'}${ea.campaignStartSide && ea.campaignStartSide !== 'NONE' ? ` • ${ea.campaignStartSide}→${ea.campaignCurrentSide || ea.side || 'NONE'} • ${ea.campaignBuyLegs || 0} BUY/${ea.campaignSellLegs || 0} SELL` : ''}`);
  text('momentumState', ea.momentumState || '—'); text('momentumDetail', `DISPLAY ONLY • ${ea.buyScore || 0}/11 BUY • ${ea.sellScore || 0}/11 SELL`);
  text('autoTitle', `AUTONOMOUS ${control.autonomous ? 'ON' : 'OFF'}`); $('autoTitle').className = control.autonomous ? 'good-text' : 'bad-text';
  text('scanTime', ea.lastSeenAt ? `Heartbeat: ${when(ea.lastSeenAt)}` : 'No current heartbeat');
  text('blockReason', operationalReason(ea, control));
  text('watchDirection', Number(ea.positionCount || 0) > 0 ? (ea.campaignCurrentSide || ea.side || 'NONE') : 'NONE'); text('buyScore', `${ea.buyScore || scan.buyScore || 0}/11`); text('sellScore', `${ea.sellScore || scan.sellScore || 0}/11`);
  text('bracketState', ea.bracketState || 'NONE'); text('buyStop', Number(ea.bracketBuyPrice) > 0 ? number(ea.bracketBuyPrice, 2) : '—'); text('sellStop', Number(ea.bracketSellPrice) > 0 ? number(ea.bracketSellPrice, 2) : '—');
  text('velocities', `${number(ea.velocity1s,3)} / ${number(ea.velocity3s,3)}`); text('tickRate', `x${number(ea.tickRateRatio,2)}`);
  text('basketTitle', ea.positionCount ? `${ea.side} LADDER` : 'NONE'); text('basketState', ea.closePending ? 'CLOSE PENDING' : ea.positionCount ? 'ACTIVE' : 'IDLE');
  setMoney('floatingProfit', ea.floatingProfit); text('positionCounts', `${ea.positionCount || 0} / ${ea.pendingCount || 0}`); text('totalLots', number(ea.totalLots,2)); text('averageEntry', Number(ea.averageEntry)>0 ? number(ea.averageEntry,2) : '—'); text('protectedStop', Number(ea.protectedStop)>0 ? number(ea.protectedStop,2) : '—');
  setMoney('peakProfit', ea.peakBasketProfit); setMoney('basketMae', ea.basketMae); text('newestTicket', ea.newestTicket || '—'); text('newestProfit', `${money(ea.newestLegProfit)} / ${money(ea.newestLegPeak)}`); text('newestAge', seconds(ea.newestLegAgeSeconds));
  text('bankCandidate', ea.bankCandidate ? 'YES' : 'NO'); $('bankCandidate').className = ea.bankCandidate ? 'warn-text' : 'good-text'; text('bankReason', ea.bankReason || 'The newest triggered position SL controls the full-basket exit.'); text('closeInfo', ea.closePending ? `${ea.closeReason || 'Close pending'} • attempts ${ea.closeAttempts || 0}` : 'No close pending.');
  setMoney('balance', ea.balance); setMoney('equity', ea.equity); setMoney('dailyPnl', ea.dailyPnl); text('basketsToday', ea.basketsToday ?? '—'); text('lossStreak', `${ea.consecutiveLosses ?? '—'} • TRACKING ONLY`); text('algo', ea.algoAllowed ? 'ALLOWED' : 'BLOCKED'); $('algo').className = ea.algoAllowed ? 'good-text' : 'bad-text'; text('spread', `${number(ea.spreadPoints,1)} pts`); text('extension', `${number(ea.extensionAtr,2)} ATR`); text('lastEvent', ea.lastEvent || 'Waiting');
  const s = performance.summary || {};
  text('statBaskets', s.baskets || 0); text('statLegs', s.totalLegs || 0); text('statWinRate', `${number(s.winRate,1)}%`); setMoney('statNet', s.netProfit); text('statPf', s.profitFactor >= 999 ? '∞' : number(s.profitFactor,2)); setMoney('statAvg', s.averageBasket); text('statDuration', seconds(s.averageDurationSeconds)); setMoney('statBest', s.bestBasket); setMoney('statWorst', s.worstBasket); setMoney('statGiveback', s.averageGiveback); setMoney('statDrawdown', s.averageMaxDrawdown); setMoney('statPeak', s.peakFloatingProfit);
  statsRows('sideRows', performance.bySide, true); statsRows('bankStatRows', performance.byBankReason, false);
  rows('basketRows', recentBaskets.slice(0,100), r => `<tr><td>${when(r.exitTime || r.receivedAt)}</td><td>${esc(r.startSide && r.finalSide && r.startSide !== r.finalSide ? `${r.startSide}→${r.finalSide}` : (r.startSide || r.side))}</td><td>${r.positionsOpened || 0}</td><td>${number(r.lotPerLeg,2)}</td><td>${number(r.maxTotalLotsUsed || r.volume,2)}</td><td>${seconds(r.durationSeconds)}</td><td class="${cls(r.netProfit)}">${money(r.netProfit)}</td><td>${money(r.peakBasketProfit)}</td><td>${money(r.profitGiveback)}</td><td>${money(r.mae)}</td><td>${esc(r.exitReason)}</td></tr>`, 11);
  rows('legRows', recentLegs.slice(0,150), r => `<tr><td>${when(r.dealTime || r.receivedAt)}</td><td>${esc(r.action)}</td><td>${esc(r.side)}</td><td>${esc(r.ticket || r.positionId || '')}</td><td>${number(r.volume,2)}</td><td>${number(r.price,2)}</td><td class="${cls(r.netProfit)}">${money(r.netProfit)}</td><td>${esc(r.reason || '')}</td></tr>`, 8);
  rows('orderRows', recentOrders.slice(0,150), r => `<tr><td>${when(r.at || r.receivedAt)}</td><td>${esc(r.action)}</td><td>${esc(r.role)}</td><td>${esc(r.orderType)}</td><td>${esc(r.ticket || '')}</td><td>${number(r.volume,2)}</td><td>${number(r.price,2)}</td><td>${esc(r.reason || '')}</td></tr>`, 8);
  rows('bankRows', recentBanks.slice(0,100), r => `<tr><td>${when(r.at || r.receivedAt)}</td><td>${esc(r.side)}</td><td class="${cls(r.basketProfit)}">${money(r.basketProfit)}</td><td>${money(r.peakBasketProfit)}</td><td class="${cls(r.newestProfit)}">${money(r.newestProfit)}</td><td>${money(r.newestPeak)}</td><td>${r.sameScore || 0}/${r.oppositeScore || 0}</td><td>${esc(r.reason)}</td></tr>`, 8);
  rows('scanRows', recentScans.slice(0,120), r => `<tr><td>${when(r.receivedAt)}</td><td>${esc(r.momentumState)}</td><td>${esc(r.watchDirection)}</td><td>${r.buyScore || 0}</td><td>${r.sellScore || 0}</td><td>${number(r.velocity1s,3)}</td><td>${number(r.velocity3s,3)}</td><td>x${number(r.tickRateRatio,2)}</td><td>${number(r.extensionAtr,2)}</td><td>${esc(r.blockReason)}</td></tr>`, 10);
  $('eventRows').innerHTML = recentEvents.slice(0,100).map(e => `<div class="event"><span>${when(e.at)}</span><strong>${esc(e.type)}</strong><p>${esc(e.message)}</p></div>`).join('') || '<p class="muted">No events yet</p>';
  fillSettings(settings);
  $('systemBadge').textContent = ea.connectionStatus === 'CONNECTED' ? 'SYSTEM ONLINE' : ea.connectionStatus === 'DELAYED' ? 'MT5 LOCAL • DASHBOARD DELAYED' : 'EA OFFLINE';
  $('systemBadge').className = `badge ${ea.connectionStatus === 'CONNECTED' ? 'good' : ea.connectionStatus === 'DELAYED' ? 'warn' : 'bad'}`;
}
async function refresh() {
  if (!token) return;
  try { const payload = await request('/api/state'); render(payload); text('message','Connected and authorised.'); $('message').className='message good-text'; }
  catch (error) { text('message',error.message); $('message').className='message bad-text'; }
}
$('connect').addEventListener('click', () => { token = $('token').value.trim(); localStorage.setItem('eveMomentumToken', token); clearInterval(timer); refresh(); timer=setInterval(refresh,1500); });
$('applySettings').addEventListener('click', async () => {
  try {
    const body = { fixedLot:Number($('fixedLot').value), useEquityScaling:$('useEquityScaling').checked, equityPer001Lot:Number($('equityPer001Lot').value) };
    const result = await request('/api/settings',{method:'POST',body:JSON.stringify(body)}); fillSettings(result.settings); text('message','Settings saved. EA will receive them on its next poll.'); $('message').className='message good-text'; await refresh();
  } catch (error) { text('message',error.message); $('message').className='message bad-text'; }
});
document.querySelectorAll('[data-action]').forEach(button => button.addEventListener('click', async () => {
  button.disabled=true;
  try { const r=await request('/api/command',{method:'POST',body:JSON.stringify({action:button.dataset.action})}); text('message',r.command ? `${r.command.action} sent to MT5.` : `${button.dataset.action} applied.`); $('message').className='message good-text'; await refresh(); }
  catch(error){ text('message',error.message); $('message').className='message bad-text'; }
  finally{ button.disabled=false; }
}));
document.querySelectorAll('[data-export]').forEach(link => link.addEventListener('click', event => { event.preventDefault(); window.location.href=authUrl(`/api/export/${link.dataset.export}.csv`); }));
if (token) { refresh(); timer=setInterval(refresh,1500); }

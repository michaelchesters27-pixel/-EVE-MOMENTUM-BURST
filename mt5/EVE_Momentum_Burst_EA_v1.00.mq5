#property copyright "EVE Momentum Research"
#property version   "1.00"
#property strict
#property description "Broker-native XAUUSD M1 momentum research EA with one-position safety and full telemetry."

#include <Trade/Trade.mqh>

CTrade trade;

input group "Identity"
input string InpTradeSymbol                 = "";              // Blank = attached chart symbol
input ulong  InpMagicNumber                 = 2207202603;
input string InpOrderComment                = "EVE-MOMENTUM-V1";

input group "Railway connection"
input string InpRailwayBaseUrl              = "https://YOUR-SERVICE.up.railway.app";
input string InpBotToken                    = "CHANGE-ME";
input int    InpHeartbeatSeconds             = 3;
input int    InpCommandPollSeconds           = 2;
input int    InpWebTimeoutMs                 = 3000;

input group "Execution"
input bool   InpAutonomousAtStart            = true;
input double InpFixedLot                     = 0.01;
input ENUM_TIMEFRAMES InpExecutionTimeframe  = PERIOD_M1;
input ENUM_TIMEFRAMES InpConfirmationTimeframe = PERIOD_M5;
input int    InpSlippagePoints               = 30;
input int    InpCooldownSeconds              = 60;
input int    InpMaximumHoldingMinutes        = 15;

input group "Momentum score"
input int    InpATRPeriod                    = 14;
input int    InpFastEMA                      = 9;
input int    InpSlowEMA                      = 21;
input int    InpTrendEMA                     = 50;
input int    InpBreakoutLookback             = 10;
input int    InpEntryScoreThreshold          = 7;
input int    InpMinimumScoreDifference       = 3;
input double InpMinimumVelocityATR           = 0.35;
input double InpATRExpansionMinimum          = 1.10;
input double InpMinimumBodyRatio             = 0.60;
input double InpMinimumVolumeRatio           = 1.20;
input int    InpMinimumDirectionalCandles    = 2;
input int    InpMaximumDirectionalCandles    = 4;
input bool   InpRequireM5Confirmation        = true;

input group "Location and market quality"
input double InpMaximumExtensionATR          = 0.85;
input double InpNearM5LevelATR               = 0.30;
input double InpBreakoutBufferATR            = 0.08;
input int    InpAbsoluteMaximumSpreadPoints  = 90;
input double InpSpreadMedianMultiplier       = 1.80;
input bool   InpUseSessionFilter             = true;
input int    InpSessionStartUTC              = 6;
input int    InpSessionEndUTC                = 21;

input group "Position protection"
input double InpStopLossATR                  = 1.00;
input double InpTakeProfitATR                = 1.20;
input double InpBreakEvenTriggerATR          = 0.45;
input double InpTrailingActivationATR        = 0.60;
input double InpStrongTrailATR               = 0.45;
input double InpNormalTrailATR               = 0.30;
input double InpWeakTrailATR                 = 0.18;
input int    InpCloseRetrySeconds            = 5;

input group "Daily account protection"
input double InpMaximumDailyLossPercent      = 2.00;
input double InpDailyProfitTargetPercent     = 3.00;
input int    InpMaximumTradesPerDay          = 20;
input int    InpMaximumConsecutiveLosses     = 4;

string PANEL_PREFIX = "EVE_MB_";
string trade_symbol = "";
string gv_prefix = "";

int atr_handle = INVALID_HANDLE;
int fast_handle = INVALID_HANDLE;
int slow_handle = INVALID_HANDLE;
int trend_handle = INVALID_HANDLE;
int confirm_atr_handle = INVALID_HANDLE;
int confirm_fast_handle = INVALID_HANDLE;
int confirm_slow_handle = INVALID_HANDLE;

struct ScanSnapshot
{
   datetime bar_time;
   int buy_score;
   int sell_score;
   int score_gap;
   string decision;
   string watch_direction;
   string block_reason;
   string regime;
   string regime_reason;
   string m5_confirmation;
   double atr;
   double atr_ratio;
   double velocity;
   double body_ratio;
   double volume_ratio;
   double extension_atr;
   double spread_points;
   double median_spread_points;
   double resistance;
   double support;
   string buy_components;
   string sell_components;
};

ScanSnapshot last_scan;
bool have_scan = false;
datetime last_scanned_bar = 0;
datetime last_entry_bar = 0;
datetime last_trade_closed_at = 0;

bool remote_autonomous = true;
bool local_paused = false;
bool emergency_stopped = false;
bool manual_news_lock = false;
long last_command_id = 0;
bool last_command_succeeded = false;
string last_command_result = "No command received";
string last_event = "EA starting";
datetime last_heartbeat_at = 0;
datetime last_poll_at = 0;

bool close_pending = false;
string close_reason = "";
double close_trigger_profit = 0.0;
datetime close_requested_at = 0;
datetime last_close_attempt_at = 0;
int close_attempts = 0;
uint last_close_retcode = 0;
string last_close_result = "No close requested";

ulong active_ticket = 0;
ulong active_position_id = 0;
string active_side = "NONE";
datetime active_entry_time = 0;
double active_entry_price = 0.0;
double active_volume = 0.0;
double active_entry_atr = 0.0;
int active_entry_score = 0;
int active_opposite_score = 0;
string active_entry_regime = "";
string active_entry_reason = "";
double active_mfe = 0.0;
double active_mae = 0.0;
bool active_reported = false;
ulong last_reported_exit_deal = 0;

int day_key = 0;
double day_start_balance = 0.0;
double daily_pnl = 0.0;
int trades_today = 0;
int consecutive_losses = 0;

double spread_samples[240];
int spread_sample_count = 0;
int spread_sample_index = 0;

int OnInit()
{
   trade_symbol = ResolveTradeSymbol();
   if(trade_symbol == "")
   {
      Print("EVE Momentum: could not resolve a Gold symbol.");
      return INIT_FAILED;
   }
   if(!SymbolSelect(trade_symbol, true))
   {
      Print("EVE Momentum: cannot select symbol ", trade_symbol);
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(trade_symbol);
   trade.SetMarginMode();

   atr_handle = iATR(trade_symbol, InpExecutionTimeframe, InpATRPeriod);
   fast_handle = iMA(trade_symbol, InpExecutionTimeframe, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   slow_handle = iMA(trade_symbol, InpExecutionTimeframe, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   trend_handle = iMA(trade_symbol, InpExecutionTimeframe, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   confirm_atr_handle = iATR(trade_symbol, InpConfirmationTimeframe, InpATRPeriod);
   confirm_fast_handle = iMA(trade_symbol, InpConfirmationTimeframe, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   confirm_slow_handle = iMA(trade_symbol, InpConfirmationTimeframe, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(atr_handle == INVALID_HANDLE || fast_handle == INVALID_HANDLE || slow_handle == INVALID_HANDLE ||
      trend_handle == INVALID_HANDLE || confirm_atr_handle == INVALID_HANDLE ||
      confirm_fast_handle == INVALID_HANDLE || confirm_slow_handle == INVALID_HANDLE)
   {
      Print("EVE Momentum: indicator handle creation failed. Error ", GetLastError());
      return INIT_FAILED;
   }

   remote_autonomous = InpAutonomousAtStart;
   gv_prefix = PersistentPrefix();
   RecoverDailyState();
   RecoverOpenPosition();
   CreatePanel();
   EventSetTimer(1);
   last_event = "EA started; waiting for a fresh closed M1 candle";
   SendEvent("system", last_event);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   SavePersistentState();
   EventKillTimer();
   DeletePanel();
   ReleaseHandles();
}

void OnTick()
{
   UpdateSpreadSample();
   ManagePosition();
   ProcessFreshClosedBar();
   UpdatePanel();
}

void OnTimer()
{
   datetime now = TimeCurrent();
   if(now - last_poll_at >= MathMax(1, InpCommandPollSeconds))
   {
      PollRailway();
      last_poll_at = now;
   }
   if(now - last_heartbeat_at >= MathMax(1, InpHeartbeatSeconds))
   {
      SendHeartbeat();
      last_heartbeat_at = now;
   }
   ManagePosition();
   DetectUnreportedExternalClose();
   UpdatePanel();
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;
   if(sparam == PANEL_PREFIX+"PAUSE") ExecuteCommand(local_paused ? "RESUME_EA" : "PAUSE_EA");
   else if(sparam == PANEL_PREFIX+"CLOSE") ExecuteCommand("CLOSE_POSITION");
   else if(sparam == PANEL_PREFIX+"STOP") ExecuteCommand("EMERGENCY_STOP");
}

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != trade_symbol) return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   ulong magic = (ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   ulong position_id = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);

   if((entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_INOUT) && magic == InpMagicNumber)
   {
      active_position_id = position_id;
      active_entry_time = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
      active_entry_price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
      active_side = HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY ? "BUY" : "SELL";
      active_reported = false;
      SavePersistentState();
      return;
   }

   if((entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT) &&
      active_position_id > 0 && position_id == active_position_id && trans.deal != last_reported_exit_deal)
   {
      ReportCompletedTrade(trans.deal);
   }
}

void ProcessFreshClosedBar()
{
   datetime closed_bar = iTime(trade_symbol, InpExecutionTimeframe, 1);
   if(closed_bar <= 0 || closed_bar == last_scanned_bar) return;
   last_scanned_bar = closed_bar;

   ScanSnapshot scan;
   if(!BuildScan(scan))
   {
      last_event = "Waiting for enough broker candle history";
      return;
   }

   ApplyOperationalBlocks(scan);
   last_scan = scan;
   have_scan = true;
   SendScan(scan);

   if(scan.decision == "BUY" || scan.decision == "SELL")
      TryOpenFromScan(scan);
}

bool BuildScan(ScanSnapshot &scan)
{
   MqlRates rates[];
   MqlRates confirm_rates[];
   double atr[];
   double fast[];
   double slow[];
   double trend[];
   double confirm_atr[];
   double confirm_fast[];
   double confirm_slow[];

   ArraySetAsSeries(rates, true);
   ArraySetAsSeries(confirm_rates, true);
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(trend, true);
   ArraySetAsSeries(confirm_atr, true);
   ArraySetAsSeries(confirm_fast, true);
   ArraySetAsSeries(confirm_slow, true);

   int needed = MathMax(80, InpBreakoutLookback + 30);
   if(CopyRates(trade_symbol, InpExecutionTimeframe, 0, needed, rates) < needed) return false;
   if(CopyRates(trade_symbol, InpConfirmationTimeframe, 0, 80, confirm_rates) < 60) return false;
   if(CopyBuffer(atr_handle, 0, 0, 40, atr) < 30) return false;
   if(CopyBuffer(fast_handle, 0, 0, 10, fast) < 6) return false;
   if(CopyBuffer(slow_handle, 0, 0, 10, slow) < 6) return false;
   if(CopyBuffer(trend_handle, 0, 0, 10, trend) < 6) return false;
   if(CopyBuffer(confirm_atr_handle, 0, 0, 30, confirm_atr) < 20) return false;
   if(CopyBuffer(confirm_fast_handle, 0, 0, 10, confirm_fast) < 6) return false;
   if(CopyBuffer(confirm_slow_handle, 0, 0, 10, confirm_slow) < 6) return false;

   double atr_now = atr[1];
   if(atr_now <= 0) return false;

   double atr_average = 0.0;
   for(int i=2; i<22; i++) atr_average += atr[i];
   atr_average /= 20.0;
   double atr_ratio = atr_average > 0 ? atr_now / atr_average : 1.0;

   double v1 = (rates[1].close - rates[2].close) / atr_now;
   double v3 = (rates[1].close - rates[4].close) / atr_now;
   double v5 = (rates[1].close - rates[6].close) / atr_now;
   double velocity = (v1 * 0.45) + (v3 * 0.35) + (v5 * 0.20);

   double range = rates[1].high - rates[1].low;
   double body = MathAbs(rates[1].close - rates[1].open);
   double body_ratio = range > 0 ? body / range : 0.0;
   double close_location = range > 0 ? (rates[1].close - rates[1].low) / range : 0.5;

   double volume_average = 0.0;
   for(int i=2; i<22; i++) volume_average += (double)rates[i].tick_volume;
   volume_average /= 20.0;
   double volume_ratio = volume_average > 0 ? (double)rates[1].tick_volume / volume_average : 1.0;

   double breakout_high = rates[2].high;
   double breakout_low = rates[2].low;
   for(int i=3; i<2+InpBreakoutLookback; i++)
   {
      breakout_high = MathMax(breakout_high, rates[i].high);
      breakout_low = MathMin(breakout_low, rates[i].low);
   }
   bool bullish_breakout = rates[1].close > breakout_high + (InpBreakoutBufferATR * atr_now);
   bool bearish_breakout = rates[1].close < breakout_low - (InpBreakoutBufferATR * atr_now);

   int bullish_candles = 0;
   int bearish_candles = 0;
   int consecutive_bullish = 0;
   int consecutive_bearish = 0;
   bool bull_chain = true;
   bool bear_chain = true;
   for(int i=1; i<=6; i++)
   {
      bool bull = rates[i].close > rates[i].open;
      bool bear = rates[i].close < rates[i].open;
      if(i <= 3)
      {
         if(bull) bullish_candles++;
         if(bear) bearish_candles++;
      }
      if(bull_chain && bull) consecutive_bullish++; else bull_chain = false;
      if(bear_chain && bear) consecutive_bearish++; else bear_chain = false;
   }

   int buy_score = 0;
   int sell_score = 0;
   string buy_components = "";
   string sell_components = "";

   if(velocity >= InpMinimumVelocityATR) { buy_score += 2; AddComponent(buy_components, "velocity"); }
   if(velocity <= -InpMinimumVelocityATR) { sell_score += 2; AddComponent(sell_components, "velocity"); }

   bool strong_bull_candle = rates[1].close > rates[1].open && body_ratio >= InpMinimumBodyRatio && close_location >= 0.72;
   bool strong_bear_candle = rates[1].close < rates[1].open && body_ratio >= InpMinimumBodyRatio && close_location <= 0.28;
   if(strong_bull_candle) { buy_score += 2; AddComponent(buy_components, "candle"); }
   if(strong_bear_candle) { sell_score += 2; AddComponent(sell_components, "candle"); }

   if(bullish_breakout) { buy_score += 2; AddComponent(buy_components, "breakout"); }
   if(bearish_breakout) { sell_score += 2; AddComponent(sell_components, "breakout"); }

   if(atr_ratio >= InpATRExpansionMinimum)
   {
      if(velocity > 0) { buy_score += 1; AddComponent(buy_components, "atr-expansion"); }
      if(velocity < 0) { sell_score += 1; AddComponent(sell_components, "atr-expansion"); }
   }

   if(volume_ratio >= InpMinimumVolumeRatio)
   {
      if(rates[1].close >= rates[1].open) { buy_score += 1; AddComponent(buy_components, "volume"); }
      if(rates[1].close <= rates[1].open) { sell_score += 1; AddComponent(sell_components, "volume"); }
   }

   if(fast[1] > slow[1] && rates[1].close > trend[1]) { buy_score += 1; AddComponent(buy_components, "ema-align"); }
   if(fast[1] < slow[1] && rates[1].close < trend[1]) { sell_score += 1; AddComponent(sell_components, "ema-align"); }

   if(fast[1] > fast[4]) { buy_score += 1; AddComponent(buy_components, "ema-slope"); }
   if(fast[1] < fast[4]) { sell_score += 1; AddComponent(sell_components, "ema-slope"); }

   if(bullish_candles >= InpMinimumDirectionalCandles) { buy_score += 1; AddComponent(buy_components, "consistency"); }
   if(bearish_candles >= InpMinimumDirectionalCandles) { sell_score += 1; AddComponent(sell_components, "consistency"); }

   string m5_confirmation = "NEUTRAL";
   bool m5_buy = confirm_fast[1] > confirm_slow[1] && confirm_rates[1].close > confirm_slow[1];
   bool m5_sell = confirm_fast[1] < confirm_slow[1] && confirm_rates[1].close < confirm_slow[1];
   if(m5_buy && !m5_sell) m5_confirmation = "BUY";
   else if(m5_sell && !m5_buy) m5_confirmation = "SELL";

   double extension_atr = MathAbs(rates[1].close - fast[1]) / atr_now;
   double m5_resistance = confirm_rates[2].high;
   double m5_support = confirm_rates[2].low;
   for(int i=3; i<22; i++)
   {
      m5_resistance = MathMax(m5_resistance, confirm_rates[i].high);
      m5_support = MathMin(m5_support, confirm_rates[i].low);
   }

   double spread = CurrentSpreadPoints();
   double median_spread = MedianSpreadPoints();
   bool spread_chaotic = spread > InpAbsoluteMaximumSpreadPoints ||
      (median_spread > 0 && spread > median_spread * InpSpreadMedianMultiplier);

   string regime = "NORMAL";
   string regime_reason = "Normal directional conditions";
   double ema_separation = MathAbs(fast[1] - slow[1]) / atr_now;
   if(spread_chaotic)
   {
      regime = "CHAOTIC";
      regime_reason = "Spread is abnormal relative to the recent broker norm";
   }
   else if(atr_ratio < 0.86 || ema_separation < 0.08)
   {
      regime = "QUIET";
      regime_reason = "Low ATR expansion or compressed fast/slow EMA separation";
   }
   else if(atr_ratio >= 1.35 && MathMax(buy_score, sell_score) >= 8 && MathAbs(velocity) >= 0.45)
   {
      regime = "HIGH_MOMENTUM";
      regime_reason = "ATR, velocity and directional score are expanding together";
   }

   int threshold = InpEntryScoreThreshold + (regime == "QUIET" ? 1 : 0);
   int gap = MathAbs(buy_score - sell_score);
   string best = buy_score >= sell_score ? "BUY" : "SELL";
   int best_score = MathMax(buy_score, sell_score);
   bool confirmation_ok = !InpRequireM5Confirmation || m5_confirmation == best;
   bool extension_ok = extension_atr <= InpMaximumExtensionATR;
   bool directional_count_ok = best == "BUY" ? consecutive_bullish <= InpMaximumDirectionalCandles : consecutive_bearish <= InpMaximumDirectionalCandles;
   bool near_level = false;
   if(best == "BUY" && m5_resistance > rates[1].close && !bullish_breakout)
      near_level = (m5_resistance - rates[1].close) / atr_now <= InpNearM5LevelATR;
   if(best == "SELL" && m5_support < rates[1].close && !bearish_breakout)
      near_level = (rates[1].close - m5_support) / atr_now <= InpNearM5LevelATR;

   string decision = "WAIT";
   string block = "Waiting for a stronger momentum state";
   if(regime == "CHAOTIC") block = "WAIT — broker spread/feed conditions are abnormal";
   else if(best_score < threshold) block = StringFormat("WAIT — best score %d/11 is below %d/11", best_score, threshold);
   else if(gap < InpMinimumScoreDifference) block = StringFormat("WAIT — BUY/SELL score gap %d is below %d", gap, InpMinimumScoreDifference);
   else if(!confirmation_ok) block = "WAIT — M5 confirmation does not support the M1 momentum direction";
   else if(!extension_ok) block = StringFormat("WAIT — price is extended %.2f ATR from EMA%d", extension_atr, InpFastEMA);
   else if(!directional_count_ok) block = "WAIT — too many same-direction candles; do not chase an exhausted move";
   else if(near_level) block = best == "BUY" ? "WAIT — BUY is too close to M5 resistance" : "WAIT — SELL is too close to M5 support";
   else
   {
      decision = best;
      block = StringFormat("%s permitted — score %d/11, gap %d, M5 %s", best, best_score, gap, m5_confirmation);
   }

   scan.bar_time = rates[1].time;
   scan.buy_score = buy_score;
   scan.sell_score = sell_score;
   scan.score_gap = gap;
   scan.decision = decision;
   scan.watch_direction = best;
   scan.block_reason = block;
   scan.regime = regime;
   scan.regime_reason = regime_reason;
   scan.m5_confirmation = m5_confirmation;
   scan.atr = atr_now;
   scan.atr_ratio = atr_ratio;
   scan.velocity = velocity;
   scan.body_ratio = body_ratio;
   scan.volume_ratio = volume_ratio;
   scan.extension_atr = extension_atr;
   scan.spread_points = spread;
   scan.median_spread_points = median_spread;
   scan.resistance = m5_resistance;
   scan.support = m5_support;
   scan.buy_components = buy_components;
   scan.sell_components = sell_components;
   return true;
}

void ApplyOperationalBlocks(ScanSnapshot &scan)
{
   ResetDailyIfNeeded();
   if(scan.decision == "WAIT") return;

   if(!remote_autonomous || local_paused)
   {
      scan.decision = "WAIT";
      scan.block_reason = local_paused ? "WAIT — EA is paused" : "WAIT — autonomous mode is disabled";
      return;
   }
   if(emergency_stopped)
   {
      scan.decision = "WAIT";
      scan.block_reason = "WAIT — emergency stop is active";
      return;
   }
   if(manual_news_lock)
   {
      scan.decision = "WAIT";
      scan.block_reason = "WAIT — manual high-impact news lock is active";
      return;
   }
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      scan.decision = "WAIT";
      scan.block_reason = "WAIT — MT5 connection or Algo Trading permission is unavailable";
      return;
   }
   if(HasOurPosition() || close_pending)
   {
      scan.decision = "WAIT";
      scan.block_reason = close_pending ? "WAIT — position close is pending" : "WAIT — the bot already has an active position";
      return;
   }
   if(last_entry_bar == scan.bar_time)
   {
      scan.decision = "WAIT";
      scan.block_reason = "WAIT — this M1 signal has already been used";
      return;
   }
   if(last_trade_closed_at > 0 && TimeCurrent() - last_trade_closed_at < InpCooldownSeconds)
   {
      scan.decision = "WAIT";
      scan.block_reason = StringFormat("WAIT — cooldown active for %d more seconds", InpCooldownSeconds - (int)(TimeCurrent() - last_trade_closed_at));
      return;
   }
   if(InpUseSessionFilter && !InsideTradingSessionUTC())
   {
      scan.decision = "WAIT";
      scan.block_reason = StringFormat("WAIT — outside configured UTC session %02d:00-%02d:00", InpSessionStartUTC, InpSessionEndUTC);
      return;
   }
   if(trades_today >= InpMaximumTradesPerDay)
   {
      scan.decision = "WAIT";
      scan.block_reason = "WAIT — maximum trades for the UTC day reached";
      return;
   }
   if(consecutive_losses >= InpMaximumConsecutiveLosses)
   {
      scan.decision = "WAIT";
      scan.block_reason = "WAIT — consecutive-loss safety lock is active until the next UTC day";
      return;
   }
   double loss_limit = day_start_balance * InpMaximumDailyLossPercent / 100.0;
   double target = day_start_balance * InpDailyProfitTargetPercent / 100.0;
   if(daily_pnl <= -loss_limit)
   {
      scan.decision = "WAIT";
      scan.block_reason = "WAIT — daily loss limit reached";
      return;
   }
   if(daily_pnl >= target)
   {
      scan.decision = "WAIT";
      scan.block_reason = "WAIT — daily profit target reached";
      return;
   }
}

bool TryOpenFromScan(const ScanSnapshot &scan)
{
   if(scan.decision != "BUY" && scan.decision != "SELL") return false;
   if(HasOurPosition() || close_pending) return false;

   MqlTick tick;
   if(!SymbolInfoTick(trade_symbol, tick)) return false;
   double point = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(trade_symbol, SYMBOL_DIGITS);
   double min_stop = MathMax((double)SymbolInfoInteger(trade_symbol, SYMBOL_TRADE_STOPS_LEVEL),
                             (double)SymbolInfoInteger(trade_symbol, SYMBOL_TRADE_FREEZE_LEVEL)) * point;
   double sl_distance = MathMax(scan.atr * InpStopLossATR, min_stop + (3.0 * point));
   double tp_distance = MathMax(scan.atr * InpTakeProfitATR, min_stop + (3.0 * point));
   double volume = NormalizeVolume(InpFixedLot);
   if(volume <= 0) return false;

   double sl = 0.0;
   double tp = 0.0;
   bool submitted = false;
   ResetLastError();

   if(scan.decision == "BUY")
   {
      sl = NormalizeDouble(tick.ask - sl_distance, digits);
      tp = NormalizeDouble(tick.ask + tp_distance, digits);
      submitted = trade.Buy(volume, trade_symbol, 0.0, sl, tp, InpOrderComment);
   }
   else
   {
      sl = NormalizeDouble(tick.bid + sl_distance, digits);
      tp = NormalizeDouble(tick.bid - tp_distance, digits);
      submitted = trade.Sell(volume, trade_symbol, 0.0, sl, tp, InpOrderComment);
   }

   uint code = trade.ResultRetcode();
   if(!submitted || !TradeResultAccepted(code))
   {
      last_event = StringFormat("Entry rejected: retcode %u %s", code, trade.ResultRetcodeDescription());
      SendEvent("entry-error", last_event);
      return false;
   }

   active_side = scan.decision;
   active_entry_time = TimeCurrent();
   active_entry_price = trade.ResultPrice();
   active_volume = volume;
   active_entry_atr = scan.atr;
   active_entry_score = scan.decision == "BUY" ? scan.buy_score : scan.sell_score;
   active_opposite_score = scan.decision == "BUY" ? scan.sell_score : scan.buy_score;
   active_entry_regime = scan.regime;
   active_entry_reason = scan.block_reason;
   active_mfe = 0.0;
   active_mae = 0.0;
   active_reported = false;
   close_pending = false;
   close_reason = "";
   last_entry_bar = scan.bar_time;
   trades_today++;
   CaptureOurPosition();
   last_event = StringFormat("%s opened %.2f lot at %.2f; score %d/11", active_side, volume, active_entry_price, active_entry_score);
   SendEvent("entry", last_event);
   SavePersistentState();
   return true;
}

void ManagePosition()
{
   if(close_pending)
   {
      ContinuePendingClose();
      return;
   }

   if(!SelectOurPosition()) return;

   ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double current = PositionGetDouble(POSITION_PRICE_CURRENT);
   double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);
   datetime opened = (datetime)PositionGetInteger(POSITION_TIME);

   active_ticket = ticket;
   if(active_position_id == 0) active_position_id = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   if(active_entry_time == 0) active_entry_time = opened;
   if(active_entry_price == 0) active_entry_price = entry;
   if(active_side == "NONE") active_side = type == POSITION_TYPE_BUY ? "BUY" : "SELL";
   active_mfe = MathMax(active_mfe, profit);
   active_mae = MathMin(active_mae, profit);

   if(TimeCurrent() - opened >= InpMaximumHoldingMinutes * 60)
   {
      RequestClose("MAXIMUM HOLDING TIME", profit);
      return;
   }

   if(emergency_stopped)
   {
      RequestClose("EMERGENCY STOP", profit);
      return;
   }

   double atr_now = active_entry_atr;
   double atr_buffer[];
   ArraySetAsSeries(atr_buffer, true);
   if(CopyBuffer(atr_handle, 0, 0, 3, atr_buffer) >= 2 && atr_buffer[1] > 0) atr_now = atr_buffer[1];
   if(atr_now <= 0) return;

   double favourable_move = type == POSITION_TYPE_BUY ? current - entry : entry - current;
   double point = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(trade_symbol, SYMBOL_DIGITS);
   double minimum_distance = MathMax((double)SymbolInfoInteger(trade_symbol, SYMBOL_TRADE_STOPS_LEVEL),
                                     (double)SymbolInfoInteger(trade_symbol, SYMBOL_TRADE_FREEZE_LEVEL)) * point;

   double desired_sl = sl;
   if(favourable_move >= atr_now * InpBreakEvenTriggerATR)
   {
      double cost_buffer = (CurrentSpreadPoints() + 5.0) * point;
      double break_even = type == POSITION_TYPE_BUY ? entry + cost_buffer : entry - cost_buffer;
      if(type == POSITION_TYPE_BUY && (desired_sl == 0 || break_even > desired_sl)) desired_sl = break_even;
      if(type == POSITION_TYPE_SELL && (desired_sl == 0 || break_even < desired_sl)) desired_sl = break_even;
   }

   if(favourable_move >= atr_now * InpTrailingActivationATR)
   {
      int current_score = active_entry_score;
      if(have_scan) current_score = active_side == "BUY" ? last_scan.buy_score : last_scan.sell_score;
      double trail_mult = current_score >= 9 ? InpStrongTrailATR : current_score >= 7 ? InpNormalTrailATR : InpWeakTrailATR;
      double trail = atr_now * trail_mult;
      double candidate = type == POSITION_TYPE_BUY ? current - trail : current + trail;
      if(type == POSITION_TYPE_BUY && (desired_sl == 0 || candidate > desired_sl)) desired_sl = candidate;
      if(type == POSITION_TYPE_SELL && (desired_sl == 0 || candidate < desired_sl)) desired_sl = candidate;
   }

   if(desired_sl > 0)
   {
      if(type == POSITION_TYPE_BUY) desired_sl = MathMin(desired_sl, current - minimum_distance);
      else desired_sl = MathMax(desired_sl, current + minimum_distance);
      desired_sl = NormalizeDouble(desired_sl, digits);
      bool tighter = type == POSITION_TYPE_BUY ? (sl == 0 || desired_sl > sl + point) : (sl == 0 || desired_sl < sl - point);
      if(tighter)
      {
         if(!trade.PositionModify(ticket, desired_sl, tp) || !TradeResultAccepted(trade.ResultRetcode()))
            PrintFormat("Protective stop update failed %u %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
      }
   }

   if(have_scan && profit > 0 && TimeCurrent() - opened >= 30)
   {
      int same_score = active_side == "BUY" ? last_scan.buy_score : last_scan.sell_score;
      int opposite_score = active_side == "BUY" ? last_scan.sell_score : last_scan.buy_score;
      string opposite = active_side == "BUY" ? "SELL" : "BUY";
      if(same_score <= 3 && opposite_score >= InpEntryScoreThreshold && last_scan.m5_confirmation == opposite)
      {
         RequestClose("CONFIRMED MOMENTUM REVERSAL", profit);
         return;
      }
   }

   SavePersistentState();
}

bool RequestClose(string reason, double trigger_profit)
{
   if(!HasOurPosition())
   {
      close_pending = false;
      last_event = "Close requested but bot position is already flat";
      return true;
   }
   if(!close_pending)
   {
      close_pending = true;
      close_reason = reason;
      close_trigger_profit = trigger_profit;
      close_requested_at = TimeCurrent();
      last_close_attempt_at = 0;
      close_attempts = 0;
      last_event = StringFormat("CLOSE PENDING — %s; trigger $%.2f", reason, trigger_profit);
      SendEvent("close", last_event);
   }
   ContinuePendingClose();
   SavePersistentState();
   return true;
}

void ContinuePendingClose()
{
   if(!close_pending) return;
   if(!HasOurPosition())
   {
      close_pending = false;
      last_trade_closed_at = TimeCurrent();
      SavePersistentState();
      return;
   }

   datetime now = TimeCurrent();
   if(last_close_attempt_at > 0 && now - last_close_attempt_at < MathMax(1, InpCloseRetrySeconds)) return;
   last_close_attempt_at = now;
   close_attempts++;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      ResetLastError();
      bool submitted = trade.PositionClose(ticket, InpSlippagePoints);
      uint code = trade.ResultRetcode();
      last_close_retcode = code;
      last_close_result = trade.ResultRetcodeDescription();
      if(!submitted || !CloseResultAccepted(code))
      {
         if(code == TRADE_RETCODE_MARKET_CLOSED)
            last_event = "CLOSE PENDING — MARKET CLOSED; the EA will retry automatically";
         else
            last_event = StringFormat("CLOSE PENDING — retry %d; retcode %u %s", close_attempts, code, last_close_result);
         Print(last_event);
      }
      else
      {
         last_event = StringFormat("CLOSE PENDING — request accepted; confirming flat; attempt %d", close_attempts);
      }
   }
   SavePersistentState();
}

void ReportCompletedTrade(ulong exit_deal)
{
   if(active_reported || exit_deal == 0 || !HistoryDealSelect(exit_deal)) return;
   ulong position_id = (ulong)HistoryDealGetInteger(exit_deal, DEAL_POSITION_ID);
   if(active_position_id > 0 && position_id != active_position_id) return;

   double net = CalculatePositionRealised(position_id);
   double exit_price = HistoryDealGetDouble(exit_deal, DEAL_PRICE);
   datetime exit_time = (datetime)HistoryDealGetInteger(exit_deal, DEAL_TIME);
   string reason = close_reason;
   if(reason == "") reason = DealReasonText((ENUM_DEAL_REASON)HistoryDealGetInteger(exit_deal, DEAL_REASON));

   string json = StringFormat(
      "{\"id\":\"%I64u\",\"account\":\"%I64d\",\"symbol\":\"%s\",\"magic\":\"%I64u\",\"ticket\":\"%I64u\",\"positionId\":\"%I64u\",\"side\":\"%s\",\"volume\":%.2f,\"entryTime\":%I64d,\"exitTime\":%I64d,\"entryPrice\":%.5f,\"exitPrice\":%.5f,\"entryScore\":%d,\"oppositeScore\":%d,\"entryRegime\":\"%s\",\"entryReason\":\"%s\",\"exitReason\":\"%s\",\"netProfit\":%.2f,\"mfe\":%.2f,\"mae\":%.2f,\"durationSeconds\":%d,\"closeAttempts\":%d,\"closeTriggerProfit\":%.2f,\"status\":\"CLOSED\"}",
      exit_deal, AccountInfoInteger(ACCOUNT_LOGIN), JsonEscape(trade_symbol), InpMagicNumber, active_ticket, position_id,
      JsonEscape(active_side), active_volume, (long)active_entry_time*1000, (long)exit_time*1000, active_entry_price, exit_price,
      active_entry_score, active_opposite_score, JsonEscape(active_entry_regime), JsonEscape(active_entry_reason), JsonEscape(reason),
      net, active_mfe, active_mae, (int)(exit_time-active_entry_time), close_attempts, close_trigger_profit);
   PostJson("/api/ea/trade", json);

   daily_pnl += net;
   if(net < 0) consecutive_losses++; else if(net > 0) consecutive_losses = 0;
   last_trade_closed_at = exit_time;
   last_reported_exit_deal = exit_deal;
   active_reported = true;
   last_event = StringFormat("Trade confirmed closed: %s net $%.2f; reason %s", active_side, net, reason);
   SendEvent("trade", last_event);
   ResetActiveTradeState();
   SavePersistentState();
}

void DetectUnreportedExternalClose()
{
   if(active_position_id == 0 || active_reported || HasOurPosition()) return;
   if(!HistorySelect(active_entry_time > 60 ? active_entry_time - 60 : 0, TimeCurrent() + 60)) return;
   ulong latest_exit = 0;
   datetime latest_time = 0;
   int deals = HistoryDealsTotal();
   for(int i=0; i<deals; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID) != active_position_id) continue;
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT) continue;
      datetime time = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      if(time >= latest_time) { latest_time = time; latest_exit = deal; }
   }
   if(latest_exit > 0) ReportCompletedTrade(latest_exit);
}

void SendScan(const ScanSnapshot &scan)
{
   string json = StringFormat(
      "{\"id\":\"%I64d-%I64u\",\"account\":\"%I64d\",\"symbol\":\"%s\",\"magic\":\"%I64u\",\"barTime\":%I64d,\"decision\":\"%s\",\"watchDirection\":\"%s\",\"buyScore\":%d,\"sellScore\":%d,\"scoreGap\":%d,\"blockReason\":\"%s\",\"regime\":\"%s\",\"regimeReason\":\"%s\",\"m5Confirmation\":\"%s\",\"atr\":%.5f,\"atrRatio\":%.3f,\"velocityAtr\":%.3f,\"bodyRatio\":%.3f,\"volumeRatio\":%.3f,\"extensionAtr\":%.3f,\"spreadPoints\":%.1f,\"medianSpreadPoints\":%.1f,\"resistance\":%.5f,\"support\":%.5f,\"buyComponents\":\"%s\",\"sellComponents\":\"%s\"}",
      (long)scan.bar_time, InpMagicNumber, AccountInfoInteger(ACCOUNT_LOGIN), JsonEscape(trade_symbol), InpMagicNumber,
      (long)scan.bar_time*1000, JsonEscape(scan.decision), JsonEscape(scan.watch_direction), scan.buy_score, scan.sell_score,
      scan.score_gap, JsonEscape(scan.block_reason), JsonEscape(scan.regime), JsonEscape(scan.regime_reason),
      JsonEscape(scan.m5_confirmation), scan.atr, scan.atr_ratio, scan.velocity, scan.body_ratio, scan.volume_ratio,
      scan.extension_atr, scan.spread_points, scan.median_spread_points, scan.resistance, scan.support,
      JsonEscape(scan.buy_components), JsonEscape(scan.sell_components));
   PostJson("/api/ea/scan", json);
}

void SendHeartbeat()
{
   MqlTick tick;
   SymbolInfoTick(trade_symbol, tick);
   bool position = SelectOurPosition();
   string side = "NONE";
   ulong ticket = 0;
   double volume = 0.0;
   double entry = 0.0;
   double current = 0.0;
   double sl = 0.0;
   double tp = 0.0;
   double profit = 0.0;
   if(position)
   {
      side = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY" : "SELL";
      ticket = (ulong)PositionGetInteger(POSITION_TICKET);
      volume = PositionGetDouble(POSITION_VOLUME);
      entry = PositionGetDouble(POSITION_PRICE_OPEN);
      current = PositionGetDouble(POSITION_PRICE_CURRENT);
      sl = PositionGetDouble(POSITION_SL);
      tp = PositionGetDouble(POSITION_TP);
      profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }

   string json = StringFormat(
      "{\"account\":\"%I64d\",\"symbol\":\"%s\",\"version\":\"1.00\",\"balance\":%.2f,\"equity\":%.2f,\"margin\":%.2f,\"freeMargin\":%.2f,\"marginLevel\":%.2f,\"bid\":%.5f,\"ask\":%.5f,\"spreadPoints\":%.1f,\"medianSpreadPoints\":%.1f,\"terminalConnected\":%s,\"algoAllowed\":%s,\"autonomous\":%s,\"emergency\":%s,\"positionOpen\":%s,\"side\":\"%s\",\"ticket\":\"%I64u\",\"volume\":%.2f,\"entryPrice\":%.5f,\"currentPrice\":%.5f,\"sl\":%.5f,\"tp\":%.5f,\"floatingProfit\":%.2f,\"mfe\":%.2f,\"mae\":%.2f,\"closePending\":%s,\"closeReason\":\"%s\",\"closeAttempts\":%d,\"lastCloseRetcode\":%u,\"lastCloseResult\":\"%s\",\"dailyPnl\":%.2f,\"tradesToday\":%d,\"consecutiveLosses\":%d,\"lastEvent\":\"%s\",\"consumedCommandId\":%I64d,\"lastCommandSucceeded\":%s,\"lastCommandResult\":\"%s\"}",
      AccountInfoInteger(ACCOUNT_LOGIN), JsonEscape(trade_symbol), AccountInfoDouble(ACCOUNT_BALANCE),
      AccountInfoDouble(ACCOUNT_EQUITY), AccountInfoDouble(ACCOUNT_MARGIN), AccountInfoDouble(ACCOUNT_MARGIN_FREE),
      AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), tick.bid, tick.ask, CurrentSpreadPoints(), MedianSpreadPoints(),
      TerminalInfoInteger(TERMINAL_CONNECTED)?"true":"false", MQLInfoInteger(MQL_TRADE_ALLOWED)?"true":"false",
      (remote_autonomous&&!local_paused)?"true":"false", emergency_stopped?"true":"false", position?"true":"false",
      side, ticket, volume, entry, current, sl, tp, profit, active_mfe, active_mae, close_pending?"true":"false",
      JsonEscape(close_reason), close_attempts, last_close_retcode, JsonEscape(last_close_result), daily_pnl, trades_today,
      consecutive_losses, JsonEscape(last_event), last_command_id, last_command_succeeded?"true":"false", JsonEscape(last_command_result));
   PostJson("/api/ea/heartbeat", json);
}

void PollRailway()
{
   string base = TrimTrailingSlash(InpRailwayBaseUrl);
   if(base == "" || StringFind(base, "YOUR-SERVICE") >= 0 || InpBotToken == "CHANGE-ME") return;
   string url = base + "/api/ea/control?token=" + InpBotToken;
   char data[];
   char result[];
   string headers;
   ResetLastError();
   int status = WebRequest("GET", url, "", "", InpWebTimeoutMs, data, 0, result, headers);
   if(status != 200) return;

   string body = CharArrayToString(result);
   long command_id = StringToInteger(ParseLineValue(body, "command_id"));
   string action = ParseLineValue(body, "action");
   remote_autonomous = ParseLineValue(body, "autonomous") == "true";
   manual_news_lock = ParseLineValue(body, "manual_news_lock") == "true";
   bool remote_emergency = ParseLineValue(body, "emergency") == "true";
   if(remote_emergency && !emergency_stopped) ExecuteCommand("EMERGENCY_STOP");

   if(command_id > last_command_id && action != "NONE")
   {
      last_command_succeeded = ExecuteCommand(action);
      last_command_result = last_event;
      last_command_id = command_id;
      SavePersistentState();
   }
}

bool ExecuteCommand(string action)
{
   bool ok = true;
   if(action == "CLOSE_POSITION") ok = RequestClose("MANUAL DASHBOARD CLOSE", CurrentBotProfit());
   else if(action == "PAUSE_EA")
   {
      local_paused = true;
      last_event = "EA paused; open position protection remains active";
   }
   else if(action == "RESUME_EA")
   {
      if(emergency_stopped) { ok = false; last_event = "Reset emergency stop before resuming"; }
      else { local_paused = false; last_event = "EA resumed"; }
   }
   else if(action == "EMERGENCY_STOP")
   {
      emergency_stopped = true;
      local_paused = true;
      if(HasOurPosition()) ok = RequestClose("EMERGENCY STOP", CurrentBotProfit());
      else last_event = "EMERGENCY STOP active; bot is already flat";
   }
   else if(action == "RESET_EMERGENCY")
   {
      if(close_pending) { ok = false; last_event = "Cannot reset while close is pending"; }
      else { emergency_stopped = false; local_paused = false; last_event = "Emergency stop reset"; }
   }
   else
   {
      ok = false;
      last_event = "Unsupported command: " + action;
   }
   last_command_succeeded = ok;
   last_command_result = last_event;
   SendEvent("command", last_event);
   SavePersistentState();
   return ok;
}

bool PostJson(string endpoint, string json)
{
   string base = TrimTrailingSlash(InpRailwayBaseUrl);
   if(base == "" || StringFind(base, "YOUR-SERVICE") >= 0 || InpBotToken == "CHANGE-ME") return false;
   string url = base + endpoint + "?token=" + InpBotToken;
   char post[];
   char result[];
   string headers;
   StringToCharArray(json, post, 0, WHOLE_ARRAY, CP_UTF8);
   int size = ArraySize(post);
   if(size > 0 && post[size-1] == 0) ArrayResize(post, size-1);
   ResetLastError();
   int status = WebRequest("POST", url, "Content-Type: application/json\r\n", InpWebTimeoutMs, post, result, headers);
   if(status < 200 || status >= 300)
   {
      PrintFormat("EVE Momentum POST %s failed. HTTP=%d MQL=%d response=%s", endpoint, status, GetLastError(), CharArrayToString(result));
      return false;
   }
   return true;
}

void SendEvent(string type, string message)
{
   string json = StringFormat("{\"type\":\"%s\",\"message\":\"%s\",\"data\":{\"account\":\"%I64d\",\"symbol\":\"%s\",\"magic\":\"%I64u\"}}",
      JsonEscape(type), JsonEscape(message), AccountInfoInteger(ACCOUNT_LOGIN), JsonEscape(trade_symbol), InpMagicNumber);
   PostJson("/api/ea/event", json);
}

bool SelectOurPosition()
{
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(IsOurSelectedPosition()) return true;
   }
   return false;
}

bool HasOurPosition()
{
   return SelectOurPosition();
}

bool IsOurSelectedPosition()
{
   return PositionGetString(POSITION_SYMBOL) == trade_symbol && (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber;
}

void CaptureOurPosition()
{
   if(!SelectOurPosition()) return;
   active_ticket = (ulong)PositionGetInteger(POSITION_TICKET);
   active_position_id = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   active_entry_time = (datetime)PositionGetInteger(POSITION_TIME);
   active_entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
   active_volume = PositionGetDouble(POSITION_VOLUME);
   active_side = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY" : "SELL";
}

void RecoverOpenPosition()
{
   if(!SelectOurPosition()) return;
   CaptureOurPosition();
   active_mfe = GVGet("mfe", 0.0);
   active_mae = GVGet("mae", 0.0);
   active_volume = GVGet("volume", PositionGetDouble(POSITION_VOLUME));
   active_entry_atr = GVGet("entryatr", 0.0);
   active_entry_score = (int)GVGet("entryscore", 0.0);
   active_opposite_score = (int)GVGet("oppscore", 0.0);
   close_pending = GVGet("closepending", 0.0) > 0.5;
   close_attempts = (int)GVGet("closeattempts", 0.0);
   close_trigger_profit = GVGet("closetrigger", 0.0);
   active_reported = false;
   last_event = close_pending ? "Recovered an open position with CLOSE PENDING" : "Recovered an open bot position";
}

void ResetActiveTradeState()
{
   active_ticket = 0;
   active_position_id = 0;
   active_side = "NONE";
   active_entry_time = 0;
   active_entry_price = 0.0;
   active_volume = 0.0;
   active_entry_atr = 0.0;
   active_entry_score = 0;
   active_opposite_score = 0;
   active_entry_regime = "";
   active_entry_reason = "";
   active_mfe = 0.0;
   active_mae = 0.0;
   active_reported = false;
   close_pending = false;
   close_reason = "";
   close_trigger_profit = 0.0;
   close_requested_at = 0;
   last_close_attempt_at = 0;
   close_attempts = 0;
   last_close_retcode = 0;
   last_close_result = "No close requested";
}

void ResetDailyIfNeeded()
{
   int today = UtcDayKey();
   if(day_key == today) return;
   day_key = today;
   day_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   daily_pnl = 0.0;
   trades_today = 0;
   consecutive_losses = 0;
   emergency_stopped = false;
   local_paused = false;
   SavePersistentState();
}

void RecoverDailyState()
{
   day_key = (int)GVGet("day", 0.0);
   day_start_balance = GVGet("daybalance", AccountInfoDouble(ACCOUNT_BALANCE));
   daily_pnl = GVGet("dailypnl", 0.0);
   trades_today = (int)GVGet("trades", 0.0);
   consecutive_losses = (int)GVGet("losses", 0.0);
   emergency_stopped = GVGet("emergency", 0.0) > 0.5;
   local_paused = GVGet("paused", 0.0) > 0.5;
   last_command_id = (long)GVGet("cmd", 0.0);
   ResetDailyIfNeeded();
}

void SavePersistentState()
{
   GVSet("day", day_key);
   GVSet("daybalance", day_start_balance);
   GVSet("dailypnl", daily_pnl);
   GVSet("trades", trades_today);
   GVSet("losses", consecutive_losses);
   GVSet("emergency", emergency_stopped ? 1.0 : 0.0);
   GVSet("paused", local_paused ? 1.0 : 0.0);
   GVSet("cmd", (double)last_command_id);
   GVSet("positionid", (double)active_position_id);
   GVSet("mfe", active_mfe);
   GVSet("mae", active_mae);
   GVSet("volume", active_volume);
   GVSet("entryatr", active_entry_atr);
   GVSet("entryscore", active_entry_score);
   GVSet("oppscore", active_opposite_score);
   GVSet("closepending", close_pending ? 1.0 : 0.0);
   GVSet("closeattempts", close_attempts);
   GVSet("closetrigger", close_trigger_profit);
}

string PersistentPrefix()
{
   return StringFormat("EMB_%I64d_%I64u_", AccountInfoInteger(ACCOUNT_LOGIN), InpMagicNumber);
}

void GVSet(string key, double value)
{
   GlobalVariableSet(gv_prefix + key, value);
}

double GVGet(string key, double fallback)
{
   string name = gv_prefix + key;
   if(!GlobalVariableCheck(name)) return fallback;
   return GlobalVariableGet(name);
}

int UtcDayKey()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   return dt.year*10000 + dt.mon*100 + dt.day;
}

bool InsideTradingSessionUTC()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   if(InpSessionStartUTC == InpSessionEndUTC) return true;
   if(InpSessionStartUTC < InpSessionEndUTC)
      return dt.hour >= InpSessionStartUTC && dt.hour < InpSessionEndUTC;
   return dt.hour >= InpSessionStartUTC || dt.hour < InpSessionEndUTC;
}

void UpdateSpreadSample()
{
   double spread = CurrentSpreadPoints();
   if(spread <= 0 || spread > 10000) return;
   spread_samples[spread_sample_index] = spread;
   spread_sample_index = (spread_sample_index + 1) % ArraySize(spread_samples);
   if(spread_sample_count < ArraySize(spread_samples)) spread_sample_count++;
}

double CurrentSpreadPoints()
{
   MqlTick tick;
   if(!SymbolInfoTick(trade_symbol, tick)) return 0.0;
   double point = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   return point > 0 ? (tick.ask - tick.bid) / point : 0.0;
}

double MedianSpreadPoints()
{
   if(spread_sample_count < 10) return CurrentSpreadPoints();
   double copy[];
   ArrayResize(copy, spread_sample_count);
   for(int i=0; i<spread_sample_count; i++) copy[i] = spread_samples[i];
   ArraySort(copy);
   int middle = spread_sample_count / 2;
   if(spread_sample_count % 2 == 1) return copy[middle];
   return (copy[middle-1] + copy[middle]) / 2.0;
}

double CurrentBotProfit()
{
   if(!SelectOurPosition()) return 0.0;
   return PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
}

double CalculatePositionRealised(ulong position_id)
{
   if(position_id == 0) return 0.0;
   datetime from = active_entry_time > 3600 ? active_entry_time - 3600 : 0;
   if(!HistorySelect(from, TimeCurrent() + 60)) return 0.0;
   double total = 0.0;
   int deals = HistoryDealsTotal();
   for(int i=0; i<deals; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0 || (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID) != position_id) continue;
      total += HistoryDealGetDouble(deal, DEAL_PROFIT);
      total += HistoryDealGetDouble(deal, DEAL_COMMISSION);
      total += HistoryDealGetDouble(deal, DEAL_SWAP);
      total += HistoryDealGetDouble(deal, DEAL_FEE);
   }
   return total;
}

string DealReasonText(ENUM_DEAL_REASON reason)
{
   if(reason == DEAL_REASON_SL) return "BROKER STOP LOSS";
   if(reason == DEAL_REASON_TP) return "BROKER TAKE PROFIT";
   if(reason == DEAL_REASON_CLIENT) return "MANUAL MT5 CLOSE";
   if(reason == DEAL_REASON_EXPERT) return "EA CLOSE";
   if(reason == DEAL_REASON_SO) return "STOP OUT";
   return EnumToString(reason);
}

bool TradeResultAccepted(uint code)
{
   return code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_PLACED || code == TRADE_RETCODE_DONE_PARTIAL;
}

bool CloseResultAccepted(uint code)
{
   return code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_PLACED || code == TRADE_RETCODE_DONE_PARTIAL || code == TRADE_RETCODE_NO_CHANGES;
}

double NormalizeVolume(double volume)
{
   double min_volume = SymbolInfoDouble(trade_symbol, SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(trade_symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(trade_symbol, SYMBOL_VOLUME_STEP);
   volume = MathMax(min_volume, MathMin(max_volume, volume));
   if(step > 0) volume = MathFloor(volume / step + 0.0000001) * step;
   int digits = 2;
   if(step == 1.0) digits = 0;
   else if(step == 0.1) digits = 1;
   else if(step == 0.001) digits = 3;
   return NormalizeDouble(volume, digits);
}

string ResolveTradeSymbol()
{
   if(InpTradeSymbol != "" && SymbolSelect(InpTradeSymbol, true)) return InpTradeSymbol;
   if(_Symbol != "" && SymbolSelect(_Symbol, true)) return _Symbol;
   int count = SymbolsTotal(false);
   for(int i=0; i<count; i++)
   {
      string name = SymbolName(i, false);
      if(StringFind(name, "XAUUSD") >= 0 || StringFind(name, "GOLD") >= 0)
      {
         if(SymbolSelect(name, true)) return name;
      }
   }
   return "";
}

void AddComponent(string &list, string item)
{
   if(list != "") list += ",";
   list += item;
}

string TrimTrailingSlash(string value)
{
   while(StringLen(value) > 0 && StringSubstr(value, StringLen(value)-1, 1) == "/")
      value = StringSubstr(value, 0, StringLen(value)-1);
   return value;
}

string ParseLineValue(string body, string key)
{
   string marker = key + "=";
   int start = StringFind(body, marker);
   if(start < 0) return "";
   start += StringLen(marker);
   int finish = StringFind(body, "\n", start);
   if(finish < 0) finish = StringLen(body);
   string value = StringSubstr(body, start, finish-start);
   StringTrimLeft(value);
   StringTrimRight(value);
   return value;
}

string JsonEscape(string value)
{
   StringReplace(value, "\\", "\\\\");
   StringReplace(value, "\"", "\\\"");
   StringReplace(value, "\r", " ");
   StringReplace(value, "\n", " ");
   return value;
}

void CreatePanel()
{
   CreateLabel(PANEL_PREFIX+"TITLE", 10, 18, "EVE MOMENTUM BURST v1.00", 12, clrWhite);
   CreateLabel(PANEL_PREFIX+"STATUS", 10, 42, "Loading broker-native M1 data...", 10, clrWhite);
   CreateLabel(PANEL_PREFIX+"SCORE", 10, 62, "BUY 0/11 | SELL 0/11", 10, clrWhite);
   CreateButton(PANEL_PREFIX+"PAUSE", 10, 92, 120, 28, "PAUSE EA", clrDarkOrange);
   CreateButton(PANEL_PREFIX+"CLOSE", 136, 92, 120, 28, "CLOSE BOT", clrSlateGray);
   CreateButton(PANEL_PREFIX+"STOP", 262, 92, 130, 28, "EMERGENCY", clrFireBrick);
}

void UpdatePanel()
{
   string decision = have_scan ? last_scan.decision : "WAIT";
   string regime = have_scan ? last_scan.regime : "LOADING";
   string status = StringFormat("%s | %s | Position %s | P/L $%.2f", decision, regime, HasOurPosition()?"OPEN":"NONE", CurrentBotProfit());
   string scores = have_scan ? StringFormat("BUY %d/11 | SELL %d/11 | %s", last_scan.buy_score, last_scan.sell_score, last_scan.block_reason) : "BUY 0/11 | SELL 0/11";
   ObjectSetString(0, PANEL_PREFIX+"STATUS", OBJPROP_TEXT, status);
   ObjectSetString(0, PANEL_PREFIX+"SCORE", OBJPROP_TEXT, scores);
   ObjectSetString(0, PANEL_PREFIX+"PAUSE", OBJPROP_TEXT, local_paused ? "RESUME EA" : "PAUSE EA");
   ChartRedraw();
}

void CreateLabel(string name, int x, int y, string text, int size, color clr)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void CreateButton(string name, int x, int y, int width, int height, string text, color background)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, background);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, background);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void DeletePanel()
{
   ObjectDelete(0, PANEL_PREFIX+"TITLE");
   ObjectDelete(0, PANEL_PREFIX+"STATUS");
   ObjectDelete(0, PANEL_PREFIX+"SCORE");
   ObjectDelete(0, PANEL_PREFIX+"PAUSE");
   ObjectDelete(0, PANEL_PREFIX+"CLOSE");
   ObjectDelete(0, PANEL_PREFIX+"STOP");
}

void ReleaseHandles()
{
   if(atr_handle != INVALID_HANDLE) IndicatorRelease(atr_handle);
   if(fast_handle != INVALID_HANDLE) IndicatorRelease(fast_handle);
   if(slow_handle != INVALID_HANDLE) IndicatorRelease(slow_handle);
   if(trend_handle != INVALID_HANDLE) IndicatorRelease(trend_handle);
   if(confirm_atr_handle != INVALID_HANDLE) IndicatorRelease(confirm_atr_handle);
   if(confirm_fast_handle != INVALID_HANDLE) IndicatorRelease(confirm_fast_handle);
   if(confirm_slow_handle != INVALID_HANDLE) IndicatorRelease(confirm_slow_handle);
}

#property copyright "EVE Momentum Research"
#property version   "1.10"
#property strict
#property description "Broker-native XAUUSD M1 live momentum burst EA with controlled multi-position execution, basket protection and full telemetry."

#include <Trade/Trade.mqh>

CTrade trade;

input group "Identity"
input string InpTradeSymbol                    = "";                 // Blank = attached chart symbol
input ulong  InpMagicNumber                    = 2207202603;
input string InpOrderComment                   = "EVE-MOMENTUM-V1.1";

input group "Railway connection"
input string InpRailwayBaseUrl                 = "https://YOUR-SERVICE.up.railway.app";
input string InpBotToken                       = "CHANGE-ME";
input int    InpHeartbeatSeconds                = 3;
input int    InpCommandPollSeconds              = 2;
input int    InpTelemetrySeconds                = 2;
input int    InpWebTimeoutMs                    = 3000;

input group "Flipper-mode burst execution"
input bool   InpAutonomousAtStart               = true;
input double InpFixedLotPerPosition             = 0.01;
input bool   InpUseEquityLotScaling             = false;
input double InpEquityPer001Lot                 = 1000.0;
input int    InpInitialBurstPositions           = 3;
input int    InpMaximumPositions                = 5;
input double InpMaximumTotalLots                = 0.05;
input bool   InpUseContinuationStop             = true;
input double InpContinuationSpacingATR          = 0.08;
input double InpAddOnlyAfterProfitMoney         = 0.25;
input int    InpContinuationOrderMaxAgeSeconds  = 15;
input int    InpSlippagePoints                  = 30;
input int    InpEntryCooldownSeconds            = 8;

input group "Live momentum engine"
input ENUM_TIMEFRAMES InpExecutionTimeframe     = PERIOD_M1;
input ENUM_TIMEFRAMES InpConfirmationTimeframe  = PERIOD_M5;
input int    InpATRPeriod                       = 14;
input int    InpFastEMA                         = 9;
input int    InpSlowEMA                         = 21;
input int    InpTrendEMA                        = 50;
input int    InpArmScore                        = 5;
input int    InpNormalEntryScore                = 7;
input int    InpQuietEntryScore                 = 8;
input int    InpHighMomentumEntryScore          = 6;
input int    InpMinimumScoreDifference          = 3;
input double InpVelocity1SecondATRPerSecond     = 0.025;
input double InpVelocity3SecondATRPerSecond     = 0.012;
input double InpAccelerationMultiplier          = 1.12;
input double InpTickRateExpansionMinimum        = 1.18;
input double InpLiveBodyMinimumATR              = 0.12;
input double InpStrongBodyMinimumATR            = 0.24;
input double InpMicroBreakoutBufferATR          = 0.015;
input int    InpMicroBreakoutLookbackSeconds    = 10;
input int    InpMinimumWarmupSeconds             = 12;

input group "Dynamic anti-chase and market quality"
input double InpNormalMaximumExtensionATR       = 1.10;
input double InpAcceleratingMaximumExtensionATR = 2.50;
input double InpDeceleratingMaximumExtensionATR = 0.90;
input int    InpAbsoluteMaximumSpreadPoints     = 90;
input double InpSpreadMedianMultiplier          = 1.80;
input bool   InpUseSessionFilter                = true;
input int    InpSessionStartUTC                 = 6;
input int    InpSessionEndUTC                   = 21;
input bool   InpPreferNewYorkWindow             = true;
input int    InpNewYorkStartUTC                 = 12;
input int    InpNewYorkEndUTC                   = 17;

input group "Per-position protection"
input double InpStopLossATR                     = 0.75;
input double InpTakeProfitATR                   = 0.90;
input double InpBreakEvenTriggerATR             = 0.12;
input double InpTrailingActivationATR           = 0.18;
input double InpBurstTrailATR                   = 0.16;
input double InpNormalTrailATR                  = 0.12;
input double InpDecayTrailATR                   = 0.08;

input group "Basket banking"
input double InpTargetMoneyPer001Lot            = 0.80;
input double InpTrailStartMoneyPer001Lot        = 0.30;
input double InpTrailGivebackMoneyPer001Lot     = 0.10;
input double InpMinimumProfitForDecayClose      = 0.20;
input double InpMaximumBasketLossMoney          = 6.00;
input int    InpMaximumBasketMinutes            = 5;
input int    InpFlipScoreThreshold              = 8;
input int    InpCloseRetrySeconds               = 3;

input group "Daily account protection"
input double InpMaximumDailyLossPercent         = 3.00;
input double InpDailyProfitTargetPercent        = 5.00;
input int    InpMaximumBasketsPerDay            = 50;
input int    InpMaximumConsecutiveLosses        = 5;

#define TICK_BUFFER_SIZE 1600

string PANEL_PREFIX = "EVE_MB_";
string trade_symbol = "";
string gv_prefix = "";

int atr_handle = INVALID_HANDLE;
int fast_handle = INVALID_HANDLE;
int slow_handle = INVALID_HANDLE;
int trend_handle = INVALID_HANDLE;
int confirm_fast_handle = INVALID_HANDLE;
int confirm_slow_handle = INVALID_HANDLE;

ulong tick_times_ms[TICK_BUFFER_SIZE];
double tick_prices[TICK_BUFFER_SIZE];
int tick_buffer_count = 0;
int tick_buffer_index = 0;
ulong first_tick_ms = 0;
ulong last_evaluation_ms = 0;
ulong last_entry_ms = 0;

double spread_samples[300];
int spread_sample_count = 0;
int spread_sample_index = 0;

struct MomentumSnapshot
{
   datetime bar_time;
   ulong snapshot_ms;
   int buy_score;
   int sell_score;
   int score_gap;
   string decision;
   string watch_direction;
   string momentum_state;
   string block_reason;
   string regime;
   string regime_reason;
   string m5_confirmation;
   double atr;
   double atr_ratio;
   double velocity_1s;
   double velocity_3s;
   double velocity_10s;
   double velocity_30s;
   double acceleration;
   double tick_rate_ratio;
   double body_atr;
   double body_ratio;
   double extension_atr;
   double dynamic_extension_limit;
   double spread_points;
   double median_spread_points;
   double micro_high;
   double micro_low;
   bool micro_break_buy;
   bool micro_break_sell;
   bool accelerating_buy;
   bool accelerating_sell;
   string buy_components;
   string sell_components;
};

MomentumSnapshot last_scan;
bool have_scan = false;
string last_sent_scan_signature = "";
datetime last_scan_sent_at = 0;

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
double close_peak_profit = 0.0;
datetime close_requested_at = 0;
datetime last_close_attempt_at = 0;
int close_attempts = 0;
uint last_close_retcode = 0;
string last_close_result = "No close requested";
string pending_flip_side = "NONE";

long basket_id = 0;
datetime basket_started_at = 0;
string basket_side = "NONE";
double basket_entry_atr = 0.0;
int basket_entry_score = 0;
int basket_opposite_score = 0;
string basket_entry_regime = "";
string basket_entry_state = "";
string basket_entry_reason = "";
double peak_basket_profit = 0.0;
double basket_mae = 0.0;
int basket_positions_opened = 0;
int basket_max_concurrent_positions = 0;
datetime last_basket_closed_at = 0;

int day_key = 0;
double day_start_balance = 0.0;
double daily_pnl = 0.0;
int baskets_today = 0;
int consecutive_losses = 0;

int OnInit()
{
   trade_symbol = ResolveTradeSymbol();
   if(trade_symbol == "")
   {
      Print("EVE Momentum v1.10: could not resolve a Gold symbol.");
      return INIT_FAILED;
   }
   if(!SymbolSelect(trade_symbol, true))
   {
      Print("EVE Momentum v1.10: cannot select symbol ", trade_symbol);
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
   confirm_fast_handle = iMA(trade_symbol, InpConfirmationTimeframe, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   confirm_slow_handle = iMA(trade_symbol, InpConfirmationTimeframe, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(atr_handle == INVALID_HANDLE || fast_handle == INVALID_HANDLE || slow_handle == INVALID_HANDLE ||
      trend_handle == INVALID_HANDLE || confirm_fast_handle == INVALID_HANDLE || confirm_slow_handle == INVALID_HANDLE)
   {
      Print("EVE Momentum v1.10: indicator handle creation failed. Error ", GetLastError());
      return INIT_FAILED;
   }

   remote_autonomous = InpAutonomousAtStart;
   gv_prefix = PersistentPrefix();
   RecoverPersistentState();
   CreatePanel();
   EventSetTimer(1);
   last_event = "EA started; warming live tick momentum engine";
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
   MqlTick tick;
   if(!SymbolInfoTick(trade_symbol, tick)) return;
   RecordTick(tick);
   UpdateSpreadSample();
   ProcessLiveMomentum(tick);
   ManageBasket();
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
   ManageBasket();
   UpdatePanel();
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;
   if(sparam == PANEL_PREFIX+"PAUSE") ExecuteCommand(local_paused ? "RESUME_EA" : "PAUSE_EA");
   else if(sparam == PANEL_PREFIX+"CLOSE") ExecuteCommand("CLOSE_BASKET");
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
      if(basket_started_at == 0)
      {
         basket_started_at = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
         basket_id = (long)basket_started_at;
      }
      basket_positions_opened = MathMax(basket_positions_opened, CountBasketEntryDeals());
      basket_max_concurrent_positions = MathMax(basket_max_concurrent_positions, CountOurPositions());
      SavePersistentState();
      return;
   }

   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT)
   {
      if(!PositionIdBelongsToOurBasket(position_id)) return;
      ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal, DEAL_REASON);
      if(CountOurPositions() > 0 && !close_pending)
      {
         string reason_text = "PARTIAL BROKER EXIT - FLATTENING BASKET";
         if(reason == DEAL_REASON_SL) reason_text = "ONE LEG HIT STOP LOSS - FLATTENING BASKET";
         else if(reason == DEAL_REASON_TP) reason_text = "ONE LEG HIT TAKE PROFIT - FLATTENING BASKET";
         RequestBasketClose(reason_text, BasketProfit());
      }
   }
}

void RecordTick(const MqlTick &tick)
{
   ulong now_ms = GetTickCount64();
   double mid = (tick.bid + tick.ask) / 2.0;
   if(mid <= 0) return;
   if(first_tick_ms == 0) first_tick_ms = now_ms;
   tick_times_ms[tick_buffer_index] = now_ms;
   tick_prices[tick_buffer_index] = mid;
   tick_buffer_index = (tick_buffer_index + 1) % TICK_BUFFER_SIZE;
   if(tick_buffer_count < TICK_BUFFER_SIZE) tick_buffer_count++;
}

void ProcessLiveMomentum(const MqlTick &tick)
{
   ulong now_ms = GetTickCount64();
   if(last_evaluation_ms > 0 && now_ms - last_evaluation_ms < 200) return;
   last_evaluation_ms = now_ms;

   MomentumSnapshot scan;
   if(!BuildLiveScan(tick, scan))
   {
      last_event = "Live momentum engine warming up";
      return;
   }

   ApplyOperationalBlocks(scan);
   last_scan = scan;
   have_scan = true;

   string signature = scan.momentum_state + "|" + scan.decision + "|" + IntegerToString(scan.buy_score) + "|" + IntegerToString(scan.sell_score) + "|" + scan.block_reason;
   if(signature != last_sent_scan_signature || TimeCurrent() - last_scan_sent_at >= MathMax(1, InpTelemetrySeconds))
   {
      SendScan(scan);
      last_sent_scan_signature = signature;
      last_scan_sent_at = TimeCurrent();
   }

   if(CountOurPositions() == 0 && CountOurPendingOrders() == 0 && !close_pending)
   {
      if(scan.decision == "BUY" || scan.decision == "SELL") TryStartBurst(scan);
   }
}

bool BuildLiveScan(const MqlTick &tick, MomentumSnapshot &scan)
{
   ulong now_ms = GetTickCount64();
   if(first_tick_ms == 0 || now_ms - first_tick_ms < (ulong)MathMax(3, InpMinimumWarmupSeconds) * 1000) return false;

   MqlRates rates[];
   MqlRates confirm_rates[];
   double atr[];
   double fast[];
   double slow[];
   double trend[];
   double confirm_fast[];
   double confirm_slow[];
   ArraySetAsSeries(rates, true);
   ArraySetAsSeries(confirm_rates, true);
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(trend, true);
   ArraySetAsSeries(confirm_fast, true);
   ArraySetAsSeries(confirm_slow, true);

   if(CopyRates(trade_symbol, InpExecutionTimeframe, 0, 60, rates) < 40) return false;
   if(CopyRates(trade_symbol, InpConfirmationTimeframe, 0, 30, confirm_rates) < 20) return false;
   if(CopyBuffer(atr_handle, 0, 0, 30, atr) < 22) return false;
   if(CopyBuffer(fast_handle, 0, 0, 8, fast) < 5) return false;
   if(CopyBuffer(slow_handle, 0, 0, 8, slow) < 5) return false;
   if(CopyBuffer(trend_handle, 0, 0, 8, trend) < 5) return false;
   if(CopyBuffer(confirm_fast_handle, 0, 0, 8, confirm_fast) < 5) return false;
   if(CopyBuffer(confirm_slow_handle, 0, 0, 8, confirm_slow) < 5) return false;

   double atr_now = atr[0] > 0 ? atr[0] : atr[1];
   if(atr_now <= 0) return false;
   double atr_average = 0.0;
   for(int i=2; i<22; i++) atr_average += atr[i];
   atr_average /= 20.0;
   double atr_ratio = atr_average > 0 ? atr_now / atr_average : 1.0;

   double mid = (tick.bid + tick.ask) / 2.0;
   double p1 = 0.0, p3 = 0.0, p10 = 0.0, p30 = 0.0;
   if(!TickPriceAgo(1, p1) || !TickPriceAgo(3, p3) || !TickPriceAgo(10, p10)) return false;
   if(!TickPriceAgo(30, p30)) p30 = p10;

   double v1 = (mid - p1) / atr_now;
   double v3 = (mid - p3) / atr_now / 3.0;
   double v10 = (mid - p10) / atr_now / 10.0;
   double v30 = (mid - p30) / atr_now / 30.0;

   bool accelerating_buy = v1 >= InpVelocity1SecondATRPerSecond && v3 > 0 && v1 >= v3 * InpAccelerationMultiplier && v3 >= v10 * 0.90;
   bool accelerating_sell = v1 <= -InpVelocity1SecondATRPerSecond && v3 < 0 && MathAbs(v1) >= MathAbs(v3) * InpAccelerationMultiplier && MathAbs(v3) >= MathAbs(v10) * 0.90;
   double acceleration = MathAbs(v1) - MathAbs(v3);

   int ticks3 = CountTicksSince(now_ms > 3000 ? now_ms - 3000 : 0);
   int ticks30 = CountTicksSince(now_ms > 30000 ? now_ms - 30000 : 0);
   double rate3 = ticks3 / 3.0;
   double rate30 = ticks30 / 30.0;
   double tick_rate_ratio = rate30 > 0 ? rate3 / rate30 : 1.0;

   double micro_high = mid;
   double micro_low = mid;
   int micro_count = 0;
   ulong micro_from = now_ms > (ulong)MathMax(3, InpMicroBreakoutLookbackSeconds) * 1000 ? now_ms - (ulong)MathMax(3, InpMicroBreakoutLookbackSeconds) * 1000 : 0;
   ulong micro_to = now_ms > 300 ? now_ms - 300 : now_ms;
   TickWindowStats(micro_from, micro_to, micro_high, micro_low, micro_count);
   bool micro_break_buy = micro_count >= 5 && mid > micro_high + InpMicroBreakoutBufferATR * atr_now;
   bool micro_break_sell = micro_count >= 5 && mid < micro_low - InpMicroBreakoutBufferATR * atr_now;

   double live_range = MathMax(rates[0].high - rates[0].low, SymbolInfoDouble(trade_symbol, SYMBOL_POINT));
   double live_body = MathAbs(mid - rates[0].open);
   double body_atr = live_body / atr_now;
   double body_ratio = live_range > 0 ? live_body / live_range : 0.0;
   double close_location = live_range > 0 ? (mid - rates[0].low) / live_range : 0.5;
   bool live_bull_body = mid > rates[0].open && body_atr >= InpLiveBodyMinimumATR && close_location >= 0.62;
   bool live_bear_body = mid < rates[0].open && body_atr >= InpLiveBodyMinimumATR && close_location <= 0.38;
   bool strong_bull_body = mid > rates[0].open && body_atr >= InpStrongBodyMinimumATR && close_location >= 0.75;
   bool strong_bear_body = mid < rates[0].open && body_atr >= InpStrongBodyMinimumATR && close_location <= 0.25;

   int bull_pressure = 0;
   int bear_pressure = 0;
   for(int i=1; i<=3; i++)
   {
      if(rates[i].close > rates[i].open) bull_pressure++;
      if(rates[i].close < rates[i].open) bear_pressure++;
   }

   bool m5_buy = confirm_fast[0] > confirm_slow[0] && confirm_rates[0].close >= confirm_slow[0];
   bool m5_sell = confirm_fast[0] < confirm_slow[0] && confirm_rates[0].close <= confirm_slow[0];
   string m5_confirmation = "NEUTRAL";
   if(m5_buy && !m5_sell) m5_confirmation = "BUY";
   else if(m5_sell && !m5_buy) m5_confirmation = "SELL";

   int buy_score = 0;
   int sell_score = 0;
   string buy_components = "";
   string sell_components = "";

   if(v1 >= InpVelocity1SecondATRPerSecond) { buy_score++; AddComponent(buy_components, "velocity-1s"); }
   if(v1 <= -InpVelocity1SecondATRPerSecond) { sell_score++; AddComponent(sell_components, "velocity-1s"); }
   if(v3 >= InpVelocity3SecondATRPerSecond) { buy_score++; AddComponent(buy_components, "velocity-3s"); }
   if(v3 <= -InpVelocity3SecondATRPerSecond) { sell_score++; AddComponent(sell_components, "velocity-3s"); }

   if(accelerating_buy) { buy_score += 2; AddComponent(buy_components, "acceleration"); }
   if(accelerating_sell) { sell_score += 2; AddComponent(sell_components, "acceleration"); }

   if(live_bull_body) { buy_score++; AddComponent(buy_components, "live-body"); }
   if(live_bear_body) { sell_score++; AddComponent(sell_components, "live-body"); }
   if(micro_break_buy || strong_bull_body) { buy_score++; AddComponent(buy_components, micro_break_buy ? "micro-break" : "body-expansion"); }
   if(micro_break_sell || strong_bear_body) { sell_score++; AddComponent(sell_components, micro_break_sell ? "micro-break" : "body-expansion"); }

   if(tick_rate_ratio >= InpTickRateExpansionMinimum)
   {
      if(v3 > 0) { buy_score++; AddComponent(buy_components, "tick-expansion"); }
      if(v3 < 0) { sell_score++; AddComponent(sell_components, "tick-expansion"); }
   }

   if(atr_ratio >= 0.95)
   {
      if(v3 > 0) { buy_score++; AddComponent(buy_components, "atr-active"); }
      if(v3 < 0) { sell_score++; AddComponent(sell_components, "atr-active"); }
   }

   if(fast[0] > slow[0] && mid >= trend[0]) { buy_score++; AddComponent(buy_components, "ema-align"); }
   if(fast[0] < slow[0] && mid <= trend[0]) { sell_score++; AddComponent(sell_components, "ema-align"); }

   if(bull_pressure >= 2 || live_bull_body) { buy_score++; AddComponent(buy_components, "directional-pressure"); }
   if(bear_pressure >= 2 || live_bear_body) { sell_score++; AddComponent(sell_components, "directional-pressure"); }

   if(m5_confirmation == "BUY") { buy_score++; AddComponent(buy_components, "m5-support"); }
   if(m5_confirmation == "SELL") { sell_score++; AddComponent(sell_components, "m5-support"); }

   buy_score = MathMin(11, buy_score);
   sell_score = MathMin(11, sell_score);
   int best_score = MathMax(buy_score, sell_score);
   int gap = MathAbs(buy_score - sell_score);
   string best = buy_score >= sell_score ? "BUY" : "SELL";

   double extension_atr = MathAbs(mid - fast[0]) / atr_now;
   double spread = CurrentSpreadPoints();
   double median_spread = MedianSpreadPoints();
   bool spread_chaotic = spread > InpAbsoluteMaximumSpreadPoints || (median_spread > 0 && spread > median_spread * InpSpreadMedianMultiplier);

   string regime = "NORMAL";
   string regime_reason = "Normal live directional conditions";
   if(spread_chaotic)
   {
      regime = "CHAOTIC";
      regime_reason = "Broker spread is abnormal relative to its recent norm";
   }
   else if(atr_ratio < 0.80 || tick_rate_ratio < 0.75)
   {
      regime = "QUIET";
      regime_reason = "ATR or tick arrival rate is compressed";
   }
   else if(tick_rate_ratio >= 1.30 && best_score >= 7 && MathAbs(v1) >= InpVelocity1SecondATRPerSecond)
   {
      regime = "HIGH_MOMENTUM";
      regime_reason = "Live velocity, acceleration and tick activity are expanding together";
   }

   int threshold = InpNormalEntryScore;
   if(regime == "QUIET") threshold = InpQuietEntryScore;
   else if(regime == "HIGH_MOMENTUM") threshold = InpHighMomentumEntryScore;
   if(InpPreferNewYorkWindow && InsideNewYorkWindowUTC() && regime != "QUIET" && regime != "CHAOTIC")
      threshold = MathMax(InpHighMomentumEntryScore, threshold - 1);

   bool best_accelerating = best == "BUY" ? accelerating_buy : accelerating_sell;
   bool burst_break = best == "BUY" ? (micro_break_buy || strong_bull_body) : (micro_break_sell || strong_bear_body);
   double extension_limit = InpNormalMaximumExtensionATR;
   if(best_score >= 9 && best_accelerating && tick_rate_ratio >= 1.10)
      extension_limit = InpAcceleratingMaximumExtensionATR;
   else if(!best_accelerating)
      extension_limit = InpDeceleratingMaximumExtensionATR;

   string state = "IDLE";
   string decision = "WAIT";
   string block = "WAIT - no live momentum burst";

   if(regime == "CHAOTIC")
   {
      state = "CHAOTIC";
      block = "WAIT - spread/feed conditions are abnormal";
   }
   else if(best_score < InpArmScore)
   {
      state = "IDLE";
      block = StringFormat("WAIT - best live score %d/11 is below arm score %d/11", best_score, InpArmScore);
   }
   else if(extension_atr > extension_limit)
   {
      state = "EXHAUSTED";
      block = StringFormat("WAIT - move is %.2f ATR extended while acceleration is insufficient; limit %.2f ATR", extension_atr, extension_limit);
   }
   else if(best_score >= threshold && gap >= InpMinimumScoreDifference && best_accelerating && burst_break)
   {
      state = "BURST";
      decision = best;
      block = StringFormat("%s BURST - live score %d/11, gap %d, extension %.2f ATR", best, best_score, gap, extension_atr);
   }
   else
   {
      state = "ARMED";
      if(best_score < threshold) block = StringFormat("ARMED - %s score %d/11 needs %d/11", best, best_score, threshold);
      else if(gap < InpMinimumScoreDifference) block = StringFormat("ARMED - score gap %d needs %d", gap, InpMinimumScoreDifference);
      else if(!best_accelerating) block = "ARMED - direction is strong but live speed is not accelerating";
      else if(!burst_break) block = "ARMED - waiting for micro-breakout or stronger live candle expansion";
   }

   if(CountOurPositions() > 0)
   {
      string current_side = BasketSideText();
      int same_score = current_side == "BUY" ? buy_score : sell_score;
      int opposite_score = current_side == "BUY" ? sell_score : buy_score;
      string opposite = current_side == "BUY" ? "SELL" : "BUY";
      bool same_accel = current_side == "BUY" ? accelerating_buy : accelerating_sell;
      bool opposite_accel = opposite == "BUY" ? accelerating_buy : accelerating_sell;
      if(opposite_score >= InpFlipScoreThreshold && opposite_score - same_score >= InpMinimumScoreDifference && opposite_accel)
      {
         state = "FLIP";
         decision = "WAIT";
         block = StringFormat("FLIP - %s live score %d/11 has overtaken %s %d/11", opposite, opposite_score, current_side, same_score);
      }
      else if(same_score <= 4 || !same_accel)
      {
         state = "DECAY";
         decision = "WAIT";
         block = StringFormat("DECAY - %s momentum score has fallen to %d/11", current_side, same_score);
      }
   }

   scan.bar_time = rates[0].time;
   scan.snapshot_ms = now_ms;
   scan.buy_score = buy_score;
   scan.sell_score = sell_score;
   scan.score_gap = gap;
   scan.decision = decision;
   scan.watch_direction = best;
   scan.momentum_state = state;
   scan.block_reason = block;
   scan.regime = regime;
   scan.regime_reason = regime_reason;
   scan.m5_confirmation = m5_confirmation;
   scan.atr = atr_now;
   scan.atr_ratio = atr_ratio;
   scan.velocity_1s = v1;
   scan.velocity_3s = v3;
   scan.velocity_10s = v10;
   scan.velocity_30s = v30;
   scan.acceleration = acceleration;
   scan.tick_rate_ratio = tick_rate_ratio;
   scan.body_atr = body_atr;
   scan.body_ratio = body_ratio;
   scan.extension_atr = extension_atr;
   scan.dynamic_extension_limit = extension_limit;
   scan.spread_points = spread;
   scan.median_spread_points = median_spread;
   scan.micro_high = micro_high;
   scan.micro_low = micro_low;
   scan.micro_break_buy = micro_break_buy;
   scan.micro_break_sell = micro_break_sell;
   scan.accelerating_buy = accelerating_buy;
   scan.accelerating_sell = accelerating_sell;
   scan.buy_components = buy_components;
   scan.sell_components = sell_components;
   return true;
}

void ApplyOperationalBlocks(MomentumSnapshot &scan)
{
   ResetDailyIfNeeded();
   if(scan.decision == "WAIT") return;

   if(!remote_autonomous || local_paused)
   {
      scan.decision = "WAIT";
      scan.block_reason = local_paused ? "WAIT - EA is paused" : "WAIT - autonomous mode is disabled";
      return;
   }
   if(emergency_stopped)
   {
      scan.decision = "WAIT";
      scan.block_reason = "WAIT - emergency stop is active";
      return;
   }
   if(manual_news_lock)
   {
      scan.decision = "WAIT";
      scan.block_reason = "WAIT - manual high-impact news lock is active";
      return;
   }
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      scan.decision = "WAIT";
      scan.block_reason = "WAIT - MT5 connection or Algo Trading permission is unavailable";
      return;
   }
   if(CountOurPositions() > 0 || CountOurPendingOrders() > 0 || close_pending)
   {
      scan.decision = "WAIT";
      scan.block_reason = close_pending ? "WAIT - basket close is pending" : "WAIT - bot basket is already active";
      return;
   }
   if(last_entry_ms > 0 && GetTickCount64() - last_entry_ms < (ulong)MathMax(1, InpEntryCooldownSeconds) * 1000)
   {
      scan.decision = "WAIT";
      scan.block_reason = "WAIT - short burst re-entry cooldown is active";
      return;
   }
   if(last_basket_closed_at > 0 && TimeCurrent() - last_basket_closed_at < InpEntryCooldownSeconds)
   {
      scan.decision = "WAIT";
      scan.block_reason = "WAIT - basket close cooldown is active";
      return;
   }
   if(InpUseSessionFilter && !InsideTradingSessionUTC())
   {
      scan.decision = "WAIT";
      scan.block_reason = StringFormat("WAIT - outside configured UTC session %02d:00-%02d:00", InpSessionStartUTC, InpSessionEndUTC);
      return;
   }
   if(baskets_today >= InpMaximumBasketsPerDay)
   {
      scan.decision = "WAIT";
      scan.block_reason = "WAIT - maximum baskets for the UTC day reached";
      return;
   }
   if(consecutive_losses >= InpMaximumConsecutiveLosses)
   {
      scan.decision = "WAIT";
      scan.block_reason = "WAIT - consecutive-loss safety lock is active until next UTC day";
      return;
   }

   double loss_limit = day_start_balance * InpMaximumDailyLossPercent / 100.0;
   double profit_target = day_start_balance * InpDailyProfitTargetPercent / 100.0;
   if(daily_pnl <= -loss_limit)
   {
      scan.decision = "WAIT";
      scan.block_reason = "WAIT - daily loss limit reached";
      return;
   }
   if(daily_pnl >= profit_target)
   {
      scan.decision = "WAIT";
      scan.block_reason = "WAIT - daily profit target reached";
      return;
   }
}

bool TryStartBurst(const MomentumSnapshot &scan)
{
   if(scan.decision != "BUY" && scan.decision != "SELL") return false;
   if(CountOurPositions() > 0 || CountOurPendingOrders() > 0 || close_pending) return false;
   if(!TradingConditionsOkay()) return false;

   ENUM_POSITION_TYPE direction = scan.decision == "BUY" ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   double leg_lot = CalculateLegLot();
   if(leg_lot <= 0) return false;
   int max_by_lots = (int)MathFloor(InpMaximumTotalLots / leg_lot + 0.000001);
   int intended = MathMin(InpInitialBurstPositions, MathMin(InpMaximumPositions, max_by_lots));
   if(intended <= 0)
   {
      last_event = "Entry blocked - configured maximum total lots is below one position";
      return false;
   }

   basket_id = (long)TimeCurrent();
   basket_started_at = TimeCurrent();
   basket_side = scan.decision;
   basket_entry_atr = scan.atr;
   basket_entry_score = scan.decision == "BUY" ? scan.buy_score : scan.sell_score;
   basket_opposite_score = scan.decision == "BUY" ? scan.sell_score : scan.buy_score;
   basket_entry_regime = scan.regime;
   basket_entry_state = scan.momentum_state;
   basket_entry_reason = scan.block_reason;
   peak_basket_profit = 0.0;
   basket_mae = 0.0;
   basket_positions_opened = 0;
   basket_max_concurrent_positions = 0;
   pending_flip_side = "NONE";
   ClearCloseState();

   int opened = 0;
   for(int i=0; i<intended; i++)
   {
      if(BasketLots() + leg_lot > InpMaximumTotalLots + 0.000001) break;
      if(OpenMarketLeg(direction, leg_lot, scan.atr)) opened++;
      else break;
   }

   if(opened <= 0)
   {
      ResetBasketState();
      return false;
   }

   basket_positions_opened = MathMax(basket_positions_opened, opened);
   basket_max_concurrent_positions = MathMax(basket_max_concurrent_positions, CountOurPositions());
   baskets_today++;
   last_entry_ms = GetTickCount64();
   last_event = StringFormat("%s LIVE BURST opened %d position(s), %.2f total lots; score %d/11", basket_side, opened, BasketLots(), basket_entry_score);
   SendEvent("entry", last_event);
   SavePersistentState();
   return true;
}

bool OpenMarketLeg(ENUM_POSITION_TYPE direction, double volume, double atr_value)
{
   MqlTick tick;
   if(!SymbolInfoTick(trade_symbol, tick)) return false;
   double point = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(trade_symbol, SYMBOL_DIGITS);
   double min_distance = BrokerMinimumStopDistancePrice();
   double sl_distance = MathMax(atr_value * InpStopLossATR, min_distance + 3.0 * point);
   double tp_distance = MathMax(atr_value * InpTakeProfitATR, min_distance + 3.0 * point);
   double sl = 0.0;
   double tp = 0.0;
   bool submitted = false;

   if(direction == POSITION_TYPE_BUY)
   {
      sl = NormalizeDouble(tick.ask - sl_distance, digits);
      tp = NormalizeDouble(tick.ask + tp_distance, digits);
      submitted = trade.Buy(NormalizeVolume(volume), trade_symbol, 0.0, sl, tp, InpOrderComment);
   }
   else
   {
      sl = NormalizeDouble(tick.bid + sl_distance, digits);
      tp = NormalizeDouble(tick.bid - tp_distance, digits);
      submitted = trade.Sell(NormalizeVolume(volume), trade_symbol, 0.0, sl, tp, InpOrderComment);
   }

   uint code = trade.ResultRetcode();
   if(!submitted || !TradeResultAccepted(code))
   {
      last_event = StringFormat("Burst leg rejected: retcode %u %s", code, trade.ResultRetcodeDescription());
      SendEvent("entry-error", last_event);
      return false;
   }
   return true;
}

void ManageBasket()
{
   if(close_pending)
   {
      ContinuePendingClose();
      return;
   }

   int positions = CountOurPositions();
   int orders = CountOurPendingOrders();
   if(positions == 0)
   {
      if(orders > 0) CancelPendingOrders();
      if(basket_started_at > 0 && CountOurPendingOrders() == 0) FinaliseBasketClose("Basket closed by broker, stop, TP or manual MT5 action");
      return;
   }

   if(basket_started_at == 0)
   {
      basket_started_at = EarliestBasketPositionTime();
      if(basket_started_at <= 0) basket_started_at = TimeCurrent();
      basket_id = (long)basket_started_at;
      basket_side = BasketSideText();
   }

   double profit = BasketProfit();
   peak_basket_profit = MathMax(peak_basket_profit, profit);
   basket_mae = MathMin(basket_mae, profit);
   basket_max_concurrent_positions = MathMax(basket_max_concurrent_positions, positions);

   if(emergency_stopped)
   {
      RequestBasketClose("EMERGENCY STOP", profit);
      return;
   }
   if(InpMaximumBasketLossMoney > 0 && profit <= -MathAbs(InpMaximumBasketLossMoney))
   {
      RequestBasketClose("MAXIMUM BASKET LOSS", profit);
      return;
   }

   double target = CurrentBasketTargetMoney();
   double trail_start = CurrentBasketTrailStartMoney();
   double giveback = CurrentBasketGivebackMoney();
   if(target > 0 && profit >= target)
   {
      RequestBasketClose("ADAPTIVE BASKET MONEY TARGET", profit);
      return;
   }
   if(trail_start > 0 && giveback > 0 && peak_basket_profit >= trail_start && profit <= peak_basket_profit - giveback)
   {
      RequestBasketClose("FAST BASKET PROFIT TRAIL", profit);
      return;
   }
   if(InpMaximumBasketMinutes > 0 && TimeCurrent() - basket_started_at >= InpMaximumBasketMinutes * 60)
   {
      RequestBasketClose("MAXIMUM BASKET DURATION", profit);
      return;
   }

   if(have_scan)
   {
      string current_side = BasketSideText();
      int same_score = current_side == "BUY" ? last_scan.buy_score : last_scan.sell_score;
      int opposite_score = current_side == "BUY" ? last_scan.sell_score : last_scan.buy_score;
      string opposite = current_side == "BUY" ? "SELL" : "BUY";
      bool opposite_accel = opposite == "BUY" ? last_scan.accelerating_buy : last_scan.accelerating_sell;

      if(opposite_score >= InpFlipScoreThreshold && opposite_score - same_score >= InpMinimumScoreDifference && opposite_accel)
      {
         pending_flip_side = opposite;
         RequestBasketClose("LIVE MOMENTUM FLIP TO " + opposite, profit);
         return;
      }
      if(profit >= InpMinimumProfitForDecayClose && (last_scan.momentum_state == "DECAY" || same_score <= 4))
      {
         RequestBasketClose("MOMENTUM DECAY PROFIT SECURED", profit);
         return;
      }
   }

   TrailAllPositions();
   ManageContinuationOrder();
   SavePersistentState();
}

void ManageContinuationOrder()
{
   if(!InpUseContinuationStop || close_pending || local_paused || emergency_stopped)
   {
      CancelPendingOrders();
      return;
   }
   int positions = CountOurPositions();
   if(positions <= 0 || positions >= InpMaximumPositions || BasketLots() >= InpMaximumTotalLots - 0.000001)
   {
      CancelPendingOrders();
      return;
   }
   if(BasketProfit() < InpAddOnlyAfterProfitMoney)
   {
      CancelPendingOrders();
      return;
   }
   if(!have_scan || last_scan.momentum_state != "BURST" || last_scan.watch_direction != BasketSideText())
   {
      CancelPendingOrders();
      return;
   }

   if(CountOurPendingOrders() > 0)
   {
      if(PendingOrdersStale()) CancelPendingOrders();
      return;
   }
   EnsureContinuationOrder();
}

void EnsureContinuationOrder()
{
   if(CountOurPendingOrders() > 0 || CountOurPositions() <= 0) return;
   if(!TradingConditionsOkay()) return;
   double leg_lot = CalculateLegLot();
   if(leg_lot <= 0 || BasketLots() + leg_lot > InpMaximumTotalLots + 0.000001) return;

   ENUM_POSITION_TYPE direction = BasketDirection();
   if(direction != POSITION_TYPE_BUY && direction != POSITION_TYPE_SELL) return;
   MqlTick tick;
   if(!SymbolInfoTick(trade_symbol, tick)) return;
   double atr_value = basket_entry_atr > 0 ? basket_entry_atr : (have_scan ? last_scan.atr : 0.0);
   if(atr_value <= 0) return;

   double point = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   double min_distance = BrokerMinimumStopDistancePrice();
   double spacing = MathMax(atr_value * InpContinuationSpacingATR, min_distance + 3.0 * point);
   double price = direction == POSITION_TYPE_BUY ? tick.ask + spacing : tick.bid - spacing;
   double sl_distance = MathMax(atr_value * InpStopLossATR, min_distance + 3.0 * point);
   double tp_distance = MathMax(atr_value * InpTakeProfitATR, min_distance + 3.0 * point);
   double sl = direction == POSITION_TYPE_BUY ? price - sl_distance : price + sl_distance;
   double tp = direction == POSITION_TYPE_BUY ? price + tp_distance : price - tp_distance;
   price = NormalizePrice(price);
   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);

   bool submitted = direction == POSITION_TYPE_BUY
      ? trade.BuyStop(leg_lot, price, trade_symbol, sl, tp, ORDER_TIME_GTC, 0, InpOrderComment)
      : trade.SellStop(leg_lot, price, trade_symbol, sl, tp, ORDER_TIME_GTC, 0, InpOrderComment);
   uint code = trade.ResultRetcode();
   if(!submitted || !TradeResultAccepted(code))
   {
      last_event = StringFormat("Continuation stop rejected: %u %s", code, trade.ResultRetcodeDescription());
      Print(last_event);
   }
   else
   {
      last_event = StringFormat("Continuation %s STOP placed at %.2f; only adds while basket is profitable", basket_side, price);
   }
}

bool PendingOrdersStale()
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket) || !IsOurSelectedOrder()) continue;
      datetime setup = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      if(setup > 0 && TimeCurrent() - setup >= InpContinuationOrderMaxAgeSeconds) return true;
   }
   return false;
}

void TrailAllPositions()
{
   if(!have_scan) return;
   double atr_now = last_scan.atr > 0 ? last_scan.atr : basket_entry_atr;
   if(atr_now <= 0) return;
   string side = BasketSideText();
   int same_score = side == "BUY" ? last_scan.buy_score : last_scan.sell_score;
   double trail_mult = InpNormalTrailATR;
   if(last_scan.momentum_state == "BURST" && same_score >= 7) trail_mult = InpBurstTrailATR;
   else if(last_scan.momentum_state == "DECAY" || same_score <= 4) trail_mult = InpDecayTrailATR;

   double point = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   double minimum_distance = BrokerMinimumStopDistancePrice();
   int digits = (int)SymbolInfoInteger(trade_symbol, SYMBOL_DIGITS);
   MqlTick tick;
   if(!SymbolInfoTick(trade_symbol, tick)) return;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double current = type == POSITION_TYPE_BUY ? tick.bid : tick.ask;
      double current_sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double favourable = type == POSITION_TYPE_BUY ? current - entry : entry - current;
      double desired_sl = current_sl;

      if(favourable >= atr_now * InpBreakEvenTriggerATR)
      {
         double cost_buffer = (CurrentSpreadPoints() + 4.0) * point;
         double break_even = type == POSITION_TYPE_BUY ? entry + cost_buffer : entry - cost_buffer;
         if(type == POSITION_TYPE_BUY && (desired_sl == 0 || break_even > desired_sl)) desired_sl = break_even;
         if(type == POSITION_TYPE_SELL && (desired_sl == 0 || break_even < desired_sl)) desired_sl = break_even;
      }

      if(favourable >= atr_now * InpTrailingActivationATR)
      {
         double candidate = type == POSITION_TYPE_BUY ? current - atr_now * trail_mult : current + atr_now * trail_mult;
         if(type == POSITION_TYPE_BUY && (desired_sl == 0 || candidate > desired_sl)) desired_sl = candidate;
         if(type == POSITION_TYPE_SELL && (desired_sl == 0 || candidate < desired_sl)) desired_sl = candidate;
      }

      if(desired_sl <= 0) continue;
      if(type == POSITION_TYPE_BUY) desired_sl = MathMin(desired_sl, current - minimum_distance);
      else desired_sl = MathMax(desired_sl, current + minimum_distance);
      desired_sl = NormalizeDouble(desired_sl, digits);
      bool tighter = type == POSITION_TYPE_BUY ? (current_sl == 0 || desired_sl > current_sl + point) : (current_sl == 0 || desired_sl < current_sl - point);
      if(tighter)
      {
         if(!trade.PositionModify(ticket, desired_sl, tp) || !TradeResultAccepted(trade.ResultRetcode()))
            PrintFormat("Momentum trail update failed for %I64u: %u %s", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      }
   }
}

bool RequestBasketClose(string reason, double trigger_profit)
{
   if(!close_pending && CountOurPositions() == 0 && CountOurPendingOrders() == 0)
   {
      last_event = reason + "; basket already flat";
      return true;
   }
   if(!close_pending)
   {
      close_pending = true;
      close_reason = reason;
      close_trigger_profit = trigger_profit;
      close_peak_profit = peak_basket_profit;
      close_requested_at = TimeCurrent();
      last_close_attempt_at = 0;
      close_attempts = 0;
      last_close_retcode = 0;
      last_close_result = "Close requested; awaiting broker confirmation";
      CancelPendingOrders();
      last_event = StringFormat("CLOSE PENDING - %s; trigger $%.2f; peak $%.2f", reason, trigger_profit, close_peak_profit);
      SendEvent("close", last_event);
      SavePersistentState();
   }
   ContinuePendingClose();
   return true;
}

void ContinuePendingClose()
{
   if(!close_pending) return;
   if(CountOurPositions() == 0 && CountOurPendingOrders() == 0)
   {
      FinaliseBasketClose(close_reason == "" ? "CLOSE CONFIRMED" : close_reason);
      return;
   }

   datetime now = TimeCurrent();
   if(last_close_attempt_at > 0 && now - last_close_attempt_at < MathMax(1, InpCloseRetrySeconds)) return;
   last_close_attempt_at = now;
   close_attempts++;

   bool all_ok = CancelPendingOrders();
   uint failure_code = last_close_retcode;
   string failure_text = last_close_result;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      ResetLastError();
      bool submitted = trade.PositionClose(ticket, InpSlippagePoints);
      uint code = trade.ResultRetcode();
      string description = trade.ResultRetcodeDescription();
      last_close_retcode = code;
      last_close_result = description;
      if(!submitted || !CloseResultAccepted(code))
      {
         all_ok = false;
         failure_code = code;
         failure_text = description;
         PrintFormat("Basket close attempt %d failed for %I64u: %u %s, MQL error %d", close_attempts, ticket, code, description, GetLastError());
      }
   }

   if(CountOurPositions() == 0 && CountOurPendingOrders() == 0)
   {
      FinaliseBasketClose(close_reason == "" ? "CLOSE CONFIRMED" : close_reason);
      return;
   }

   if(!all_ok)
   {
      last_close_retcode = failure_code;
      last_close_result = failure_text;
      if(failure_code == TRADE_RETCODE_MARKET_CLOSED)
         last_event = StringFormat("CLOSE PENDING - MARKET CLOSED; automatic retry; %d position(s) remain", CountOurPositions());
      else
         last_event = StringFormat("CLOSE PENDING - retry %d; %d position(s), %d order(s) remain; %s", close_attempts, CountOurPositions(), CountOurPendingOrders(), failure_text);
   }
   else
      last_event = StringFormat("CLOSE PENDING - broker requests accepted; confirming flat; %d position(s) remain", CountOurPositions());
   SavePersistentState();
}

void FinaliseBasketClose(string fallback_reason)
{
   if(basket_started_at <= 0)
   {
      ClearCloseState();
      return;
   }

   double realised = CalculateBasketRealisedProfit();
   double avg_entry = CalculateBasketAverageDealPrice(true);
   double avg_exit = CalculateBasketAverageDealPrice(false);
   int entry_legs = CountBasketEntryDeals();
   datetime exit_time = LatestBasketExitTime();
   if(exit_time <= 0) exit_time = TimeCurrent();
   string reason = close_reason == "" ? fallback_reason : close_reason;
   double total_volume = CalculateBasketEntryVolume();
   int duration = (int)(exit_time - basket_started_at);

   string json = StringFormat(
      "{\"id\":\"%I64d-%I64u\",\"account\":\"%I64d\",\"symbol\":\"%s\",\"magic\":\"%I64u\",\"side\":\"%s\",\"volume\":%.2f,\"positionsOpened\":%d,\"maxConcurrentPositions\":%d,\"entryTime\":%I64d,\"exitTime\":%I64d,\"entryPrice\":%.5f,\"exitPrice\":%.5f,\"entryScore\":%d,\"oppositeScore\":%d,\"entryRegime\":\"%s\",\"entryState\":\"%s\",\"entryReason\":\"%s\",\"exitReason\":\"%s\",\"netProfit\":%.2f,\"mfe\":%.2f,\"mae\":%.2f,\"durationSeconds\":%d,\"closeAttempts\":%d,\"closeTriggerProfit\":%.2f,\"peakBasketProfit\":%.2f,\"targetMoney\":%.2f,\"trailStartMoney\":%.2f,\"givebackMoney\":%.2f,\"status\":\"CLOSED\"}",
      basket_id, InpMagicNumber, AccountInfoInteger(ACCOUNT_LOGIN), JsonEscape(trade_symbol), InpMagicNumber,
      JsonEscape(basket_side), total_volume, entry_legs, basket_max_concurrent_positions,
      (long)basket_started_at * 1000, (long)exit_time * 1000, avg_entry, avg_exit,
      basket_entry_score, basket_opposite_score, JsonEscape(basket_entry_regime), JsonEscape(basket_entry_state),
      JsonEscape(basket_entry_reason), JsonEscape(reason), realised, peak_basket_profit, basket_mae, duration,
      close_attempts, close_trigger_profit, close_peak_profit > 0 ? close_peak_profit : peak_basket_profit,
      MoneyForLots(total_volume, InpTargetMoneyPer001Lot), MoneyForLots(total_volume, InpTrailStartMoneyPer001Lot),
      MoneyForLots(total_volume, InpTrailGivebackMoneyPer001Lot));
   PostJson("/api/ea/trade", json);

   daily_pnl += realised;
   if(realised < 0) consecutive_losses++;
   else if(realised > 0) consecutive_losses = 0;
   last_basket_closed_at = exit_time;
   last_event = StringFormat("Basket confirmed flat: %s net $%.2f; %d legs; reason %s", basket_side, realised, entry_legs, reason);
   SendEvent("trade", last_event);

   string flip = pending_flip_side;
   ResetBasketState();
   pending_flip_side = flip;
   SavePersistentState();
}

void ResetBasketState()
{
   basket_id = 0;
   basket_started_at = 0;
   basket_side = "NONE";
   basket_entry_atr = 0.0;
   basket_entry_score = 0;
   basket_opposite_score = 0;
   basket_entry_regime = "";
   basket_entry_state = "";
   basket_entry_reason = "";
   peak_basket_profit = 0.0;
   basket_mae = 0.0;
   basket_positions_opened = 0;
   basket_max_concurrent_positions = 0;
   ClearCloseState();
}

void ClearCloseState()
{
   close_pending = false;
   close_reason = "";
   close_trigger_profit = 0.0;
   close_peak_profit = 0.0;
   close_requested_at = 0;
   last_close_attempt_at = 0;
   close_attempts = 0;
   last_close_retcode = 0;
   last_close_result = "No close pending";
}

bool CancelPendingOrders()
{
   bool all_removed = true;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket) || !IsOurSelectedOrder()) continue;
      ResetLastError();
      bool submitted = trade.OrderDelete(ticket);
      uint code = trade.ResultRetcode();
      if(!submitted || !DeleteResultAccepted(code))
      {
         all_removed = false;
         last_close_retcode = code;
         last_close_result = trade.ResultRetcodeDescription();
         PrintFormat("Pending order delete failed for %I64u: %u %s", ticket, code, trade.ResultRetcodeDescription());
      }
   }
   return all_removed && CountOurPendingOrders() == 0;
}

bool TradingConditionsOkay()
{
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) { last_event = "MT5 disconnected"; return false; }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) { last_event = "AutoTrading not allowed"; return false; }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) { last_event = "EA trading permission disabled"; return false; }
   MqlTick tick;
   if(!SymbolInfoTick(trade_symbol, tick)) { last_event = "No symbol tick"; return false; }
   double spread = CurrentSpreadPoints();
   double median = MedianSpreadPoints();
   if(spread > InpAbsoluteMaximumSpreadPoints || (median > 0 && spread > median * InpSpreadMedianMultiplier))
   {
      last_event = StringFormat("Spread too high: %.1f points versus %.1f median", spread, median);
      return false;
   }
   return true;
}

int CountOurPositions()
{
   int count = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(IsOurSelectedPosition()) count++;
   }
   return count;
}

int CountOurPendingOrders()
{
   int count = 0;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket)) continue;
      if(IsOurSelectedOrder()) count++;
   }
   return count;
}

bool IsOurSelectedPosition()
{
   return PositionGetString(POSITION_SYMBOL) == trade_symbol && (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber;
}

bool IsOurSelectedOrder()
{
   return OrderGetString(ORDER_SYMBOL) == trade_symbol && (ulong)OrderGetInteger(ORDER_MAGIC) == InpMagicNumber;
}

ENUM_POSITION_TYPE BasketDirection()
{
   int buys = 0;
   int sells = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) buys++;
      else sells++;
   }
   if(buys > 0 && sells == 0) return POSITION_TYPE_BUY;
   if(sells > 0 && buys == 0) return POSITION_TYPE_SELL;
   return (ENUM_POSITION_TYPE)-1;
}

string BasketSideText()
{
   ENUM_POSITION_TYPE direction = BasketDirection();
   if(direction == POSITION_TYPE_BUY) return "BUY";
   if(direction == POSITION_TYPE_SELL) return "SELL";
   return basket_side;
}

double BasketProfit()
{
   double total = 0.0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      total += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return total;
}

double BasketLots()
{
   double total = 0.0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      total += PositionGetDouble(POSITION_VOLUME);
   }
   return total;
}

double AverageBasketEntry()
{
   double weighted = 0.0;
   double lots = 0.0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      double volume = PositionGetDouble(POSITION_VOLUME);
      weighted += PositionGetDouble(POSITION_PRICE_OPEN) * volume;
      lots += volume;
   }
   return lots > 0 ? weighted / lots : 0.0;
}

double BasketProtectedStop()
{
   double result = 0.0;
   ENUM_POSITION_TYPE direction = BasketDirection();
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      double sl = PositionGetDouble(POSITION_SL);
      if(sl <= 0) continue;
      if(result == 0) result = sl;
      else if(direction == POSITION_TYPE_BUY) result = MathMin(result, sl);
      else if(direction == POSITION_TYPE_SELL) result = MathMax(result, sl);
   }
   return result;
}

datetime EarliestBasketPositionTime()
{
   datetime earliest = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      datetime value = (datetime)PositionGetInteger(POSITION_TIME);
      if(earliest == 0 || value < earliest) earliest = value;
   }
   return earliest;
}

bool PositionIdBelongsToOurBasket(ulong position_id)
{
   if(position_id == 0) return false;
   datetime from = basket_started_at > 120 ? basket_started_at - 120 : 0;
   if(!HistorySelect(from, TimeCurrent() + 60)) return false;
   int deals = HistoryDealsTotal();
   for(int i=0; i<deals; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID) != position_id) continue;
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
      if((entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_INOUT) && (ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) == InpMagicNumber)
         return true;
   }
   return false;
}

void BuildBasketPositionIds(ulong &ids[])
{
   ArrayResize(ids, 0);
   if(basket_started_at <= 0) return;
   datetime from = basket_started_at > 120 ? basket_started_at - 120 : 0;
   if(!HistorySelect(from, TimeCurrent() + 60)) return;
   int deals = HistoryDealsTotal();
   for(int i=0; i<deals; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0 || HistoryDealGetString(deal, DEAL_SYMBOL) != trade_symbol) continue;
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagicNumber) continue;
      datetime time = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      if(time < basket_started_at - 2) continue;
      ulong id = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      AddUniqueUlong(ids, id);
   }
}

bool ArrayContainsUlong(ulong &values[], ulong value)
{
   for(int i=0; i<ArraySize(values); i++) if(values[i] == value) return true;
   return false;
}

void AddUniqueUlong(ulong &values[], ulong value)
{
   if(value == 0 || ArrayContainsUlong(values, value)) return;
   int size = ArraySize(values);
   ArrayResize(values, size + 1);
   values[size] = value;
}

double CalculateBasketRealisedProfit()
{
   ulong ids[];
   BuildBasketPositionIds(ids);
   if(ArraySize(ids) == 0) return 0.0;
   datetime from = basket_started_at > 120 ? basket_started_at - 120 : 0;
   if(!HistorySelect(from, TimeCurrent() + 60)) return 0.0;
   double total = 0.0;
   int deals = HistoryDealsTotal();
   for(int i=0; i<deals; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      ulong position_id = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      if(!ArrayContainsUlong(ids, position_id)) continue;
      total += HistoryDealGetDouble(deal, DEAL_PROFIT);
      total += HistoryDealGetDouble(deal, DEAL_COMMISSION);
      total += HistoryDealGetDouble(deal, DEAL_SWAP);
      total += HistoryDealGetDouble(deal, DEAL_FEE);
   }
   return total;
}

double CalculateBasketAverageDealPrice(bool entries)
{
   ulong ids[];
   BuildBasketPositionIds(ids);
   if(ArraySize(ids) == 0) return 0.0;
   datetime from = basket_started_at > 120 ? basket_started_at - 120 : 0;
   if(!HistorySelect(from, TimeCurrent() + 60)) return 0.0;
   double weighted = 0.0;
   double volume = 0.0;
   int deals = HistoryDealsTotal();
   for(int i=0; i<deals; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      ulong position_id = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      if(!ArrayContainsUlong(ids, position_id)) continue;
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
      bool is_entry = entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_INOUT;
      bool is_exit = entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT;
      if((entries && !is_entry) || (!entries && !is_exit)) continue;
      double deal_volume = HistoryDealGetDouble(deal, DEAL_VOLUME);
      weighted += HistoryDealGetDouble(deal, DEAL_PRICE) * deal_volume;
      volume += deal_volume;
   }
   return volume > 0 ? weighted / volume : 0.0;
}

double CalculateBasketEntryVolume()
{
   ulong ids[];
   BuildBasketPositionIds(ids);
   if(ArraySize(ids) == 0) return 0.0;
   datetime from = basket_started_at > 120 ? basket_started_at - 120 : 0;
   if(!HistorySelect(from, TimeCurrent() + 60)) return 0.0;
   double volume = 0.0;
   int deals = HistoryDealsTotal();
   for(int i=0; i<deals; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0 || !ArrayContainsUlong(ids, (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID))) continue;
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_INOUT) volume += HistoryDealGetDouble(deal, DEAL_VOLUME);
   }
   return volume;
}

int CountBasketEntryDeals()
{
   ulong ids[];
   BuildBasketPositionIds(ids);
   return ArraySize(ids);
}

datetime LatestBasketExitTime()
{
   ulong ids[];
   BuildBasketPositionIds(ids);
   if(ArraySize(ids) == 0) return 0;
   datetime from = basket_started_at > 120 ? basket_started_at - 120 : 0;
   if(!HistorySelect(from, TimeCurrent() + 60)) return 0;
   datetime latest = 0;
   int deals = HistoryDealsTotal();
   for(int i=0; i<deals; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0 || !ArrayContainsUlong(ids, (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID))) continue;
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT) continue;
      datetime time = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      if(time > latest) latest = time;
   }
   return latest;
}

void SendScan(const MomentumSnapshot &scan)
{
   string json = StringFormat(
      "{\"id\":\"%I64d-%I64u-%I64u\",\"account\":\"%I64d\",\"symbol\":\"%s\",\"magic\":\"%I64u\",\"barTime\":%I64d,\"snapshotMs\":%I64u,\"decision\":\"%s\",\"watchDirection\":\"%s\",\"momentumState\":\"%s\",\"buyScore\":%d,\"sellScore\":%d,\"scoreGap\":%d,\"blockReason\":\"%s\",\"regime\":\"%s\",\"regimeReason\":\"%s\",\"m5Confirmation\":\"%s\",\"atr\":%.5f,\"atrRatio\":%.3f,\"velocity1s\":%.5f,\"velocity3s\":%.5f,\"velocity10s\":%.5f,\"velocity30s\":%.5f,\"acceleration\":%.5f,\"tickRateRatio\":%.3f,\"bodyAtr\":%.3f,\"bodyRatio\":%.3f,\"extensionAtr\":%.3f,\"extensionLimitAtr\":%.3f,\"spreadPoints\":%.1f,\"medianSpreadPoints\":%.1f,\"microHigh\":%.5f,\"microLow\":%.5f,\"microBreakBuy\":%s,\"microBreakSell\":%s,\"buyComponents\":\"%s\",\"sellComponents\":\"%s\"}",
      (long)scan.bar_time, InpMagicNumber, scan.snapshot_ms, AccountInfoInteger(ACCOUNT_LOGIN), JsonEscape(trade_symbol), InpMagicNumber,
      (long)scan.bar_time * 1000, scan.snapshot_ms, JsonEscape(scan.decision), JsonEscape(scan.watch_direction), JsonEscape(scan.momentum_state),
      scan.buy_score, scan.sell_score, scan.score_gap, JsonEscape(scan.block_reason), JsonEscape(scan.regime), JsonEscape(scan.regime_reason),
      JsonEscape(scan.m5_confirmation), scan.atr, scan.atr_ratio, scan.velocity_1s, scan.velocity_3s, scan.velocity_10s, scan.velocity_30s,
      scan.acceleration, scan.tick_rate_ratio, scan.body_atr, scan.body_ratio, scan.extension_atr, scan.dynamic_extension_limit,
      scan.spread_points, scan.median_spread_points, scan.micro_high, scan.micro_low,
      scan.micro_break_buy ? "true" : "false", scan.micro_break_sell ? "true" : "false",
      JsonEscape(scan.buy_components), JsonEscape(scan.sell_components));
   PostJson("/api/ea/scan", json);
}

void SendHeartbeat()
{
   MqlTick tick;
   SymbolInfoTick(trade_symbol, tick);
   int positions = CountOurPositions();
   int pending = CountOurPendingOrders();
   string side = BasketSideText();
   double lots = BasketLots();
   double average = AverageBasketEntry();
   double current = side == "BUY" ? tick.bid : side == "SELL" ? tick.ask : (tick.bid + tick.ask) / 2.0;
   double profit = BasketProfit();
   double target = CurrentBasketTargetMoney();
   double trail_start = CurrentBasketTrailStartMoney();
   double giveback = CurrentBasketGivebackMoney();

   string json = StringFormat(
      "{\"account\":\"%I64d\",\"symbol\":\"%s\",\"version\":\"1.10\",\"balance\":%.2f,\"equity\":%.2f,\"margin\":%.2f,\"freeMargin\":%.2f,\"marginLevel\":%.2f,\"bid\":%.5f,\"ask\":%.5f,\"spreadPoints\":%.1f,\"medianSpreadPoints\":%.1f,\"terminalConnected\":%s,\"algoAllowed\":%s,\"autonomous\":%s,\"emergency\":%s,\"positionOpen\":%s,\"positionCount\":%d,\"pendingCount\":%d,\"side\":\"%s\",\"totalLots\":%.2f,\"averageEntry\":%.5f,\"currentPrice\":%.5f,\"protectedStop\":%.5f,\"floatingProfit\":%.2f,\"peakBasketProfit\":%.2f,\"basketMae\":%.2f,\"basketTargetMoney\":%.2f,\"basketTrailStartMoney\":%.2f,\"basketGivebackMoney\":%.2f,\"basketStartedAt\":%I64d,\"positionsOpened\":%d,\"maxConcurrentPositions\":%d,\"closePending\":%s,\"closeReason\":\"%s\",\"closeAttempts\":%d,\"lastCloseRetcode\":%u,\"lastCloseResult\":\"%s\",\"dailyPnl\":%.2f,\"basketsToday\":%d,\"consecutiveLosses\":%d,\"momentumState\":\"%s\",\"liveDirection\":\"%s\",\"buyScore\":%d,\"sellScore\":%d,\"velocity1s\":%.5f,\"velocity3s\":%.5f,\"velocity10s\":%.5f,\"tickRateRatio\":%.3f,\"acceleration\":%.5f,\"bodyAtr\":%.3f,\"extensionAtr\":%.3f,\"lastEvent\":\"%s\",\"consumedCommandId\":%I64d,\"lastCommandSucceeded\":%s,\"lastCommandResult\":\"%s\"}",
      AccountInfoInteger(ACCOUNT_LOGIN), JsonEscape(trade_symbol), AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY),
      AccountInfoDouble(ACCOUNT_MARGIN), AccountInfoDouble(ACCOUNT_MARGIN_FREE), AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), tick.bid, tick.ask,
      CurrentSpreadPoints(), MedianSpreadPoints(), TerminalInfoInteger(TERMINAL_CONNECTED) ? "true" : "false",
      MQLInfoInteger(MQL_TRADE_ALLOWED) ? "true" : "false", (remote_autonomous && !local_paused) ? "true" : "false",
      emergency_stopped ? "true" : "false", positions > 0 ? "true" : "false", positions, pending, JsonEscape(side), lots, average,
      current, BasketProtectedStop(), profit, peak_basket_profit, basket_mae, target, trail_start, giveback,
      (long)basket_started_at * 1000, basket_positions_opened, basket_max_concurrent_positions, close_pending ? "true" : "false",
      JsonEscape(close_reason), close_attempts, last_close_retcode, JsonEscape(last_close_result), daily_pnl, baskets_today, consecutive_losses,
      have_scan ? JsonEscape(last_scan.momentum_state) : "WARMING", have_scan ? JsonEscape(last_scan.watch_direction) : "NONE",
      have_scan ? last_scan.buy_score : 0, have_scan ? last_scan.sell_score : 0,
      have_scan ? last_scan.velocity_1s : 0.0, have_scan ? last_scan.velocity_3s : 0.0, have_scan ? last_scan.velocity_10s : 0.0,
      have_scan ? last_scan.tick_rate_ratio : 0.0, have_scan ? last_scan.acceleration : 0.0,
      have_scan ? last_scan.body_atr : 0.0, have_scan ? last_scan.extension_atr : 0.0,
      JsonEscape(last_event), last_command_id, last_command_succeeded ? "true" : "false", JsonEscape(last_command_result));
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
   if(action == "CLOSE_BASKET" || action == "CLOSE_POSITION") ok = RequestBasketClose("MANUAL DASHBOARD CLOSE", BasketProfit());
   else if(action == "PAUSE_EA" || action == "PAUSE_ADDING")
   {
      local_paused = true;
      CancelPendingOrders();
      last_event = "EA paused; open basket protection remains active";
   }
   else if(action == "RESUME_EA" || action == "RESUME_ADDING")
   {
      if(emergency_stopped) { ok = false; last_event = "Reset emergency stop before resuming"; }
      else { local_paused = false; last_event = "EA resumed"; }
   }
   else if(action == "EMERGENCY_STOP")
   {
      emergency_stopped = true;
      local_paused = true;
      CancelPendingOrders();
      if(CountOurPositions() > 0) ok = RequestBasketClose("EMERGENCY STOP", BasketProfit());
      else last_event = "EMERGENCY STOP active; bot is already flat";
   }
   else if(action == "RESET_EMERGENCY")
   {
      if(close_pending) { ok = false; last_event = "Cannot reset while basket close is pending"; }
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
      PrintFormat("EVE Momentum v1.10 POST %s failed. HTTP=%d MQL=%d response=%s", endpoint, status, GetLastError(), CharArrayToString(result));
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

void ResetDailyIfNeeded()
{
   int today = UtcDayKey();
   if(day_key == today) return;
   day_key = today;
   day_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   daily_pnl = 0.0;
   baskets_today = 0;
   consecutive_losses = 0;
   emergency_stopped = false;
   local_paused = false;
   SavePersistentState();
}

void RecoverPersistentState()
{
   day_key = (int)GVGet("day", 0.0);
   day_start_balance = GVGet("daybalance", AccountInfoDouble(ACCOUNT_BALANCE));
   daily_pnl = GVGet("dailypnl", 0.0);
   baskets_today = (int)GVGet("baskets", 0.0);
   consecutive_losses = (int)GVGet("losses", 0.0);
   emergency_stopped = GVGet("emergency", 0.0) > 0.5;
   local_paused = GVGet("paused", 0.0) > 0.5;
   last_command_id = (long)GVGet("cmd", 0.0);

   basket_started_at = (datetime)GVGet("basketstart", 0.0);
   basket_id = (long)GVGet("basketid", 0.0);
   basket_entry_atr = GVGet("entryatr", 0.0);
   basket_entry_score = (int)GVGet("entryscore", 0.0);
   basket_opposite_score = (int)GVGet("oppscore", 0.0);
   peak_basket_profit = GVGet("peak", 0.0);
   basket_mae = GVGet("mae", 0.0);
   basket_positions_opened = (int)GVGet("opened", 0.0);
   basket_max_concurrent_positions = (int)GVGet("maxpositions", 0.0);
   close_pending = GVGet("closepending", 0.0) > 0.5;
   close_trigger_profit = GVGet("closetrigger", 0.0);
   close_peak_profit = GVGet("closepeak", 0.0);
   close_attempts = (int)GVGet("closeattempts", 0.0);

   if(CountOurPositions() > 0)
   {
      if(basket_started_at <= 0) basket_started_at = EarliestBasketPositionTime();
      if(basket_id <= 0) basket_id = (long)basket_started_at;
      basket_side = BasketSideText();
      last_event = close_pending ? "Recovered active basket with CLOSE PENDING" : "Recovered active momentum basket";
   }
   else if(CountOurPendingOrders() > 0)
      CancelPendingOrders();
   else
      ResetBasketState();

   ResetDailyIfNeeded();
}

void SavePersistentState()
{
   GVSet("day", day_key);
   GVSet("daybalance", day_start_balance);
   GVSet("dailypnl", daily_pnl);
   GVSet("baskets", baskets_today);
   GVSet("losses", consecutive_losses);
   GVSet("emergency", emergency_stopped ? 1.0 : 0.0);
   GVSet("paused", local_paused ? 1.0 : 0.0);
   GVSet("cmd", (double)last_command_id);
   GVSet("basketstart", (double)basket_started_at);
   GVSet("basketid", (double)basket_id);
   GVSet("entryatr", basket_entry_atr);
   GVSet("entryscore", basket_entry_score);
   GVSet("oppscore", basket_opposite_score);
   GVSet("peak", peak_basket_profit);
   GVSet("mae", basket_mae);
   GVSet("opened", basket_positions_opened);
   GVSet("maxpositions", basket_max_concurrent_positions);
   GVSet("closepending", close_pending ? 1.0 : 0.0);
   GVSet("closetrigger", close_trigger_profit);
   GVSet("closepeak", close_peak_profit);
   GVSet("closeattempts", close_attempts);
}

string PersistentPrefix()
{
   return StringFormat("EMB110_%I64d_%I64u_", AccountInfoInteger(ACCOUNT_LOGIN), InpMagicNumber);
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

bool TickPriceAgo(int seconds, double &price)
{
   if(tick_buffer_count <= 0) return false;
   ulong now_ms = GetTickCount64();
   ulong target = now_ms > (ulong)seconds * 1000 ? now_ms - (ulong)seconds * 1000 : 0;
   bool found = false;
   ulong best_time = 0;
   double earliest_price = 0.0;
   ulong earliest_time = 0;
   for(int n=0; n<tick_buffer_count; n++)
   {
      int index = tick_buffer_index - 1 - n;
      while(index < 0) index += TICK_BUFFER_SIZE;
      ulong time = tick_times_ms[index];
      double value = tick_prices[index];
      if(time == 0 || value <= 0) continue;
      if(earliest_time == 0 || time < earliest_time) { earliest_time = time; earliest_price = value; }
      if(time <= target && time >= best_time)
      {
         best_time = time;
         price = value;
         found = true;
      }
   }
   if(found) return true;
   if(earliest_time > 0) { price = earliest_price; return true; }
   return false;
}

int CountTicksSince(ulong from_ms)
{
   int count = 0;
   for(int n=0; n<tick_buffer_count; n++)
   {
      int index = tick_buffer_index - 1 - n;
      while(index < 0) index += TICK_BUFFER_SIZE;
      ulong time = tick_times_ms[index];
      if(time >= from_ms) count++;
   }
   return count;
}

void TickWindowStats(ulong from_ms, ulong to_ms, double &high, double &low, int &count)
{
   high = 0.0;
   low = 0.0;
   count = 0;
   for(int n=0; n<tick_buffer_count; n++)
   {
      int index = tick_buffer_index - 1 - n;
      while(index < 0) index += TICK_BUFFER_SIZE;
      ulong time = tick_times_ms[index];
      double value = tick_prices[index];
      if(time < from_ms || time > to_ms || value <= 0) continue;
      if(count == 0) { high = value; low = value; }
      else { high = MathMax(high, value); low = MathMin(low, value); }
      count++;
   }
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

double BrokerMinimumStopDistancePrice()
{
   double point = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   long stops = SymbolInfoInteger(trade_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze = SymbolInfoInteger(trade_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return MathMax((double)stops, (double)freeze) * point;
}

double CalculateLegLot()
{
   double lot = InpFixedLotPerPosition;
   if(InpUseEquityLotScaling && InpEquityPer001Lot > 0)
   {
      double units = MathFloor(AccountInfoDouble(ACCOUNT_EQUITY) / InpEquityPer001Lot);
      lot = MathMax(0.01, units * 0.01);
   }
   lot = MathMin(lot, InpMaximumTotalLots);
   return NormalizeVolume(lot);
}

double MoneyForLots(double lots, double per_001)
{
   if(lots <= 0 || per_001 <= 0) return 0.0;
   return (lots / 0.01) * per_001;
}

double CurrentBasketTargetMoney()
{
   return MoneyForLots(BasketLots(), InpTargetMoneyPer001Lot);
}

double CurrentBasketTrailStartMoney()
{
   return MoneyForLots(BasketLots(), InpTrailStartMoneyPer001Lot);
}

double CurrentBasketGivebackMoney()
{
   return MoneyForLots(BasketLots(), InpTrailGivebackMoneyPer001Lot);
}

int UtcDayKey()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   return dt.year * 10000 + dt.mon * 100 + dt.day;
}

bool InsideTradingSessionUTC()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   if(InpSessionStartUTC == InpSessionEndUTC) return true;
   if(InpSessionStartUTC < InpSessionEndUTC) return dt.hour >= InpSessionStartUTC && dt.hour < InpSessionEndUTC;
   return dt.hour >= InpSessionStartUTC || dt.hour < InpSessionEndUTC;
}

bool InsideNewYorkWindowUTC()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   if(InpNewYorkStartUTC == InpNewYorkEndUTC) return true;
   if(InpNewYorkStartUTC < InpNewYorkEndUTC) return dt.hour >= InpNewYorkStartUTC && dt.hour < InpNewYorkEndUTC;
   return dt.hour >= InpNewYorkStartUTC || dt.hour < InpNewYorkEndUTC;
}

bool TradeResultAccepted(uint code)
{
   return code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_PLACED || code == TRADE_RETCODE_DONE_PARTIAL || code == TRADE_RETCODE_NO_CHANGES;
}

bool CloseResultAccepted(uint code)
{
   return code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_PLACED || code == TRADE_RETCODE_DONE_PARTIAL || code == TRADE_RETCODE_POSITION_CLOSED || code == TRADE_RETCODE_NO_CHANGES;
}

bool DeleteResultAccepted(uint code)
{
   return code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_PLACED || code == TRADE_RETCODE_NO_CHANGES;
}

double NormalizePrice(double price)
{
   int digits = (int)SymbolInfoInteger(trade_symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
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
   string value = StringSubstr(body, start, finish - start);
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
   CreateLabel(PANEL_PREFIX+"TITLE", 10, 18, "EVE MOMENTUM BURST v1.10 - FLIPPER MODE", 12, clrWhite);
   CreateLabel(PANEL_PREFIX+"STATUS", 10, 42, "WARMING | Position NONE", 10, clrWhite);
   CreateLabel(PANEL_PREFIX+"SCORE", 10, 62, "BUY 0/11 | SELL 0/11", 10, clrWhite);
   CreateLabel(PANEL_PREFIX+"LIVE", 10, 80, "v1 0.000 | tick x0.00 | extension 0.00 ATR", 9, clrLightSteelBlue);
   CreateButton(PANEL_PREFIX+"PAUSE", 10, 108, 120, 28, "PAUSE EA", clrDarkOrange);
   CreateButton(PANEL_PREFIX+"CLOSE", 136, 108, 120, 28, "CLOSE BASKET", clrSlateGray);
   CreateButton(PANEL_PREFIX+"STOP", 262, 108, 130, 28, "EMERGENCY", clrFireBrick);
}

void UpdatePanel()
{
   string state = have_scan ? last_scan.momentum_state : "WARMING";
   string regime = have_scan ? last_scan.regime : "LOADING";
   string side = BasketSideText();
   string status = StringFormat("%s | %s | %s | Positions %d | Pending %d | Lots %.2f | P/L $%.2f",
      state, regime, side, CountOurPositions(), CountOurPendingOrders(), BasketLots(), BasketProfit());
   string scores = have_scan ? StringFormat("BUY %d/11 | SELL %d/11 | %s", last_scan.buy_score, last_scan.sell_score, last_scan.block_reason) : "BUY 0/11 | SELL 0/11";
   string live = have_scan ? StringFormat("v1 %.3f | v3 %.3f | ticks x%.2f | extension %.2f/%.2f ATR", last_scan.velocity_1s, last_scan.velocity_3s, last_scan.tick_rate_ratio, last_scan.extension_atr, last_scan.dynamic_extension_limit) : "Live tick engine warming";
   ObjectSetString(0, PANEL_PREFIX+"STATUS", OBJPROP_TEXT, status);
   ObjectSetString(0, PANEL_PREFIX+"SCORE", OBJPROP_TEXT, scores);
   ObjectSetString(0, PANEL_PREFIX+"LIVE", OBJPROP_TEXT, live);
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
   ObjectDelete(0, PANEL_PREFIX+"LIVE");
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
   if(confirm_fast_handle != INVALID_HANDLE) IndicatorRelease(confirm_fast_handle);
   if(confirm_slow_handle != INVALID_HANDLE) IndicatorRelease(confirm_slow_handle);
}

#property copyright "EVE Momentum"
#property version   "4.10"
#property strict
#property description "XAUUSD demo momentum ladder. Every position has its own broker-side SL and TP."

#include <Trade/Trade.mqh>

CTrade trade;

input group "Identity"
input string InpTradeSymbol                    = "XAUUSD";
input ulong  InpMagicNumber                    = 2407202641;
input string InpOrderCommentPrefix             = "EVE410";

input group "Position sizing and capital protection"
input double InpFixedLot                       = 0.01;
input int    InpMaximumPositions               = 10;
input double InpMaximumTotalLots               = 0.10;
input double InpEmergencyBasketLossPercent     = 1.50;
input double InpMaximumDailyLossPercent        = 4.00;
input int    InpMaximumSpreadPoints            = 120;
input int    InpSlippagePoints                 = 30;

input group "Momentum detector"
input int    InpATRPeriod                      = 14;
input int    InpSignalScoreRequired            = 5;
input int    InpSignalScoreDifference          = 2;
input double InpVelocity1ATR                   = 0.040;
input double InpVelocity3ATR                   = 0.070;
input double InpVelocity10ATR                  = 0.100;
input double InpTickExpansion                  = 1.10;
input double InpAcceleration                   = 1.05;
input int    InpSignalHoldMilliseconds         = 400;
input int    InpOppositeSignalHoldMilliseconds = 1000;
input double InpOppositeThresholdMultiplier    = 1.15;
input int    InpMicroBreakLookbackMilliseconds = 1800;

input group "Campaign construction"
input double InpEntrySpacingATR                = 0.12;
input double InpMinimumEntrySpacingPrice       = 0.18;
input double InpStopLossATR                    = 1.20;
input double InpTakeProfitATR                  = 1.00;
input int    InpMaximumCampaignEntries         = 10;
input double InpAddSupportVelocity1ATR         = 0.015;
input double InpHardFadeVelocityATR            = 0.030;
input int    InpPendingCancelRetryMilliseconds = 750;

input group "Individual position protection"
input bool   InpUseBreakEven                   = true;
input double InpBreakEvenTriggerATR            = 0.45;
input double InpBreakEvenBufferATR             = 0.05;
input bool   InpUseTrailingStop                = true;
input double InpTrailingActivationATR          = 0.75;
input double InpTrailingDistanceATR            = 0.35;
input double InpMinimumTrailStepATR            = 0.08;

input group "Fresh-burst reset"
input double InpQuietVelocity1ATR              = 0.020;
input double InpQuietVelocity3ATR              = 0.035;
input int    InpQuietResetMilliseconds         = 1200;

input group "Railway connection"
input string InpRailwayBaseUrl                 = "https://YOUR-SERVICE.up.railway.app";
input string InpBotToken                       = "CHANGE-ME";
input int    InpHeartbeatSeconds               = 5;
input int    InpCommandPollSeconds             = 8;
input int    InpWebTimeoutMilliseconds         = 3500;

input group "Operation"
input bool   InpStartAutonomous                = true;
input bool   InpShowPanel                      = true;

#define TICK_BUFFER_SIZE 1024
#define MODIFY_MEMORY_SIZE 128

struct TickSample
{
   ulong  ms;
   double mid;
};

struct MomentumSnapshot
{
   bool   ready;
   double atr;
   double mid;
   double velocity1;
   double velocity3;
   double velocity10;
   double tickRatio;
   double acceleration;
   double bodyATR;
   double microHigh;
   double microLow;
   int    buyScore;
   int    sellScore;
   string direction;
   string reason;
};

enum EngineState
{
   STATE_WARMING = 0,
   STATE_IDLE,
   STATE_ARMED,
   STATE_RUNNING,
   STATE_CANCELLING,
   STATE_PAUSED,
   STATE_EMERGENCY
};

string trade_symbol = "";
int atr_handle = INVALID_HANDLE;
TickSample tick_buffer[TICK_BUFFER_SIZE];
int tick_head = 0;
int tick_count = 0;

MomentumSnapshot momentum;
EngineState engine_state = STATE_WARMING;
string campaign_side = "NONE";
string last_campaign_side = "NONE";
string held_signal_side = "NONE";
ulong held_signal_started_ms = 0;
bool reset_required = false;
ulong quiet_started_ms = 0;
bool adding_stopped = false;
int campaign_entries = 0;
datetime campaign_started_at = 0;
double campaign_start_balance = 0.0;
double campaign_peak_floating = 0.0;
double campaign_worst_floating = 0.0;
string last_event = "EA starting";

bool local_paused = false;
bool remote_autonomous = true;
bool emergency_stopped = false;
long last_command_id = 0;
string last_command_result = "No command received";

ulong last_trade_request_ms = 0;
ulong last_cancel_request_ms = 0;
ulong last_heartbeat_ms = 0;
ulong last_poll_ms = 0;
ulong next_http_allowed_ms = 0;
int http_failure_count = 0;
string last_http_status = "Not connected";
string queued_basket_json = "";
double cached_atr = 0.0;
ulong cached_atr_ms = 0;
double cached_daily_pnl = 0.0;
ulong cached_daily_pnl_ms = 0;
double runtime_fixed_lot = 0.01;
bool runtime_use_equity_scaling = false;
double runtime_equity_per_001 = 1000.0;
int runtime_settings_version = 0;

ulong modified_tickets[MODIFY_MEMORY_SIZE];
ulong modified_times[MODIFY_MEMORY_SIZE];
int modified_count = 0;

string PANEL_PREFIX = "EVE410_";

int OnInit()
{
   trade_symbol = InpTradeSymbol == "" ? _Symbol : InpTradeSymbol;
   if(!SymbolSelect(trade_symbol, true))
   {
      Print("EVE v4.10 cannot select symbol ", trade_symbol);
      return INIT_FAILED;
   }

   long margin_mode = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(margin_mode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Alert("EVE v4.10 requires a HEDGING demo account.");
      return INIT_FAILED;
   }

   atr_handle = iATR(trade_symbol, PERIOD_M1, MathMax(2, InpATRPeriod));
   if(atr_handle == INVALID_HANDLE)
   {
      Print("EVE v4.10 failed to create ATR handle. Error ", GetLastError());
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(trade_symbol);
   trade.SetMarginMode();

   remote_autonomous = InpStartAutonomous;
   runtime_fixed_lot = InpFixedLot;
   EventSetTimer(1);
   if(InpShowPanel) CreatePanel();
   last_event = "v4.10 ready: individual SL/TP momentum ladder";
   Print(last_event);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(atr_handle != INVALID_HANDLE) IndicatorRelease(atr_handle);
   DeletePanel();
}

void OnTick()
{
   MqlTick tick;
   if(!SymbolInfoTick(trade_symbol, tick)) return;
   RecordTick(tick);
   BuildMomentum(tick, momentum);
   ManageIndividualProtection(tick);
   EnforceCapitalProtection();
   RunEngine(tick);
   if(InpShowPanel) UpdatePanel();
}

void OnTimer()
{
   ProcessRailway();
   if(InpShowPanel) UpdatePanel();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != trade_symbol) return;
   if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber) return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   ENUM_DEAL_TYPE type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   double price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);

   if(entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_INOUT)
   {
      string side = type == DEAL_TYPE_BUY ? "BUY" : "SELL";
      if(campaign_started_at <= 0) StartCampaign(side);
      campaign_entries++;
      engine_state = STATE_RUNNING;
      adding_stopped = false;
      last_event = StringFormat("%s position %d opened at %.2f with individual SL and TP", side, campaign_entries, price);
   }
   else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
   {
      double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                      HistoryDealGetDouble(trans.deal, DEAL_COMMISSION) +
                      HistoryDealGetDouble(trans.deal, DEAL_SWAP) +
                      HistoryDealGetDouble(trans.deal, DEAL_FEE);
      last_event = StringFormat("Position closed %.2f; remaining positions continue independently", profit);
   }
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;
   if(sparam == PANEL_PREFIX + "PAUSE")
   {
      local_paused = !local_paused;
      if(local_paused) CancelAllPending("manual pause");
      last_event = local_paused ? "EA paused; open positions remain protected" : "EA resumed";
   }
   else if(sparam == PANEL_PREFIX + "CLOSE")
   {
      CancelAllPending("manual close");
      CloseAllPositions("manual close");
   }
   else if(sparam == PANEL_PREFIX + "STOP")
   {
      emergency_stopped = true;
      local_paused = true;
      CancelAllPending("emergency stop");
      CloseAllPositions("emergency stop");
      last_event = "EMERGENCY STOP active";
   }
}

void RecordTick(const MqlTick &tick)
{
   tick_buffer[tick_head].ms = GetTickCount64();
   tick_buffer[tick_head].mid = (tick.bid + tick.ask) * 0.5;
   tick_head = (tick_head + 1) % TICK_BUFFER_SIZE;
   if(tick_count < TICK_BUFFER_SIZE) tick_count++;
}

int BufferIndexFromNewest(int offset)
{
   int index = tick_head - 1 - offset;
   while(index < 0) index += TICK_BUFFER_SIZE;
   return index % TICK_BUFFER_SIZE;
}

bool PriceAtAge(ulong age_ms, double &price)
{
   if(tick_count < 2) return false;
   ulong target = GetTickCount64() > age_ms ? GetTickCount64() - age_ms : 0;
   for(int offset=0; offset<tick_count; offset++)
   {
      int index = BufferIndexFromNewest(offset);
      if(tick_buffer[index].ms <= target)
      {
         price = tick_buffer[index].mid;
         return true;
      }
   }
   return false;
}

int CountTicksSince(ulong age_ms)
{
   ulong target = GetTickCount64() > age_ms ? GetTickCount64() - age_ms : 0;
   int count = 0;
   for(int offset=0; offset<tick_count; offset++)
   {
      int index = BufferIndexFromNewest(offset);
      if(tick_buffer[index].ms < target) break;
      count++;
   }
   return count;
}

bool MicroRange(int lookback_ms, double &high, double &low)
{
   if(tick_count < 5) return false;
   ulong now = GetTickCount64();
   ulong target = now > (ulong)lookback_ms ? now - (ulong)lookback_ms : 0;
   high = -1.0e100;
   low = 1.0e100;
   int used = 0;
   for(int offset=1; offset<tick_count; offset++)
   {
      int index = BufferIndexFromNewest(offset);
      if(tick_buffer[index].ms < target) break;
      high = MathMax(high, tick_buffer[index].mid);
      low = MathMin(low, tick_buffer[index].mid);
      used++;
   }
   return used >= 3;
}

double CurrentATR()
{
   ulong now = GetTickCount64();
   if(cached_atr > 0.0 && cached_atr_ms > 0 && now - cached_atr_ms < 250) return cached_atr;
   if(atr_handle == INVALID_HANDLE) return cached_atr;
   double buffer[2];
   int copied = CopyBuffer(atr_handle, 0, 0, 2, buffer);
   if(copied < 1) return cached_atr;
   double value = copied > 1 && buffer[1] > 0.0 ? buffer[1] : buffer[0];
   if(value > 0.0)
   {
      cached_atr = value;
      cached_atr_ms = now;
   }
   return cached_atr;
}

void BuildMomentum(const MqlTick &tick, MomentumSnapshot &out)
{
   out.ready = false;
   out.atr = CurrentATR();
   out.mid = (tick.bid + tick.ask) * 0.5;
   out.buyScore = 0;
   out.sellScore = 0;
   out.direction = "NONE";
   out.reason = "warming";
   if(out.atr <= 0.0 || tick_count < 20) return;

   double p1, p3, p10;
   if(!PriceAtAge(1000, p1) || !PriceAtAge(3000, p3) || !PriceAtAge(10000, p10)) return;
   if(!MicroRange(InpMicroBreakLookbackMilliseconds, out.microHigh, out.microLow)) return;

   out.velocity1 = (out.mid - p1) / out.atr;
   out.velocity3 = (out.mid - p3) / out.atr;
   out.velocity10 = (out.mid - p10) / out.atr;
   int ticks1 = CountTicksSince(1000);
   int ticks10 = CountTicksSince(10000);
   double normal_per_second = MathMax(1.0, (double)ticks10 / 10.0);
   out.tickRatio = (double)ticks1 / normal_per_second;
   double baseline = MathMax(0.004, MathAbs(out.velocity3) / 3.0);
   out.acceleration = MathAbs(out.velocity1) / baseline;
   double open = iOpen(trade_symbol, PERIOD_M1, 0);
   out.bodyATR = open > 0.0 ? (out.mid - open) / out.atr : 0.0;

   if(out.velocity1 >= InpVelocity1ATR) out.buyScore++;
   if(out.velocity3 >= InpVelocity3ATR) out.buyScore++;
   if(out.velocity10 >= InpVelocity10ATR) out.buyScore++;
   if(out.tickRatio >= InpTickExpansion) out.buyScore++;
   if(out.acceleration >= InpAcceleration && out.velocity1 > 0.0) out.buyScore++;
   if(out.mid >= out.microHigh) out.buyScore++;
   if(out.bodyATR >= 0.08) out.buyScore++;

   if(out.velocity1 <= -InpVelocity1ATR) out.sellScore++;
   if(out.velocity3 <= -InpVelocity3ATR) out.sellScore++;
   if(out.velocity10 <= -InpVelocity10ATR) out.sellScore++;
   if(out.tickRatio >= InpTickExpansion) out.sellScore++;
   if(out.acceleration >= InpAcceleration && out.velocity1 < 0.0) out.sellScore++;
   if(out.mid <= out.microLow) out.sellScore++;
   if(out.bodyATR <= -0.08) out.sellScore++;

   if(out.buyScore >= InpSignalScoreRequired && out.buyScore - out.sellScore >= InpSignalScoreDifference)
      out.direction = "BUY";
   else if(out.sellScore >= InpSignalScoreRequired && out.sellScore - out.buyScore >= InpSignalScoreDifference)
      out.direction = "SELL";

   out.reason = StringFormat("BUY %d/7 SELL %d/7 v1 %.3f v3 %.3f ticks x%.2f", out.buyScore, out.sellScore, out.velocity1, out.velocity3, out.tickRatio);
   out.ready = true;
}

bool SpreadOkay()
{
   MqlTick tick;
   if(!SymbolInfoTick(trade_symbol, tick)) return false;
   double point = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   if(point <= 0.0) return false;
   double spread_points = (tick.ask - tick.bid) / point;
   return spread_points <= InpMaximumSpreadPoints;
}

double CurrentSpreadPoints()
{
   MqlTick tick;
   if(!SymbolInfoTick(trade_symbol, tick)) return 0.0;
   double point = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   return point > 0.0 ? (tick.ask - tick.bid) / point : 0.0;
}

bool NewEntriesAllowed()
{
   if(local_paused || emergency_stopped || !remote_autonomous) return false;
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) return false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return false;
   if(!SpreadOkay()) return false;
   if(DailyLossBlocked()) return false;
   return true;
}

void RunEngine(const MqlTick &tick)
{
   int positions = CountOurPositions();
   int pending = CountOurPending();

   if(emergency_stopped)
   {
      engine_state = STATE_EMERGENCY;
      CancelAllPending("emergency state");
      return;
   }
   if(local_paused || !remote_autonomous)
   {
      engine_state = STATE_PAUSED;
      CancelAllPending("paused");
      return;
   }
   if(!momentum.ready)
   {
      engine_state = STATE_WARMING;
      return;
   }

   if(positions > 0 && campaign_side == "NONE") StartCampaign(OurPositionSide());

   if(positions > 0)
   {
      engine_state = STATE_RUNNING;
      UpdateCampaignStats();
      if(BasketEmergencyReached())
      {
         adding_stopped = true;
         CancelAllPending("basket emergency loss");
         CloseAllPositions("basket emergency loss");
         return;
      }

      string actual_side = OurPositionSide();
      if(actual_side != "NONE") campaign_side = actual_side;

      bool hard_fade = campaign_side == "BUY"
         ? (momentum.velocity1 <= -InpHardFadeVelocityATR || momentum.sellScore >= InpSignalScoreRequired)
         : (momentum.velocity1 >= InpHardFadeVelocityATR || momentum.buyScore >= InpSignalScoreRequired);

      if(hard_fade)
      {
         adding_stopped = true;
         CancelAllPending("momentum faded or opposite pressure confirmed");
         last_event = "Momentum faded; no more positions will be added to this campaign";
      }

      if(!adding_stopped && NewEntriesAllowed() && CampaignCanAdd() && MomentumSupportsCampaign())
         EnsureOnePending(campaign_side);
      else if(!MomentumSupportsCampaign())
         CancelAllPending("same-direction momentum no longer supports adding");

      return;
   }

   if(pending > 0)
   {
      engine_state = STATE_ARMED;
      string pending_side = OurPendingSide();
      if(pending_side == "NONE" || !SignalStillSupports(pending_side))
      {
         engine_state = STATE_CANCELLING;
         CancelAllPending("armed signal faded before fill");
      }
      return;
   }

   if(campaign_started_at > 0)
   {
      FinishCampaign();
      return;
   }
   if(campaign_side != "NONE")
   {
      last_event = campaign_side + " armed signal expired before entry";
      campaign_side = "NONE";
      campaign_entries = 0;
      adding_stopped = false;
   }

   if(reset_required)
   {
      if(QuietResetComplete())
      {
         reset_required = false;
         last_event = "Quiet reset complete; waiting for a genuinely fresh burst";
      }
      else
      {
         engine_state = STATE_IDLE;
         held_signal_side = "NONE";
         held_signal_started_ms = 0;
         return;
      }
   }

   engine_state = STATE_IDLE;
   if(!NewEntriesAllowed()) return;
   string signal = ConfirmedSignal();
   if(signal == "NONE") return;

   campaign_side = signal;
   campaign_entries = 0;
   campaign_started_at = 0;
   adding_stopped = false;
   if(EnsureOnePending(signal))
   {
      engine_state = STATE_ARMED;
      last_event = signal + " momentum confirmed; one continuation stop armed";
   }
   else
   {
      campaign_side = "NONE";
   }
}

string ConfirmedSignal()
{
   string raw = momentum.direction;
   if(raw == "NONE")
   {
      held_signal_side = "NONE";
      held_signal_started_ms = 0;
      return "NONE";
   }

   double multiplier = 1.0;
   int hold_ms = InpSignalHoldMilliseconds;
   bool opposite_to_last = last_campaign_side != "NONE" && raw != last_campaign_side;
   if(opposite_to_last)
   {
      multiplier = InpOppositeThresholdMultiplier;
      hold_ms = InpOppositeSignalHoldMilliseconds;
      bool strong_enough = raw == "BUY"
         ? momentum.velocity1 >= InpVelocity1ATR * multiplier && momentum.velocity3 >= InpVelocity3ATR * multiplier && momentum.buyScore >= InpSignalScoreRequired + 1
         : momentum.velocity1 <= -InpVelocity1ATR * multiplier && momentum.velocity3 <= -InpVelocity3ATR * multiplier && momentum.sellScore >= InpSignalScoreRequired + 1;
      if(!strong_enough)
      {
         held_signal_side = "NONE";
         held_signal_started_ms = 0;
         return "NONE";
      }
   }

   ulong now = GetTickCount64();
   if(held_signal_side != raw)
   {
      held_signal_side = raw;
      held_signal_started_ms = now;
      return "NONE";
   }
   if(held_signal_started_ms == 0 || now - held_signal_started_ms < (ulong)MathMax(0, hold_ms)) return "NONE";

   held_signal_side = "NONE";
   held_signal_started_ms = 0;
   return raw;
}

bool SignalStillSupports(string side)
{
   if(!momentum.ready) return false;
   if(side == "BUY") return momentum.velocity1 > 0.0 && momentum.buyScore >= InpSignalScoreRequired - 1;
   if(side == "SELL") return momentum.velocity1 < 0.0 && momentum.sellScore >= InpSignalScoreRequired - 1;
   return false;
}

bool MomentumSupportsCampaign()
{
   if(campaign_side == "BUY")
      return momentum.velocity1 >= InpAddSupportVelocity1ATR && momentum.buyScore >= InpSignalScoreRequired - 1;
   if(campaign_side == "SELL")
      return momentum.velocity1 <= -InpAddSupportVelocity1ATR && momentum.sellScore >= InpSignalScoreRequired - 1;
   return false;
}

bool QuietResetComplete()
{
   bool quiet = MathAbs(momentum.velocity1) <= InpQuietVelocity1ATR &&
                MathAbs(momentum.velocity3) <= InpQuietVelocity3ATR;
   ulong now = GetTickCount64();
   if(!quiet)
   {
      quiet_started_ms = 0;
      return false;
   }
   if(quiet_started_ms == 0) quiet_started_ms = now;
   return now - quiet_started_ms >= (ulong)MathMax(0, InpQuietResetMilliseconds);
}

void StartCampaign(string side)
{
   campaign_side = side;
   campaign_started_at = TimeCurrent();
   campaign_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   campaign_peak_floating = BasketFloatingProfit();
   campaign_worst_floating = campaign_peak_floating;
   adding_stopped = false;
   engine_state = STATE_RUNNING;
}

void UpdateCampaignStats()
{
   double floating = BasketFloatingProfit();
   campaign_peak_floating = MathMax(campaign_peak_floating, floating);
   campaign_worst_floating = MathMin(campaign_worst_floating, floating);
}

void FinishCampaign()
{
   double realised = CampaignRealisedProfit();
   string finished_side = campaign_side;
   if(finished_side == "NONE") finished_side = last_campaign_side;
   last_campaign_side = finished_side;
   QueueBasketReport(finished_side, realised);
   last_event = StringFormat("%s campaign finished %.2f; quiet reset required before a new campaign", finished_side, realised);
   campaign_side = "NONE";
   campaign_entries = 0;
   campaign_started_at = 0;
   campaign_start_balance = 0.0;
   campaign_peak_floating = 0.0;
   campaign_worst_floating = 0.0;
   adding_stopped = false;
   reset_required = true;
   quiet_started_ms = 0;
   engine_state = STATE_IDLE;
}

bool CampaignCanAdd()
{
   int positions = CountOurPositions();
   if(positions >= InpMaximumPositions) return false;
   if(campaign_entries >= InpMaximumCampaignEntries) return false;
   double lots = OurTotalLots();
   if(InpMaximumTotalLots > 0.0 && lots + EffectiveLot() > InpMaximumTotalLots + 0.000001) return false;
   return true;
}

bool EnsureOnePending(string side)
{
   if(side != "BUY" && side != "SELL") return false;
   int existing = CountOurPending();
   if(existing > 0)
   {
      if(OurPendingSide() == side) return true;
      CancelAllPending("wrong-side pending removed before arming");
      return false;
   }
   return PlaceContinuationStop(side);
}

bool PlaceContinuationStop(string side)
{
   ulong now = GetTickCount64();
   if(last_trade_request_ms > 0 && now - last_trade_request_ms < 200) return false;
   last_trade_request_ms = now;

   MqlTick tick;
   if(!SymbolInfoTick(trade_symbol, tick)) return false;
   double atr = MathMax(momentum.atr, CurrentATR());
   if(atr <= 0.0) return false;

   double point = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   double min_distance = BrokerMinimumDistancePrice() + point * 2.0;
   double spacing = MathMax(InpMinimumEntrySpacingPrice, atr * InpEntrySpacingATR);
   spacing = MathMax(spacing, min_distance);
   double stop_distance = MathMax(atr * InpStopLossATR, min_distance);
   double take_distance = MathMax(atr * InpTakeProfitATR, min_distance);
   double entry = 0.0, sl = 0.0, tp = 0.0;

   if(side == "BUY")
   {
      double highest = HighestOurEntry();
      double base = MathMax(tick.ask, highest);
      entry = MathMax(tick.ask + min_distance, base + spacing);
      sl = entry - stop_distance;
      tp = entry + take_distance;
   }
   else
   {
      double lowest = LowestOurEntry();
      double base = lowest > 0.0 ? MathMin(tick.bid, lowest) : tick.bid;
      entry = MathMin(tick.bid - min_distance, base - spacing);
      sl = entry + stop_distance;
      tp = entry - take_distance;
   }

   entry = NormalisePrice(entry);
   sl = NormalisePrice(sl);
   tp = NormalisePrice(tp);
   double volume = EffectiveLot();
   string comment = StringFormat("%s-%s-%02d", InpOrderCommentPrefix, side, campaign_entries + 1);

   ResetLastError();
   bool submitted = side == "BUY"
      ? trade.BuyStop(volume, entry, trade_symbol, sl, tp, ORDER_TIME_GTC, 0, comment)
      : trade.SellStop(volume, entry, trade_symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
   uint code = trade.ResultRetcode();
   bool accepted = submitted && IsAcceptedTradeRetcode(code);

   if(!accepted)
   {
      last_event = StringFormat("%s stop rejected %u: %s", side, code, trade.ResultRetcodeDescription());
      Print("EVE v4.10 ", last_event, " MQL=", GetLastError());
      return false;
   }

   last_event = StringFormat("%s STOP %.2f placed with own SL %.2f and TP %.2f", side, entry, sl, tp);
   return true;
}

bool IsAcceptedTradeRetcode(uint code)
{
   return code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_PLACED || code == TRADE_RETCODE_DONE_PARTIAL || code == TRADE_RETCODE_NO_CHANGES;
}

bool CancelAllPending(string reason)
{
   bool all_clear = true;
   ulong now = GetTickCount64();
   if(last_cancel_request_ms > 0 && now - last_cancel_request_ms < (ulong)MathMax(100, InpPendingCancelRetryMilliseconds))
      return CountOurPending() == 0;

   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket)) continue;
      if(!IsOurSelectedOrder()) continue;

      ENUM_ORDER_STATE state = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
      if(state != ORDER_STATE_PLACED && state != ORDER_STATE_PARTIAL && state != ORDER_STATE_STARTED) continue;

      if(OrderInsideFreezeZone())
      {
         all_clear = false;
         last_event = "Pending order entered broker freeze zone; cancellation deferred and any fill will remain protected";
         continue;
      }

      last_cancel_request_ms = now;
      ResetLastError();
      bool submitted = trade.OrderDelete(ticket);
      uint code = trade.ResultRetcode();
      if(submitted && IsAcceptedTradeRetcode(code)) continue;

      if(!OrderSelect(ticket)) continue;
      all_clear = false;
      last_event = StringFormat("Cancel deferred for order %I64u: %u %s", ticket, code, trade.ResultRetcodeDescription());
      Print("EVE v4.10 ", last_event, " reason=", reason, " MQL=", GetLastError());
   }
   return all_clear && CountOurPending() == 0;
}

bool OrderInsideFreezeZone()
{
   MqlTick tick;
   if(!SymbolInfoTick(trade_symbol, tick)) return false;
   double point = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   double freeze = (double)SymbolInfoInteger(trade_symbol, SYMBOL_TRADE_FREEZE_LEVEL) * point;
   if(freeze <= 0.0) return false;
   ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   double price = OrderGetDouble(ORDER_PRICE_OPEN);
   double reference = type == ORDER_TYPE_BUY_STOP ? tick.ask : tick.bid;
   return MathAbs(price - reference) <= freeze + point * 2.0;
}

void ManageIndividualProtection(const MqlTick &tick)
{
   double atr = momentum.atr > 0.0 ? momentum.atr : CurrentATR();
   if(atr <= 0.0) return;
   double min_distance = BrokerMinimumDistancePrice() + SymbolInfoDouble(trade_symbol, SYMBOL_POINT) * 2.0;
   double spread_price = tick.ask - tick.bid;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double desired_tp = tp;
      double current = type == POSITION_TYPE_BUY ? tick.bid : tick.ask;
      double progress = type == POSITION_TYPE_BUY ? current - open : open - current;
      double desired = sl;

      if(sl <= 0.0)
      {
         desired = type == POSITION_TYPE_BUY ? open - MathMax(atr * InpStopLossATR, min_distance)
                                             : open + MathMax(atr * InpStopLossATR, min_distance);
      }
      if(tp <= 0.0)
      {
         double intended_tp = type == POSITION_TYPE_BUY ? open + MathMax(atr * InpTakeProfitATR, min_distance)
                                                        : open - MathMax(atr * InpTakeProfitATR, min_distance);
         desired_tp = type == POSITION_TYPE_BUY ? MathMax(intended_tp, tick.ask + min_distance)
                                                 : MathMin(intended_tp, tick.bid - min_distance);
      }

      double buffer = MathMax(atr * InpBreakEvenBufferATR, spread_price + SymbolInfoDouble(trade_symbol, SYMBOL_POINT) * 2.0);
      if(InpUseBreakEven && progress >= atr * InpBreakEvenTriggerATR)
      {
         double be = type == POSITION_TYPE_BUY ? open + buffer : open - buffer;
         desired = BetterStop(type, desired, be);
      }

      if(InpUseTrailingStop && progress >= atr * InpTrailingActivationATR)
      {
         double trail = type == POSITION_TYPE_BUY ? tick.bid - atr * InpTrailingDistanceATR
                                                  : tick.ask + atr * InpTrailingDistanceATR;
         desired = BetterStop(type, desired, trail);
      }

      desired = ClampLegalStop(type, desired, tick, min_distance);
      bool stop_change = StopImprovesEnough(type, sl, desired, atr);
      bool tp_change = tp <= 0.0 && desired_tp > 0.0;
      if(!stop_change && !tp_change) continue;
      if(!CanModifyTicket(ticket)) continue;
      double requested_sl = stop_change ? desired : sl;

      ResetLastError();
      bool submitted = trade.PositionModify(ticket, NormalisePrice(requested_sl), NormalisePrice(desired_tp));
      uint code = trade.ResultRetcode();
      RememberModify(ticket);
      if(!submitted || !IsAcceptedTradeRetcode(code))
      {
         PrintFormat("EVE v4.10 position %I64u protection modify rejected %u %s MQL=%d", ticket, code, trade.ResultRetcodeDescription(), GetLastError());
      }
   }
}

double BetterStop(ENUM_POSITION_TYPE type, double current_stop, double candidate)
{
   if(current_stop <= 0.0) return candidate;
   if(type == POSITION_TYPE_BUY) return MathMax(current_stop, candidate);
   return MathMin(current_stop, candidate);
}

double ClampLegalStop(ENUM_POSITION_TYPE type, double desired, const MqlTick &tick, double min_distance)
{
   if(type == POSITION_TYPE_BUY) return MathMin(desired, tick.bid - min_distance);
   return MathMax(desired, tick.ask + min_distance);
}

bool StopImprovesEnough(ENUM_POSITION_TYPE type, double old_sl, double new_sl, double atr)
{
   if(new_sl <= 0.0) return false;
   double step = MathMax(SymbolInfoDouble(trade_symbol, SYMBOL_POINT) * 2.0, atr * InpMinimumTrailStepATR);
   if(old_sl <= 0.0) return true;
   if(type == POSITION_TYPE_BUY) return new_sl >= old_sl + step;
   return new_sl <= old_sl - step;
}

bool CanModifyTicket(ulong ticket)
{
   ulong now = GetTickCount64();
   for(int i=0; i<modified_count; i++)
      if(modified_tickets[i] == ticket) return now - modified_times[i] >= 750;
   return true;
}

void RememberModify(ulong ticket)
{
   ulong now = GetTickCount64();
   for(int i=0; i<modified_count; i++)
   {
      if(modified_tickets[i] == ticket)
      {
         modified_times[i] = now;
         return;
      }
   }
   if(modified_count < MODIFY_MEMORY_SIZE)
   {
      modified_tickets[modified_count] = ticket;
      modified_times[modified_count] = now;
      modified_count++;
   }
}

void EnforceCapitalProtection()
{
   if(BasketEmergencyReached())
   {
      adding_stopped = true;
      CancelAllPending("capital protection");
      CloseAllPositions("capital protection");
   }
}

bool BasketEmergencyReached()
{
   if(InpEmergencyBasketLossPercent <= 0.0 || CountOurPositions() == 0) return false;
   double maximum_loss = AccountInfoDouble(ACCOUNT_BALANCE) * InpEmergencyBasketLossPercent / 100.0;
   return BasketFloatingProfit() <= -maximum_loss;
}

bool DailyLossBlocked()
{
   if(InpMaximumDailyLossPercent <= 0.0) return false;
   double pnl = DailyRealisedProfit();
   double estimated_start = AccountInfoDouble(ACCOUNT_BALANCE) - pnl;
   if(estimated_start <= 0.0) return false;
   return pnl <= -(estimated_start * InpMaximumDailyLossPercent / 100.0);
}

double DailyRealisedProfit()
{
   ulong now_ms = GetTickCount64();
   if(cached_daily_pnl_ms > 0 && now_ms - cached_daily_pnl_ms < 1000) return cached_daily_pnl;
   MqlDateTime parts;
   TimeToStruct(TimeCurrent(), parts);
   parts.hour = 0; parts.min = 0; parts.sec = 0;
   datetime start = StructToTime(parts);
   if(!HistorySelect(start, TimeCurrent() + 60)) return cached_daily_pnl;
   double total = 0.0;
   for(int i=0; i<HistoryDealsTotal(); i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != trade_symbol) continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagicNumber) continue;
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT) continue;
      total += HistoryDealGetDouble(deal, DEAL_PROFIT) +
               HistoryDealGetDouble(deal, DEAL_COMMISSION) +
               HistoryDealGetDouble(deal, DEAL_SWAP) +
               HistoryDealGetDouble(deal, DEAL_FEE);
   }
   cached_daily_pnl = total;
   cached_daily_pnl_ms = now_ms;
   return total;
}

double CampaignRealisedProfit()
{
   if(campaign_started_at <= 0) return AccountInfoDouble(ACCOUNT_BALANCE) - campaign_start_balance;
   if(!HistorySelect(campaign_started_at - 2, TimeCurrent() + 60)) return 0.0;
   double total = 0.0;
   for(int i=0; i<HistoryDealsTotal(); i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != trade_symbol) continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagicNumber) continue;
      total += HistoryDealGetDouble(deal, DEAL_PROFIT) +
               HistoryDealGetDouble(deal, DEAL_COMMISSION) +
               HistoryDealGetDouble(deal, DEAL_SWAP) +
               HistoryDealGetDouble(deal, DEAL_FEE);
   }
   return total;
}

bool CloseAllPositions(string reason)
{
   bool all_closed = true;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      ResetLastError();
      bool submitted = trade.PositionClose(ticket, InpSlippagePoints);
      uint code = trade.ResultRetcode();
      if(!submitted || !IsAcceptedTradeRetcode(code))
      {
         all_closed = false;
         PrintFormat("EVE v4.10 close %I64u failed %u %s MQL=%d", ticket, code, trade.ResultRetcodeDescription(), GetLastError());
      }
   }
   last_event = reason + (all_closed ? ": close requests accepted" : ": some close requests require retry");
   return all_closed;
}

int CountOurPositions()
{
   int count = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket) && IsOurSelectedPosition()) count++;
   }
   return count;
}

int CountOurPending()
{
   int count = 0;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0 && OrderSelect(ticket) && IsOurSelectedOrder()) count++;
   }
   return count;
}

bool IsOurSelectedPosition()
{
   return PositionGetString(POSITION_SYMBOL) == trade_symbol &&
          (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber;
}

bool IsOurSelectedOrder()
{
   if(OrderGetString(ORDER_SYMBOL) != trade_symbol) return false;
   if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber) return false;
   ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   return type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP;
}

string OurPositionSide()
{
   int buys = 0, sells = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(type == POSITION_TYPE_BUY) buys++; else if(type == POSITION_TYPE_SELL) sells++;
   }
   if(buys > 0 && sells == 0) return "BUY";
   if(sells > 0 && buys == 0) return "SELL";
   return "NONE";
}

string OurPendingSide()
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket) || !IsOurSelectedOrder()) continue;
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      return type == ORDER_TYPE_BUY_STOP ? "BUY" : "SELL";
   }
   return "NONE";
}

double BasketFloatingProfit()
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

double OurTotalLots()
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

double HighestOurEntry()
{
   double highest = 0.0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      highest = MathMax(highest, PositionGetDouble(POSITION_PRICE_OPEN));
   }
   return highest;
}

double LowestOurEntry()
{
   double lowest = 0.0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      double price = PositionGetDouble(POSITION_PRICE_OPEN);
      if(lowest <= 0.0 || price < lowest) lowest = price;
   }
   return lowest;
}

double BrokerMinimumDistancePrice()
{
   double point = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   long stops = SymbolInfoInteger(trade_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze = SymbolInfoInteger(trade_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return MathMax((double)stops, (double)freeze) * point;
}

double NormalisePrice(double price)
{
   int digits = (int)SymbolInfoInteger(trade_symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
}

double EffectiveLot()
{
   double lot = runtime_fixed_lot;
   if(runtime_use_equity_scaling && runtime_equity_per_001 > 0.0)
   {
      double units = MathFloor(AccountInfoDouble(ACCOUNT_EQUITY) / runtime_equity_per_001);
      if(units < 1.0) units = 1.0;
      lot = units * 0.01;
   }
   return NormaliseVolume(lot);
}

double NormaliseVolume(double volume)
{
   double minimum = SymbolInfoDouble(trade_symbol, SYMBOL_VOLUME_MIN);
   double maximum = SymbolInfoDouble(trade_symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(trade_symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = minimum > 0.0 ? minimum : 0.01;
   volume = MathMax(minimum, MathMin(maximum, volume));
   volume = MathFloor(volume / step + 0.0000001) * step;
   return NormalizeDouble(volume, 2);
}

string EngineStateText()
{
   switch(engine_state)
   {
      case STATE_WARMING: return "WARMING";
      case STATE_IDLE: return reset_required ? "WAITING FOR QUIET RESET" : "WAITING FOR BURST";
      case STATE_ARMED: return "CONTINUATION STOP ARMED";
      case STATE_RUNNING: return adding_stopped ? "POSITIONS MANAGED - ADDING STOPPED" : "MOMENTUM CAMPAIGN ACTIVE";
      case STATE_CANCELLING: return "CANCELLING STALE PENDING";
      case STATE_PAUSED: return "PAUSED";
      case STATE_EMERGENCY: return "EMERGENCY STOP";
   }
   return "UNKNOWN";
}

void ProcessRailway()
{
   string base = TrimTrailingSlash(InpRailwayBaseUrl);
   if(base == "" || StringFind(base, "YOUR-SERVICE") >= 0 || InpBotToken == "CHANGE-ME") return;
   ulong now = GetTickCount64();
   if(now < next_http_allowed_ms) return;

   if(queued_basket_json != "")
   {
      if(PostJson("/api/ea/basket", queued_basket_json)) queued_basket_json = "";
      return;
   }

   ulong heartbeat_interval = (ulong)MathMax(2, InpHeartbeatSeconds) * 1000;
   ulong poll_interval = (ulong)MathMax(3, InpCommandPollSeconds) * 1000;
   if(last_heartbeat_ms == 0 || now - last_heartbeat_ms >= heartbeat_interval)
   {
      SendHeartbeat();
      last_heartbeat_ms = now;
      return;
   }
   if(last_poll_ms == 0 || now - last_poll_ms >= poll_interval)
   {
      PollRailway();
      last_poll_ms = now;
   }
}

void SendHeartbeat()
{
   MqlTick tick;
   SymbolInfoTick(trade_symbol, tick);
   string json = StringFormat(
      "{\"account\":\"%I64d\",\"symbol\":\"%s\",\"version\":\"4.10\",\"magic\":\"%I64u\",\"strategy\":\"INDIVIDUAL_SL_TP_MOMENTUM_LADDER\",\"balance\":%.2f,\"equity\":%.2f,\"margin\":%.2f,\"freeMargin\":%.2f,\"marginLevel\":%.2f,\"bid\":%.5f,\"ask\":%.5f,\"spreadPoints\":%.1f,\"terminalConnected\":%s,\"algoAllowed\":%s,\"autonomous\":%s,\"emergency\":%s,\"engineState\":\"%s\",\"supervisorState\":\"%s\",\"supervisorFault\":false,\"supervisorReason\":\"%s\",\"bracketState\":\"%s\",\"campaignPhase\":\"%s\",\"campaignStartSide\":\"%s\",\"campaignCurrentSide\":\"%s\",\"campaignBuyLegs\":%d,\"campaignSellLegs\":%d,\"telemetryQueueDepth\":%d,\"bracketBuyPrice\":%.5f,\"bracketSellPrice\":%.5f,\"positionOpen\":%s,\"positionCount\":%d,\"pendingCount\":%d,\"side\":\"%s\",\"totalLots\":%.2f,\"averageEntry\":%.5f,\"currentPrice\":%.5f,\"protectedStop\":0,\"floatingProfit\":%.2f,\"peakBasketProfit\":%.2f,\"basketMae\":%.2f,\"basketStartedAt\":%I64d,\"positionsOpened\":%d,\"maxConcurrentPositions\":%d,\"bankCandidate\":false,\"bankReason\":\"Individual SL/TP management\",\"closePending\":false,\"closeReason\":\"\",\"closeAttempts\":0,\"dailyPnl\":%.2f,\"basketsToday\":0,\"consecutiveLosses\":0,\"momentumState\":\"%s\",\"liveDirection\":\"%s\",\"buyScore\":%d,\"sellScore\":%d,\"velocity1s\":%.5f,\"velocity3s\":%.5f,\"velocity10s\":%.5f,\"tickRateRatio\":%.3f,\"acceleration\":%.3f,\"bodyAtr\":%.3f,\"extensionAtr\":0,\"settingsVersion\":%d,\"lastEvent\":\"%s\",\"consumedCommandId\":%I64d,\"lastCommandSucceeded\":true,\"lastCommandResult\":\"%s\"}",
      AccountInfoInteger(ACCOUNT_LOGIN), JsonEscape(trade_symbol), InpMagicNumber,
      AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY), AccountInfoDouble(ACCOUNT_MARGIN),
      AccountInfoDouble(ACCOUNT_MARGIN_FREE), AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), tick.bid, tick.ask, CurrentSpreadPoints(),
      TerminalInfoInteger(TERMINAL_CONNECTED) ? "true" : "false", MQLInfoInteger(MQL_TRADE_ALLOWED) ? "true" : "false",
      (remote_autonomous && !local_paused) ? "true" : "false", emergency_stopped ? "true" : "false",
      JsonEscape(EngineStateText()), JsonEscape(EngineStateText()), JsonEscape(last_event), JsonEscape(OurPendingSide()), JsonEscape(EngineStateText()),
      JsonEscape(campaign_side), JsonEscape(campaign_side), campaign_side == "BUY" ? CountOurPositions() : 0, campaign_side == "SELL" ? CountOurPositions() : 0,
      queued_basket_json == "" ? 0 : 1, PendingPrice("BUY"), PendingPrice("SELL"), CountOurPositions() > 0 ? "true" : "false",
      CountOurPositions(), CountOurPending(), JsonEscape(OurPositionSide()), OurTotalLots(), AverageEntry(),
      campaign_side == "BUY" ? tick.bid : campaign_side == "SELL" ? tick.ask : (tick.bid + tick.ask) * 0.5,
      BasketFloatingProfit(), campaign_peak_floating, campaign_worst_floating, (long)campaign_started_at * 1000,
      campaign_entries, CountOurPositions(), DailyRealisedProfit(), JsonEscape(momentum.reason), JsonEscape(momentum.direction),
      momentum.buyScore, momentum.sellScore, momentum.velocity1, momentum.velocity3, momentum.velocity10,
      momentum.tickRatio, momentum.acceleration, momentum.bodyATR, runtime_settings_version, JsonEscape(last_event), last_command_id, JsonEscape(last_command_result));
   PostJson("/api/ea/heartbeat", json);
}

void PollRailway()
{
   string base = TrimTrailingSlash(InpRailwayBaseUrl);
   string url = base + "/api/ea/control?token=" + InpBotToken;
   char data[];
   char result[];
   string response_headers;
   ResetLastError();
   int status = WebRequest("GET", url, "", "", InpWebTimeoutMilliseconds, data, 0, result, response_headers);
   if(status != 200)
   {
      RegisterHttpFailure("control", status, CharArrayToString(result));
      return;
   }
   RegisterHttpSuccess("control");
   string body = CharArrayToString(result);
   remote_autonomous = ParseLineValue(body, "autonomous") == "true";
   bool remote_emergency = ParseLineValue(body, "emergency") == "true";
   int incoming_settings_version = (int)StringToInteger(ParseLineValue(body, "settings_version"));
   if(incoming_settings_version > runtime_settings_version)
   {
      double incoming_lot = StringToDouble(ParseLineValue(body, "fixed_lot"));
      if(incoming_lot > 0.0) runtime_fixed_lot = incoming_lot;
      runtime_use_equity_scaling = ParseLineValue(body, "use_equity_scaling") == "true";
      double incoming_equity_per = StringToDouble(ParseLineValue(body, "equity_per_001_lot"));
      if(incoming_equity_per > 0.0) runtime_equity_per_001 = incoming_equity_per;
      runtime_settings_version = incoming_settings_version;
      last_event = StringFormat("Dashboard lot settings applied: %.2f effective lot", EffectiveLot());
   }
   long command_id = StringToInteger(ParseLineValue(body, "command_id"));
   string action = ParseLineValue(body, "action");
   if(remote_emergency) emergency_stopped = true;
   if(command_id > last_command_id && action != "NONE")
   {
      ExecuteRemoteCommand(action);
      last_command_id = command_id;
      last_command_result = last_event;
   }
}

void ExecuteRemoteCommand(string action)
{
   if(action == "PAUSE_EA" || action == "PAUSE_ADDING")
   {
      local_paused = true;
      CancelAllPending("dashboard pause");
      last_event = "Dashboard paused new entries";
   }
   else if(action == "RESUME_EA" || action == "RESUME_ADDING")
   {
      if(!emergency_stopped) local_paused = false;
      last_event = emergency_stopped ? "Reset emergency before resuming" : "Dashboard resumed EA";
   }
   else if(action == "CLOSE_BASKET" || action == "CLOSE_POSITION")
   {
      CancelAllPending("dashboard close");
      CloseAllPositions("dashboard close");
   }
   else if(action == "EMERGENCY_STOP")
   {
      emergency_stopped = true;
      local_paused = true;
      CancelAllPending("dashboard emergency");
      CloseAllPositions("dashboard emergency");
   }
   else if(action == "RESET_EMERGENCY")
   {
      emergency_stopped = false;
      local_paused = false;
      last_event = "Emergency stop reset";
   }
   else if(action == "REBUILD_BRACKET")
   {
      CancelAllPending("dashboard reset burst watcher");
      held_signal_side = "NONE";
      held_signal_started_ms = 0;
      last_event = "Burst watcher reset";
   }
   else last_event = "Unsupported dashboard command: " + action;
}

bool PostJson(string endpoint, string json)
{
   string base = TrimTrailingSlash(InpRailwayBaseUrl);
   string url = base + endpoint + "?token=" + InpBotToken;
   char post[];
   char result[];
   string response_headers;
   StringToCharArray(json, post, 0, WHOLE_ARRAY, CP_UTF8);
   int size = ArraySize(post);
   if(size > 0 && post[size-1] == 0) ArrayResize(post, size - 1);
   ResetLastError();
   int status = WebRequest("POST", url, "Content-Type: application/json\r\nConnection: close\r\n", InpWebTimeoutMilliseconds, post, result, response_headers);
   if(status < 200 || status >= 300)
   {
      RegisterHttpFailure(endpoint, status, CharArrayToString(result));
      return false;
   }
   RegisterHttpSuccess(endpoint);
   return true;
}

void RegisterHttpFailure(string endpoint, int status, string response)
{
   http_failure_count++;
   int exponent = http_failure_count < 5 ? http_failure_count : 5;
   int backoff_seconds = 2 * (1 << exponent);
   if(backoff_seconds > 60) backoff_seconds = 60;
   next_http_allowed_ms = GetTickCount64() + (ulong)backoff_seconds * 1000;
   last_http_status = StringFormat("%s HTTP %d MQL %d; retry in %ds", endpoint, status, GetLastError(), backoff_seconds);
   Print("EVE v4.10 Railway ", last_http_status, " response=", response);
}

void RegisterHttpSuccess(string endpoint)
{
   http_failure_count = 0;
   next_http_allowed_ms = 0;
   last_http_status = endpoint + " OK";
}

void QueueBasketReport(string side, double realised)
{
   long started_ms = (long)campaign_started_at * 1000;
   long ended_ms = (long)TimeCurrent() * 1000;
   queued_basket_json = StringFormat(
      "{\"id\":\"%I64d-%I64d\",\"account\":\"%I64d\",\"symbol\":\"%s\",\"version\":\"4.10\",\"strategy\":\"INDIVIDUAL_SL_TP_MOMENTUM_LADDER\",\"magic\":\"%I64u\",\"status\":\"CLOSED\",\"side\":\"%s\",\"startSide\":\"%s\",\"entryTime\":%I64d,\"exitTime\":%I64d,\"durationSeconds\":%d,\"positionsOpened\":%d,\"lotPerLeg\":%.2f,\"netProfit\":%.2f,\"peakBasketProfit\":%.2f,\"mae\":%.2f,\"profitGiveback\":%.2f,\"exitReason\":\"INDIVIDUAL SL/TP CAMPAIGN COMPLETE\",\"entryRegime\":\"LIVE TICK MOMENTUM\"}",
      AccountInfoInteger(ACCOUNT_LOGIN), ended_ms, AccountInfoInteger(ACCOUNT_LOGIN), JsonEscape(trade_symbol), InpMagicNumber,
      JsonEscape(side), JsonEscape(side), started_ms, ended_ms, campaign_started_at > 0 ? (int)(TimeCurrent() - campaign_started_at) : 0,
      campaign_entries, EffectiveLot(), realised, campaign_peak_floating, campaign_worst_floating,
      MathMax(0.0, campaign_peak_floating - realised));
}

double PendingPrice(string side)
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket) || !IsOurSelectedOrder()) continue;
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if((side == "BUY" && type == ORDER_TYPE_BUY_STOP) || (side == "SELL" && type == ORDER_TYPE_SELL_STOP))
         return OrderGetDouble(ORDER_PRICE_OPEN);
   }
   return 0.0;
}

double AverageEntry()
{
   double weighted = 0.0, volume = 0.0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      double lot = PositionGetDouble(POSITION_VOLUME);
      weighted += PositionGetDouble(POSITION_PRICE_OPEN) * lot;
      volume += lot;
   }
   return volume > 0.0 ? weighted / volume : 0.0;
}

string ParseLineValue(string body, string key)
{
   string marker = key + "=";
   int start = StringFind(body, marker);
   if(start < 0) return "";
   start += StringLen(marker);
   int end = StringFind(body, "\n", start);
   if(end < 0) end = StringLen(body);
   string value = StringSubstr(body, start, end - start);
   StringTrimLeft(value);
   StringTrimRight(value);
   return value;
}

string TrimTrailingSlash(string value)
{
   StringTrimLeft(value);
   StringTrimRight(value);
   while(StringLen(value) > 0 && StringSubstr(value, StringLen(value)-1, 1) == "/")
      value = StringSubstr(value, 0, StringLen(value)-1);
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
   CreateLabel(PANEL_PREFIX + "TITLE", 12, 18, "EVE FURY RECONSTRUCTION DEMO v4.10", 12);
   CreateLabel(PANEL_PREFIX + "STATE", 12, 42, "STATE", 10);
   CreateLabel(PANEL_PREFIX + "MOMENTUM", 12, 62, "MOMENTUM", 9);
   CreateLabel(PANEL_PREFIX + "CAMPAIGN", 12, 82, "CAMPAIGN", 9);
   CreateLabel(PANEL_PREFIX + "HTTP", 12, 102, "RAILWAY", 8);
   CreateButton(PANEL_PREFIX + "PAUSE", 12, 126, 120, 28, "PAUSE EA", clrDarkOrange);
   CreateButton(PANEL_PREFIX + "CLOSE", 142, 126, 120, 28, "CLOSE ALL", clrSlateGray);
   CreateButton(PANEL_PREFIX + "STOP", 272, 126, 120, 28, "EMERGENCY", clrCrimson);
}

void UpdatePanel()
{
   if(!InpShowPanel) return;
   SetLabel(PANEL_PREFIX + "STATE", "STATE: " + EngineStateText());
   SetLabel(PANEL_PREFIX + "MOMENTUM", StringFormat("BUY %d/7 | SELL %d/7 | v1 %.3f | v3 %.3f | spread %.1f", momentum.buyScore, momentum.sellScore, momentum.velocity1, momentum.velocity3, CurrentSpreadPoints()));
   SetLabel(PANEL_PREFIX + "CAMPAIGN", StringFormat("%s | positions %d | pending %d | P/L %.2f | every trade has own SL/TP", campaign_side, CountOurPositions(), CountOurPending(), BasketFloatingProfit()));
   SetLabel(PANEL_PREFIX + "HTTP", "RAILWAY: " + last_http_status);
   SetButtonText(PANEL_PREFIX + "PAUSE", local_paused ? "RESUME EA" : "PAUSE EA");
   ChartRedraw();
}

void DeletePanel()
{
   for(int i=ObjectsTotal(0)-1; i>=0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, PANEL_PREFIX) == 0) ObjectDelete(0, name);
   }
}

void CreateLabel(string name, int x, int y, string text, int size)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void CreateButton(string name, int x, int y, int width, int height, string text, color background)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, background);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void SetLabel(string name, string text)
{
   if(ObjectFind(0, name) >= 0) ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void SetButtonText(string name, string text)
{
   if(ObjectFind(0, name) >= 0) ObjectSetString(0, name, OBJPROP_TEXT, text);
}

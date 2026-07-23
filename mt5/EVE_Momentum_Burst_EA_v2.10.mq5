#property copyright "EVE Momentum Research"
#property version   "2.10"
#property strict
#property description "One M1 campaign attempt per candle. Position 1 profit lock. One pre-armed stop order ahead. Every confirmed position shares one broker-side basket SL."

#include <Trade/Trade.mqh>

CTrade trade;

input group "Identity"
input string InpTradeSymbol                    = "";                 // Blank = attached chart symbol
input ulong  InpMagicNumber                    = 2207202610;
input string InpOrderComment                   = "EVE-MOMENTUM-V2.10";

input group "One-time legacy isolation"
input bool   InpDeleteLegacyPendingOrders       = true;                // Deletes v2.09 EVE pending orders before v2.10 starts
input ulong  InpLegacyMagicNumber               = 2207202609;          // Previous v2.09 EVE magic number
input bool   InpBlockOnLegacyOpenPosition       = true;                // Prevents overlapping v2.09 and v2.10 campaigns

input group "Railway connection"
input string InpRailwayBaseUrl                 = "https://YOUR-SERVICE.up.railway.app";
input string InpBotToken                       = "CHANGE-ME";
input int    InpHeartbeatSeconds                = 5;
input int    InpCommandPollSeconds              = 5;
input int    InpTelemetrySeconds                = 5;
input int    InpWebTimeoutMs                    = 800;

input group "User-controlled lot and ladder limits"
input bool   InpAutonomousAtStart               = true;
input double InpFixedLotPerPosition             = 0.01;
input bool   InpUseEquityLotScaling             = false;
input double InpEquityPer001Lot                 = 1000.0;
input int    InpInitialPositions                = 1;
input int    InpMaximumPositions                = 0;                  // 0 = unlimited; retained only for dashboard compatibility
input double InpMaximumTotalLots                = 0.0;                // 0 = unlimited; retained only for dashboard compatibility
input int    InpSlippagePoints                  = 30;
input int    InpMinimumSequentialFillTicks       = 1;                  // Safety only: later BUY fills must be higher; later SELL fills must be lower
input int    InpMissingSLGraceSeconds             = 1;                  // Allows the terminal one second to attach the broker-side SL after a fill
input int    InpTradeRequestCooldownMs           = 0;                  // No strategy cooldown
input int    InpOrderDeleteTimeoutSeconds         = 5;
input int    InpPendingSafetyBufferPoints         = 18;
input int    InpPendingInvalidPriceBackoffSeconds = 1;                 // Broker-error retry only; not a strategy cooldown
input int    InpPendingMaximumAdaptiveBufferPoints= 80;

input group "Every-candle breakout straddle"
input bool   InpUseMovingStraddle               = true;                // Fixed once per candle while flat
input double InpBracketDistanceATR              = 0.20;
input double InpBracketRefreshATR               = 0.10;
input int    InpBracketMaximumAgeSeconds        = 0;                   // Replaced only when a new candle starts
input double InpReverseStopATR                  = 0.75;
input double InpReverseBufferATR                = 0.025;
input double InpBracketMinimumDistancePrice     = 0.25;
input int    InpOcoCancelTimeoutSeconds         = 8;
input int    InpCampaignLockSeconds             = 0;                   // No campaign lock
input int    InpPostCampaignCooldownSeconds     = 0;                   // Legacy input; v2.10 waits for the next candle, not a timed cooldown
input bool   InpOneCampaignAttemptPerCandle      = true;                // A finished campaign cannot restart inside the same M1 candle
input bool   InpPausePendingEntriesOnWideSpread  = true;                // Execution safety only; open positions keep their broker-side SL
input int    InpReversalArmDelaySeconds         = 0;                   // Legacy input; unused in v2.10
input double InpReversalArmMinimumProfitMoney   = 0.0;                 // Legacy input; unused in v2.10

input group "Continuous pending-stop ladder"
input double InpAddSpacingATR                   = 0.10;                // Distance between ladder stops
input int    InpAddCooldownSeconds              = 0;                   // No add cooldown
input double InpAddOnlyAfterBasketProfit        = 0.0;                 // Legacy input; unused in v2.10
input bool   InpNeverAddToLosingBasket          = false;               // Pending ladder is price-triggered, not P/L-gated
input double InpNewestLegProfitBeforeAddMoney   = 0.0;                 // Legacy input; unused in v2.10
input int    InpLadderOrdersAhead                = 1;                   // Safety: exactly one future stop is ever allowed
input double InpLadderMinimumSpacingPrice       = 0.20;
input double InpNewestSLPreviousLegLockFraction  = 0.65;                // Shared SL sits 65% through the latest entry gap before cost adjustment
input double InpFallbackATRPrice                 = 1.00;

input group "Live momentum engine"
input ENUM_TIMEFRAMES InpExecutionTimeframe     = PERIOD_M1;
input ENUM_TIMEFRAMES InpConfirmationTimeframe  = PERIOD_M5;
input int    InpATRPeriod                       = 14;
input int    InpFastEMA                         = 9;
input int    InpSlowEMA                         = 21;
input int    InpTrendEMA                        = 50;
input int    InpAnalyticsReferenceScore         = 5;                  // Display/telemetry only; never gates orders
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
input bool   InpUseSessionFilter                = false;               // Runs whenever the broker market is open
input int    InpSessionStartUTC                 = 6;
input int    InpSessionEndUTC                   = 21;
input bool   InpPreferNewYorkWindow             = true;
input int    InpNewYorkStartUTC                 = 12;
input int    InpNewYorkEndUTC                   = 17;

input group "Shared basket stop protection"
input double InpStopLossATR                     = 0.75;                 // Initial/provisional order protection before direction is confirmed
input double InpTakeProfitATR                   = 0.0;                  // No fixed TP
input double InpSharedSLMinimumNetProfitMoney   = 0.20;                 // Minimum basket profit intended after the cost reserve
input double InpSharedSLCommissionReservePerLot = 8.00;                 // Observed IC Markets round-trip reserve per 1.00 lot
input int    InpSharedSLSlippageReservePoints   = 5;                    // Extra price cushion beyond calculated break-even
input int    InpSharedSLSyncTolerancePoints     = 0;                    // 0 = exact tick-price match; positive values allow extra point tolerance
input double InpProvisionalLockTriggerMoney     = 0.20;                 // Position 1 starts protecting profit after this peak
input double InpProvisionalLockMinimumMoney     = 0.10;                 // Minimum intended net profit when Position 1 protection activates
input double InpProvisionalLockGivebackPercent  = 50.0;                 // 50 = retain half of Position 1's best floating profit
input double InpBreakEvenTriggerATR             = 0.10;                 // Legacy input; unused in v2.10
input double InpTrailingActivationATR           = 0.16;                 // Legacy input; unused in v2.10
input double InpNewestTrailATR                  = 0.065;                // Legacy input; unused in v2.10
input double InpMiddleTrailATR                  = 0.10;                 // Legacy input; unused in v2.10
input double InpOldestTrailATR                  = 0.16;                 // Legacy input; unused in v2.10

input group "Canary and basket banking"
input double InpMinimumBankProfitMoney          = 0.20;
input int    InpCanaryMinimumAgeSeconds         = 3;
input double InpCanaryPeakMinimumMoney          = 0.05;
input double InpCanaryGivebackPercent           = 75.0;
input double InpCanaryNegativeTriggerMoney      = 0.05;
input double InpBasketPeakGivebackPercent       = 28.0;
input double InpMaximumBasketLossMoney          = 0.0;                 // No automatic basket-loss restriction
input int    InpMaximumBasketMinutes            = 0;                   // No campaign-duration restriction
input int    InpFlipScoreThreshold              = 7;
input int    InpCloseRetrySeconds               = 3;

input group "Demo testing and account protection"
input bool   InpDemoTestingModeDefault         = true; // true = track losses but do not auto-lock entries
input double InpMaximumDailyLossPercent         = 0.0;
input double InpDailyProfitTargetPercent        = 0.0;
input int    InpMaximumBasketsPerDay            = 0;
input int    InpMaximumConsecutiveLosses        = 0;

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
ulong last_heartbeat_ms = 0;
ulong last_poll_ms = 0;

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

// Railway-controlled runtime settings. Dashboard changes affect new entries only.
bool runtime_testing_mode = true;
double runtime_fixed_lot = 0.01;
bool runtime_use_equity_scaling = false;
double runtime_equity_per_001 = 1000.0;
int runtime_initial_positions = 1;
int runtime_maximum_positions = 0;
double runtime_maximum_total_lots = 0.0;
int runtime_settings_version = 0;

// Moving straddle / rolling ladder state.
bool scan_dirty = false;
ulong last_telemetry_ms = 0;
datetime last_bracket_refresh_at = 0;
double last_bracket_buy_price = 0.0;
double last_bracket_sell_price = 0.0;
datetime last_add_at = 0;
double last_add_price = 0.0;
ulong newest_ticket = 0;
double newest_leg_peak_profit = 0.0;
double newest_leg_current_profit = 0.0;
datetime newest_leg_open_time = 0;
bool bank_candidate = false;
string bank_candidate_reason = "";
bool reversal_triggered = false;
string engine_state = "WARMING";

// Broker transaction synchronisation. Only one trade request is released at a time.
ulong last_trade_request_ms = 0;
ulong delete_wait_ticket = 0;
ulong delete_wait_started_ms = 0;
int pending_invalid_price_streak = 0;
string pending_sync_state = "IDLE";
ulong pending_retry_after_ms = 0;
bool execution_integrity_breach = false;
string execution_integrity_reason = "";
ulong execution_integrity_position_id = 0;
bool close_pending_cancel_attempted = false;

enum ENUM_CAMPAIGN_PHASE
{
   CAMPAIGN_FLAT = 0,
   CAMPAIGN_BUILDING_STRADDLE = 1,
   CAMPAIGN_STRADDLE_READY = 2,
   CAMPAIGN_OCO_CANCELLING = 3,
   CAMPAIGN_ACTIVE = 4,
   CAMPAIGN_REVERSING = 5,
   CAMPAIGN_CLOSING = 6,
   CAMPAIGN_WAIT_NEXT_CANDLE = 7
};

ENUM_CAMPAIGN_PHASE campaign_phase = CAMPAIGN_FLAT;
string campaign_start_side = "NONE";
string campaign_current_side = "NONE";
string campaign_reversal_target = "NONE";
datetime campaign_triggered_at = 0;
double campaign_trigger_price = 0.0;
double campaign_invalidation_price = 0.0;
int campaign_buy_legs = 0;
int campaign_sell_legs = 0;
int campaign_reversal_count = 0;
datetime campaign_cooldown_until = 0;
double post_campaign_anchor_price = 0.0;
ulong campaign_first_position_id = 0;
datetime campaign_flat_seen_at = 0;

// v2.10 candle-attempt, provisional-lock, ladder and shared-stop state.
double shared_basket_stop = 0.0;
string shared_stop_state = "NOT ACTIVE";
int shared_stop_synced_positions = 0;
datetime straddle_candle_time = 0;
double straddle_anchor_high = 0.0;
double straddle_anchor_low = 0.0;
datetime straddle_buy_synced_candle = 0;
datetime straddle_sell_synced_candle = 0;
ulong newest_position_id = 0;
bool newest_leg_sl_exit_detected = false;
string newest_leg_sl_exit_reason = "";
datetime campaign_attempt_candle = 0;
datetime last_campaign_finished_candle = 0;
double provisional_profit_lock_stop = 0.0;
double provisional_profit_locked_money = 0.0;
string provisional_profit_lock_state = "NOT ACTIVE";

#define HTTP_QUEUE_SIZE 256
string http_queue_endpoint[HTTP_QUEUE_SIZE];
string http_queue_payload[HTTP_QUEUE_SIZE];
int http_queue_attempts[HTTP_QUEUE_SIZE];
int http_queue_head = 0;
int http_queue_tail = 0;
int http_queue_count = 0;
ulong http_queue_retry_after_ms = 0;

int OnInit()
{
   trade_symbol = ResolveTradeSymbol();
   if(trade_symbol == "")
   {
      Print("EVE Momentum v2.10: could not resolve a trading symbol.");
      return INIT_FAILED;
   }
   if(!SymbolSelect(trade_symbol, true))
   {
      Print("EVE Momentum v2.10: cannot select symbol ", trade_symbol);
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
      Print("EVE Momentum v2.10: indicator handle creation failed. Error ", GetLastError());
      return INIT_FAILED;
   }

   remote_autonomous = InpAutonomousAtStart;
   runtime_testing_mode = InpDemoTestingModeDefault;
   runtime_fixed_lot = InpFixedLotPerPosition;
   runtime_use_equity_scaling = InpUseEquityLotScaling;
   runtime_equity_per_001 = InpEquityPer001Lot;
   runtime_initial_positions = InpInitialPositions;
   runtime_maximum_positions = InpMaximumPositions;
   runtime_maximum_total_lots = InpMaximumTotalLots;
   gv_prefix = PersistentPrefix();
   RecoverPersistentState();
   CreatePanel();
   EventSetTimer(1);
   last_event = "EA started; every-candle straddle and continuous pending-stop ladder are active";
   SendHeartbeat();
   last_heartbeat_ms = GetTickCount64();
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
   DetectExecutionIntegrityBreach(tick);
   ManageBasket();
   UpdatePanel();
}

void OnTimer()
{
   // Use a monotonic local clock for communications. TimeCurrent() can stop advancing
   // during broker breaks or quiet periods, which previously made a healthy EA appear offline.
   ulong now_ms = GetTickCount64();
   ulong heartbeat_interval_ms = (ulong)MathMax(1, InpHeartbeatSeconds) * 1000;
   ulong poll_interval_ms = (ulong)MathMax(1, InpCommandPollSeconds) * 1000;
   ulong telemetry_interval_ms = (ulong)MathMax(1, InpTelemetrySeconds) * 1000;

   // At most one blocking WebRequest is allowed per timer pass.
   // Heartbeat is always first priority so the dashboard does not falsely show the EA as disconnected.
   if(last_heartbeat_ms == 0 || now_ms - last_heartbeat_ms >= heartbeat_interval_ms)
   {
      SendHeartbeat();
      last_heartbeat_ms = now_ms;
   }
   else if(last_poll_ms == 0 || now_ms - last_poll_ms >= poll_interval_ms)
   {
      PollRailway();
      last_poll_ms = now_ms;
   }
   else if(http_queue_count > 0)
   {
      FlushOneQueuedPost();
   }
   else if(scan_dirty && have_scan && (last_telemetry_ms == 0 || now_ms - last_telemetry_ms >= telemetry_interval_ms))
   {
      SendScan(last_scan);
      scan_dirty = false;
      last_telemetry_ms = now_ms;
   }

   MqlTick safety_tick;
   if(SymbolInfoTick(trade_symbol, safety_tick))
      DetectExecutionIntegrityBreach(safety_tick);
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
   if(delete_wait_ticket > 0 && trans.order == delete_wait_ticket &&
      (trans.type == TRADE_TRANSACTION_ORDER_DELETE || trans.type == TRADE_TRANSACTION_DEAL_ADD || trans.type == TRADE_TRANSACTION_ORDER_UPDATE))
   {
      if(!OrderSelect(delete_wait_ticket))
      {
         delete_wait_ticket = 0;
         delete_wait_started_ms = 0;
         pending_sync_state = "ORDER STATE CONFIRMED";
      }
   }

   if(trans.type == TRADE_TRANSACTION_REQUEST && request.magic == InpMagicNumber)
   {
      if(TradeResultAccepted(result.retcode) || CloseResultAccepted(result.retcode) || DeleteResultAccepted(result.retcode))
      {
         if(result.retcode != TRADE_RETCODE_NO_CHANGES)
            pending_invalid_price_streak = 0;
      }
      else
      {
         RegisterPendingFailure(result.retcode);
      }
   }

   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != trade_symbol) return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   ulong magic = (ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   ulong position_id = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   if(magic != InpMagicNumber && !PositionIdBelongsToOurBasket(position_id)) return;

   ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   string execution_side = deal_type == DEAL_TYPE_BUY ? "BUY" : deal_type == DEAL_TYPE_SELL ? "SELL" : "OTHER";
   double volume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
   double price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   double net = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_SWAP) + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION) + HistoryDealGetDouble(trans.deal, DEAL_FEE);
   datetime deal_time = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
   ENUM_DEAL_REASON deal_reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal, DEAL_REASON);
   ulong order_ticket = (ulong)HistoryDealGetInteger(trans.deal, DEAL_ORDER);
   string order_role = OrderRoleFromHistory(order_ticket);

   if(entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_INOUT)
   {
      bool first_leg = basket_started_at == 0;
      double previous_trigger = last_add_price;
      if(!first_leg && execution_side == campaign_current_side && previous_trigger <= 0.0)
         previous_trigger = PreviousSameSideEntryPrice(execution_side, position_id);

      string fill_breach = "";
      if(!first_leg && execution_side == campaign_current_side && previous_trigger > 0.0 &&
         !SequentialFillProgressed(execution_side, previous_trigger, price))
      {
         fill_breach = StringFormat("INVALID %s LADDER FILL: %.2f did not progress beyond previous trigger %.2f", execution_side, price, previous_trigger);
      }

      double planned_sl = HistoryOrderStopLoss(order_ticket);
      MqlTick fill_tick;
      if(fill_breach == "" && planned_sl > 0.0 && SymbolInfoTick(trade_symbol, fill_tick))
      {
         if(execution_side == "BUY" && (planned_sl >= price || fill_tick.bid <= planned_sl))
            fill_breach = StringFormat("INVALID BUY FILL/SL: fill %.2f, SL %.2f, Bid %.2f", price, planned_sl, fill_tick.bid);
         if(execution_side == "SELL" && (planned_sl <= price || fill_tick.ask >= planned_sl))
            fill_breach = StringFormat("INVALID SELL FILL/SL: fill %.2f, SL %.2f, Ask %.2f", price, planned_sl, fill_tick.ask);
      }

      if(execution_side == "BUY") campaign_buy_legs++;
      if(execution_side == "SELL") campaign_sell_legs++;
      basket_positions_opened++;
      basket_max_concurrent_positions = MathMax(basket_max_concurrent_positions, CountOurPositions());

      if(fill_breach != "")
      {
         if(first_leg)
         {
            basket_started_at = deal_time;
            basket_id = ((long)basket_started_at * 1000) + (long)(trans.deal % 1000);
            basket_side = execution_side;
            campaign_start_side = execution_side;
            campaign_current_side = execution_side;
            campaign_triggered_at = deal_time;
            campaign_trigger_price = price;
            campaign_first_position_id = position_id;
            campaign_attempt_candle = iTime(trade_symbol, InpExecutionTimeframe, 0);
            provisional_profit_lock_stop = 0.0;
            provisional_profit_locked_money = 0.0;
            provisional_profit_lock_state = "WAITING FOR POSITION 1 PROFIT";
            basket_entry_atr = CurrentOrderAtr();
            basket_entry_reason = "FIRST TRIGGER FAILED EXECUTION INTEGRITY";
            baskets_today++;
         }
         execution_integrity_breach = true;
         execution_integrity_reason = fill_breach + " - CANCEL ALL PENDING ORDERS AND CLOSE THE FULL BASKET";
         execution_integrity_position_id = position_id;
         campaign_phase = CAMPAIGN_CLOSING;
         pending_sync_state = "EXECUTION INTEGRITY BREACH";
         last_event = execution_integrity_reason;
         newest_position_id = position_id;
         SendEvent("execution-integrity", last_event);
         SendLegRecord("OPEN-INVALID", execution_side, trans.deal, position_id, volume, price, 0.0, order_role + " | " + fill_breach);
         SavePersistentState();
         return;
      }

      if(first_leg)
      {
         basket_started_at = deal_time;
         basket_id = ((long)basket_started_at * 1000) + (long)(trans.deal % 1000);
         basket_side = execution_side;
         campaign_start_side = execution_side;
         campaign_current_side = execution_side;
         campaign_reversal_target = "NONE";
         campaign_triggered_at = deal_time;
         campaign_trigger_price = price;
         campaign_first_position_id = position_id;
         campaign_attempt_candle = iTime(trade_symbol, InpExecutionTimeframe, 0);
         provisional_profit_lock_stop = 0.0;
         provisional_profit_locked_money = 0.0;
         provisional_profit_lock_state = "WAITING FOR POSITION 1 PROFIT";
         campaign_invalidation_price = 0.0;
         campaign_phase = CAMPAIGN_OCO_CANCELLING; // v2.10: first of two same-side confirmations
         basket_entry_atr = CurrentOrderAtr();
         basket_entry_score = execution_side == "BUY" ? last_scan.buy_score : last_scan.sell_score;
         basket_opposite_score = execution_side == "BUY" ? last_scan.sell_score : last_scan.buy_score;
         basket_entry_regime = have_scan ? last_scan.regime : "UNFILTERED";
         basket_entry_state = have_scan ? last_scan.momentum_state : "PRICE TRIGGER";
         basket_entry_reason = "FIRST CANDLE STOP TRIGGER - DIRECTION PROVISIONAL";
         baskets_today++;
         pending_sync_state = "FIRST TRIGGER - WAITING SECOND";
         last_event = StringFormat("%s first stop triggered at %.2f; opposite stop remains until the second %s trigger", execution_side, price, execution_side);
      }
      else if(!close_pending && campaign_phase != CAMPAIGN_CLOSING)
      {
         if(campaign_phase == CAMPAIGN_OCO_CANCELLING)
         {
            if(execution_side == campaign_current_side)
            {
               int same_positions = CountOurPositionsBySide(execution_side);
               if(same_positions >= 2)
               {
                  campaign_phase = CAMPAIGN_ACTIVE;
                  pending_sync_state = "SECOND TRIGGER CONFIRMED";
                  last_event = StringFormat("Second %s stop triggered at %.2f; direction confirmed and opposite stop will now be cancelled", execution_side, price);
                  SendEvent("confirmed", last_event);
               }
            }
            else
            {
               string failed_side = campaign_current_side;
               campaign_current_side = execution_side;
               basket_side = execution_side;
               campaign_reversal_count++;
               reversal_triggered = true;
               campaign_triggered_at = deal_time;
               campaign_trigger_price = price;
               campaign_phase = CAMPAIGN_OCO_CANCELLING;
               pending_sync_state = "FALSE BREAKOUT FLIP";
               last_event = StringFormat("%s opposite stop triggered before the second %s; failed %s leg will close and %s becomes provisional", execution_side, failed_side, failed_side, execution_side);
               SendEvent("false-breakout-flip", last_event);
            }
         }
         else if(campaign_phase == CAMPAIGN_ACTIVE && execution_side != campaign_current_side)
         {
            pending_sync_state = "LATE OPPOSITE TRIGGER - CLEANING";
            last_event = StringFormat("Late %s stop triggered after %s confirmation; confirmed %s ladder is retained and the accidental leg will close", execution_side, campaign_current_side, campaign_current_side);
            SendEvent("late-opposite", last_event);
         }
      }

      if(execution_side == campaign_current_side && !close_pending && campaign_phase != CAMPAIGN_CLOSING)
      {
         newest_position_id = position_id;
         last_add_at = TimeCurrent();
         last_add_price = price;
         last_entry_ms = GetTickCount64();
         shared_basket_stop = 0.0;
         shared_stop_state = "NEW FILL - RECALCULATING SHARED BASKET SL";
         shared_stop_synced_positions = 0;
      }

      SendLegRecord("OPEN", execution_side, trans.deal, position_id, volume, price, 0.0, order_role + " | " + DealReasonText(deal_reason));
      SavePersistentState();
      return;
   }

   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT)
   {
      string position_side = PositionEntrySideById(position_id);
      if(position_side == "NONE") position_side = execution_side == "BUY" ? "SELL" : execution_side == "SELL" ? "BUY" : execution_side;
      SendLegRecord("CLOSE", position_side, trans.deal, position_id, volume, price, net, DealReasonText(deal_reason));

      if(deal_reason == DEAL_REASON_SL && position_id > 0 && basket_started_at > 0)
      {
         newest_leg_sl_exit_detected = true;
         newest_leg_sl_exit_reason = StringFormat("SHARED %s BASKET STOP LOSS HIT - CLOSE/CLEAR THE FULL CAMPAIGN", position_side);
         campaign_phase = CAMPAIGN_CLOSING;
         pending_sync_state = "SHARED SL - BANKING BASKET";
         last_event = newest_leg_sl_exit_reason;
         SendEvent("shared-sl", last_event);
      }

      if(CountOurPositions() == 0 && basket_started_at > 0 && !close_pending)
      {
         campaign_phase = CAMPAIGN_CLOSING;
         pending_sync_state = "CLEARING CAMPAIGN ORDERS";
      }
      SavePersistentState();
   }
}


double MinimumSequentialFillPrice()
{
   double tick_size = SymbolInfoDouble(trade_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0) tick_size = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   return MathMax(tick_size, SymbolInfoDouble(trade_symbol, SYMBOL_POINT)) * MathMax(1, InpMinimumSequentialFillTicks);
}

double PreviousSameSideEntryPrice(string side, ulong exclude_identifier)
{
   bool found = false;
   double selected = 0.0;
   datetime latest_time = 0;
   long latest_msc = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(identifier == exclude_identifier) continue;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string position_side = type == POSITION_TYPE_BUY ? "BUY" : "SELL";
      if(position_side != side) continue;
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      long opened_msc = PositionGetInteger(POSITION_TIME_MSC);
      if(!found || opened > latest_time || (opened == latest_time && opened_msc > latest_msc))
      {
         found = true;
         latest_time = opened;
         latest_msc = opened_msc;
         selected = PositionGetDouble(POSITION_PRICE_OPEN);
      }
   }
   return selected;
}

bool SequentialFillProgressed(string side, double previous_price, double new_price)
{
   double minimum = MinimumSequentialFillPrice();
   if(side == "BUY") return new_price >= previous_price + minimum - 0.0000001;
   if(side == "SELL") return new_price <= previous_price - minimum + 0.0000001;
   return false;
}

double HistoryOrderStopLoss(ulong order_ticket)
{
   if(order_ticket == 0 || !HistoryOrderSelect(order_ticket)) return 0.0;
   return HistoryOrderGetDouble(order_ticket, ORDER_SL);
}

void FlagExecutionIntegrityBreach(string reason, ulong position_id)
{
   if(close_pending || execution_integrity_breach) return;
   execution_integrity_breach = true;
   execution_integrity_reason = reason + " - CANCEL ALL PENDING ORDERS AND CLOSE THE FULL BASKET";
   execution_integrity_position_id = position_id;
   campaign_phase = CAMPAIGN_CLOSING;
   pending_sync_state = "EXECUTION INTEGRITY BREACH";
   last_event = execution_integrity_reason;
   SendEvent("execution-integrity", last_event);
}

bool DetectExecutionIntegrityBreach(const MqlTick &tick)
{
   if(close_pending || CountOurPositions() == 0) return false;

   double tick_size = SymbolInfoDouble(trade_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0) tick_size = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   double tolerance = MathMax(tick_size * 0.25, SymbolInfoDouble(trade_symbol, SYMBOL_POINT) * 0.25);

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string side = type == POSITION_TYPE_BUY ? "BUY" : "SELL";
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      int age = (int)MathMax(0, TimeCurrent() - opened);

      if(sl <= 0.0)
      {
         if(age >= MathMax(0, InpMissingSLGraceSeconds))
         {
            FlagExecutionIntegrityBreach(StringFormat("%s position %I64u has no broker-side SL", side, ticket), identifier);
            return true;
         }
         continue;
      }

      bool is_newest = identifier > 0 && identifier == newest_position_id;
      int same_side_positions = CountOurPositionsBySide(side);

      if(type == POSITION_TYPE_BUY)
      {
         // A single provisional BUY is allowed to move its SL above entry to lock profit.
         // In a confirmed basket, the newest BUY must still have the shared SL below
         // its own entry; older BUY positions may have the shared SL above entry.
         if(is_newest && same_side_positions >= 2 && sl >= entry - tolerance)
         {
            FlagExecutionIntegrityBreach(StringFormat("Newest BUY %I64u has shared SL on the wrong side: entry %.2f / SL %.2f", ticket, entry, sl), identifier);
            return true;
         }
         if(tick.bid <= sl + tolerance)
         {
            FlagExecutionIntegrityBreach(StringFormat("BUY position %I64u remains open after Bid %.2f crossed SL %.2f", ticket, tick.bid, sl), identifier);
            return true;
         }
      }
      else
      {
         // A single provisional SELL is allowed to move its SL below entry to lock profit.
         // In a confirmed basket, the newest SELL must retain the shared stop above
         // its own entry; older SELL positions may have the shared SL below entry.
         if(is_newest && same_side_positions >= 2 && sl <= entry + tolerance)
         {
            FlagExecutionIntegrityBreach(StringFormat("Newest SELL %I64u has shared SL on the wrong side: entry %.2f / SL %.2f", ticket, entry, sl), identifier);
            return true;
         }
         if(tick.ask >= sl - tolerance)
         {
            FlagExecutionIntegrityBreach(StringFormat("SELL position %I64u remains open after Ask %.2f crossed SL %.2f", ticket, tick.ask, sl), identifier);
            return true;
         }
      }
   }

   string side = campaign_current_side;
   if(side == "BUY" || side == "SELL")
   {
      bool found_latest = false, found_previous = false;
      datetime latest_time = 0, previous_time = 0;
      long latest_msc = 0, previous_msc = 0;
      double latest_price = 0.0, previous_price = 0.0;
      ulong latest_identifier = 0;

      for(int i=PositionsTotal()-1; i>=0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         string position_side = type == POSITION_TYPE_BUY ? "BUY" : "SELL";
         if(position_side != side) continue;
         datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
         long opened_msc = PositionGetInteger(POSITION_TIME_MSC);
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);

         if(!found_latest || opened > latest_time || (opened == latest_time && opened_msc > latest_msc))
         {
            if(found_latest)
            {
               found_previous = true;
               previous_time = latest_time;
               previous_msc = latest_msc;
               previous_price = latest_price;
            }
            found_latest = true;
            latest_time = opened;
            latest_msc = opened_msc;
            latest_price = entry;
            latest_identifier = identifier;
         }
         else if(!found_previous || opened > previous_time || (opened == previous_time && opened_msc > previous_msc))
         {
            found_previous = true;
            previous_time = opened;
            previous_msc = opened_msc;
            previous_price = entry;
         }
      }

      if(found_latest && found_previous && !SequentialFillProgressed(side, previous_price, latest_price))
      {
         FlagExecutionIntegrityBreach(StringFormat("%s ladder sequence failed: newest fill %.2f did not progress beyond previous fill %.2f", side, latest_price, previous_price), latest_identifier);
         return true;
      }
   }

   return false;
}


string CampaignPhaseText()
{
   if(campaign_phase == CAMPAIGN_FLAT) return "FLAT";
   if(campaign_phase == CAMPAIGN_BUILDING_STRADDLE) return "BUILDING STRADDLE";
   if(campaign_phase == CAMPAIGN_STRADDLE_READY) return "STRADDLE READY";
   if(campaign_phase == CAMPAIGN_OCO_CANCELLING) return "PROVISIONAL 1/2";
   if(campaign_phase == CAMPAIGN_ACTIVE) return "ACTIVE";
   if(campaign_phase == CAMPAIGN_REVERSING) return "REVERSING";
   if(campaign_phase == CAMPAIGN_CLOSING) return "CLOSING";
   if(campaign_phase == CAMPAIGN_WAIT_NEXT_CANDLE) return "WAIT NEXT CANDLE";
   return "UNKNOWN";
}

double CampaignInvalidationFromEntry(string side, double entry_price)
{
   double atr_value = have_scan && last_scan.atr > 0 ? last_scan.atr : basket_entry_atr;
   double distance = MathMax(PendingEntryDistancePrice(), atr_value > 0 ? atr_value * InpReverseStopATR : InpBracketMinimumDistancePrice);
   if(side == "BUY") return NormalizePrice(entry_price - distance);
   if(side == "SELL") return NormalizePrice(entry_price + distance);
   return 0.0;
}

double CampaignInvalidationFromOpenPositions(string side)
{
   double selected = 0.0;
   datetime earliest = 0;
   double earliest_entry = 0.0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string position_side = type == POSITION_TYPE_BUY ? "BUY" : "SELL";
      if(position_side != side) continue;

      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      double sl = PositionGetDouble(POSITION_SL);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      if(earliest == 0 || opened < earliest)
      {
         earliest = opened;
         earliest_entry = entry;
      }

      if(sl > 0)
      {
         if(selected == 0) selected = sl;
         else if(side == "BUY") selected = MathMin(selected, sl);
         else selected = MathMax(selected, sl);
      }
   }
   if(selected > 0) return NormalizePrice(selected);
   if(earliest_entry > 0) return CampaignInvalidationFromEntry(side, earliest_entry);
   return 0.0;
}

string OrderRoleFromHistory(ulong order_ticket)
{
   if(order_ticket == 0) return "UNKNOWN";
   string comment = "";
   if(HistoryOrderSelect(order_ticket))
      comment = HistoryOrderGetString(order_ticket, ORDER_COMMENT);
   else if(OrderSelect(order_ticket))
      comment = OrderGetString(ORDER_COMMENT);

   if(StringFind(comment, "INIT") >= 0 || StringFind(comment, "BRK") >= 0) return "INITIAL";
   if(StringFind(comment, "CONF") >= 0) return "CONFIRMATION";
   if(StringFind(comment, "LAD") >= 0) return "LADDER";
   if(StringFind(comment, "REV") >= 0) return "CONFIRMATION";
   return "UNKNOWN";
}


string PositionEntrySideById(ulong position_id)
{
   if(position_id == 0) return "NONE";
   datetime from = basket_started_at > 300 ? basket_started_at - 300 : 0;
   if(!HistorySelect(from, TimeCurrent() + 60)) return "NONE";
   datetime earliest = 0;
   string side = "NONE";
   int total = HistoryDealsTotal();
   for(int i=0; i<total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID) != position_id) continue;
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) continue;
      datetime at = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      if(earliest != 0 && at >= earliest) continue;
      ENUM_DEAL_TYPE type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE);
      side = type == DEAL_TYPE_BUY ? "BUY" : type == DEAL_TYPE_SELL ? "SELL" : "NONE";
      earliest = at;
   }
   return side;
}

int CountOurPositionsBySide(string wanted_side)
{
   int count = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string side = type == POSITION_TYPE_BUY ? "BUY" : "SELL";
      if(side == wanted_side) count++;
   }
   return count;
}

bool SelectedOrderMatchesRole(string role)
{
   string comment = OrderGetString(ORDER_COMMENT);
   if(role == "INITIAL") return StringFind(comment, "INIT") >= 0 || StringFind(comment, "BRK") >= 0;
   if(role == "CONFIRMATION") return StringFind(comment, "CONF") >= 0 || StringFind(comment, "REV") >= 0;
   if(role == "LADDER") return StringFind(comment, "LAD") >= 0;
   if(role == "ENTRY-BRACKET") return StringFind(comment, "INIT") >= 0 || StringFind(comment, "BRK") >= 0;
   if(role == "REVERSAL") return StringFind(comment, "CONF") >= 0 || StringFind(comment, "REV") >= 0;
   return true;
}


int CountPendingByRole(string role)
{
   int count = 0;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket) || !IsOurSelectedOrder()) continue;
      if(SelectedOrderMatchesRole(role)) count++;
   }
   return count;
}

bool CancelPendingByRole(string role)
{
   if(delete_wait_ticket > 0)
   {
      if(!OrderSelect(delete_wait_ticket))
      {
         delete_wait_ticket = 0;
         delete_wait_started_ms = 0;
      }
      else if(GetTickCount64() - delete_wait_started_ms < (ulong)MathMax(1, InpOcoCancelTimeoutSeconds) * 1000)
         return false;
      else
      {
         delete_wait_ticket = 0;
         delete_wait_started_ms = 0;
      }
   }

   if(!TradeRequestAvailable()) return CountPendingByRole(role) == 0;

   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket) || !IsOurSelectedOrder()) continue;
      if(!SelectedOrderMatchesRole(role)) continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      double volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
      double price = OrderGetDouble(ORDER_PRICE_OPEN);

      if(PendingOrderInsideFreeze(type, price))
      {
         pending_sync_state = "WAITING BROKER FREEZE";
         return false;
      }

      MarkTradeRequest();
      bool submitted = trade.OrderDelete(ticket);
      uint code = trade.ResultRetcode();
      if(!submitted || !DeleteResultAccepted(code))
      {
         RegisterPendingFailure(code);
         SendOrderActivity("DELETE-FAILED", role, type, ticket, volume, price, trade.ResultRetcodeDescription());
         return false;
      }

      delete_wait_ticket = ticket;
      delete_wait_started_ms = GetTickCount64();
      SendOrderActivity("CANCEL-REQUESTED", role, type, ticket, volume, price, "OCO/campaign role cleanup");
      return false;
   }

   return true;
}



string PendingSideFromType(ENUM_ORDER_TYPE type)
{
   if(type == ORDER_TYPE_BUY_STOP) return "BUY";
   if(type == ORDER_TYPE_SELL_STOP) return "SELL";
   return "NONE";
}

ENUM_ORDER_TYPE StopTypeForSide(string side)
{
   return side == "BUY" ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP;
}

string OppositeSide(string side)
{
   return side == "BUY" ? "SELL" : "BUY";
}

string SelectedPendingRole()
{
   string comment = OrderGetString(ORDER_COMMENT);
   if(StringFind(comment, "INIT") >= 0 || StringFind(comment, "BRK") >= 0) return "INITIAL";
   if(StringFind(comment, "CONF") >= 0 || StringFind(comment, "REV") >= 0) return "CONFIRMATION";
   if(StringFind(comment, "LAD") >= 0) return "LADDER";
   return "UNKNOWN";
}

int CountPendingBySide(string side)
{
   int count = 0;
   ENUM_ORDER_TYPE wanted = StopTypeForSide(side);
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket) || !IsOurSelectedOrder()) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) == wanted) count++;
   }
   return count;
}

int CountPendingBySideAndRole(string side, string role)
{
   int count = 0;
   ENUM_ORDER_TYPE wanted = StopTypeForSide(side);
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket) || !IsOurSelectedOrder()) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != wanted) continue;
      if(SelectedPendingRole() == role) count++;
   }
   return count;
}

double ExtremePendingPrice(string side, string role)
{
   double value = 0.0;
   ENUM_ORDER_TYPE wanted = StopTypeForSide(side);
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket) || !IsOurSelectedOrder()) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != wanted) continue;
      if(role != "" && SelectedPendingRole() != role) continue;
      double price = OrderGetDouble(ORDER_PRICE_OPEN);
      if(value == 0.0) value = price;
      else if(side == "BUY") value = MathMax(value, price);
      else value = MathMin(value, price);
   }
   return value;
}

bool DeleteSelectedPending(string reason)
{
   ulong ticket = (ulong)OrderGetInteger(ORDER_TICKET);
   ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   double volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
   double price = OrderGetDouble(ORDER_PRICE_OPEN);
   string role = SelectedPendingRole();

   if(PendingOrderInsideFreeze(type, price))
   {
      pending_sync_state = "WAITING BROKER FREEZE";
      return false;
   }
   if(!TradeRequestAvailable()) return false;

   MarkTradeRequest();
   bool submitted = trade.OrderDelete(ticket);
   uint code = trade.ResultRetcode();
   if(!submitted || !DeleteResultAccepted(code))
   {
      RegisterPendingFailure(code);
      SendOrderActivity("DELETE-FAILED", role, type, ticket, volume, price, reason + " | " + trade.ResultRetcodeDescription());
      return false;
   }

   delete_wait_ticket = ticket;
   delete_wait_started_ms = GetTickCount64();
   SendOrderActivity("CANCEL-REQUESTED", role, type, ticket, volume, price, reason);
   return true;
}

bool DeleteOneForFlatStraddle()
{
   bool kept_buy = false;
   bool kept_sell = false;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket) || !IsOurSelectedOrder()) continue;
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      string role = SelectedPendingRole();
      bool keep = false;
      if(role == "INITIAL" && type == ORDER_TYPE_BUY_STOP && !kept_buy) { kept_buy = true; keep = true; }
      if(role == "INITIAL" && type == ORDER_TYPE_SELL_STOP && !kept_sell) { kept_sell = true; keep = true; }
      if(keep) continue;
      DeleteSelectedPending("fresh candle straddle cleanup");
      return true;
   }
   return false;
}

bool DeleteOneForProvisional(string side)
{
   bool kept_same = false;
   bool kept_opposite = false;
   ENUM_ORDER_TYPE same_type = StopTypeForSide(side);

   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket) || !IsOurSelectedOrder()) continue;
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      string role = SelectedPendingRole();
      bool same = type == same_type;
      bool allowed_role = role == "INITIAL" || role == "CONFIRMATION";
      bool keep = false;

      if(allowed_role && same && !kept_same) { kept_same = true; keep = true; }
      else if(allowed_role && !same && !kept_opposite) { kept_opposite = true; keep = true; }

      if(keep) continue;
      DeleteSelectedPending("provisional two-sided confirmation cleanup");
      return true;
   }
   return false;
}

bool DeleteOneForActiveLadder(string side)
{
   ENUM_ORDER_TYPE wanted = StopTypeForSide(side);
   bool kept_one = false;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket) || !IsOurSelectedOrder()) continue;
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      string role = SelectedPendingRole();
      if(type == wanted && role == "LADDER" && !kept_one)
      {
         kept_one = true;
         continue;
      }
      DeleteSelectedPending("confirmed campaign permits exactly one same-side ladder stop ahead");
      return true;
   }
   return false;
}

double CurrentOrderAtr()
{
   if(have_scan && last_scan.atr > 0) return last_scan.atr;
   if(atr_handle != INVALID_HANDLE)
   {
      double values[1];
      if(CopyBuffer(atr_handle, 0, 0, 1, values) == 1 && values[0] > 0)
         return values[0];
   }
   return MathMax(InpFallbackATRPrice, SymbolInfoDouble(trade_symbol, SYMBOL_POINT) * 100.0);
}

double LadderSpacingPrice(string side)
{
   double tick_size = SymbolInfoDouble(trade_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0) tick_size = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   double lock_fraction = MathMax(0.10, MathMin(0.80, InpNewestSLPreviousLegLockFraction));
   double broker_sl_distance = BrokerStopsDistancePrice() + PendingAdaptiveBufferPrice() + 2.0 * tick_size;
   double gap_for_stop_geometry = broker_sl_distance / MathMax(0.20, 1.0 - lock_fraction);
   double gap = MathMax(gap_for_stop_geometry, MathMax(InpLadderMinimumSpacingPrice, CurrentOrderAtr() * InpAddSpacingATR));

   if(side != "BUY" && side != "SELL" || CountOurPositionsBySide(side) <= 0) return gap;
   double previous_entry = last_add_price > 0.0 ? last_add_price : campaign_trigger_price;
   if(previous_entry <= 0.0) return gap;

   double next_volume = CalculateLegLot();
   double required_gross = MathMax(0.0, InpSharedSLMinimumNetProfitMoney) + SharedStopCommissionReserveMoney(next_volume);
   double point = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   double reserve = MathMax(0, InpSharedSLSlippageReservePoints) * point;

   for(int i=0; i<96; i++)
   {
      double next_entry = side == "BUY" ? previous_entry + gap : previous_entry - gap;
      double candidate = side == "BUY"
         ? previous_entry + gap * lock_fraction + reserve
         : previous_entry - gap * lock_fraction - reserve;
      double projected = 0.0;
      bool profit_ok = ProjectedBasketProfitAtPrice(side, candidate, next_entry, next_volume, projected) && projected >= required_gross;
      bool geometry_ok = side == "BUY"
         ? (candidate > previous_entry && candidate < next_entry - broker_sl_distance)
         : (candidate < previous_entry && candidate > next_entry + broker_sl_distance);
      if(profit_ok && geometry_ok) return gap;
      gap = MathMax(gap + tick_size, gap * 1.12);
   }
   return gap;
}
double StraddleDistancePrice()
{
   return MathMax(InpBracketMinimumDistancePrice, MathMax(CurrentOrderAtr() * InpBracketDistanceATR, PendingEntryDistancePrice()));
}

void ResetStraddleAnchor()
{
   straddle_candle_time = 0;
   straddle_anchor_high = 0.0;
   straddle_anchor_low = 0.0;
   straddle_buy_synced_candle = 0;
   straddle_sell_synced_candle = 0;
}

bool CaptureCurrentCandleAnchor()
{
   datetime bar = iTime(trade_symbol, InpExecutionTimeframe, 0);
   MqlTick tick;
   if(bar <= 0 || !SymbolInfoTick(trade_symbol, tick)) return false;
   double high = iHigh(trade_symbol, InpExecutionTimeframe, 0);
   double low = iLow(trade_symbol, InpExecutionTimeframe, 0);
   if(high <= 0) high = tick.ask;
   if(low <= 0) low = tick.bid;
   straddle_candle_time = bar;
   straddle_anchor_high = MathMax(high, tick.ask);
   straddle_anchor_low = MathMin(low, tick.bid);
   return true;
}

bool BasicTradingAvailable()
{
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) { last_event = "MT5 disconnected"; return false; }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) { last_event = "AutoTrading not allowed"; return false; }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) { last_event = "EA trading permission disabled"; return false; }
   MqlTick tick;
   if(!SymbolInfoTick(trade_symbol, tick)) { last_event = "Waiting for a market tick"; return false; }
   return true;
}

double ProvisionalGuardPrice(string guard_side)
{
   MqlTick tick;
   if(!SymbolInfoTick(trade_symbol, tick)) return 0.0;
   double distance = StraddleDistancePrice();

   if(guard_side == "BUY")
   {
      if(last_bracket_buy_price > tick.ask) return last_bracket_buy_price;
      return tick.ask + distance;
   }

   if(last_bracket_sell_price > 0 && last_bracket_sell_price < tick.bid) return last_bracket_sell_price;
   return tick.bid - distance;
}

bool EntrySpreadSafe(string &reason)
{
   reason = "";
   if(!InpPausePendingEntriesOnWideSpread) return true;

   double spread = CurrentSpreadPoints();
   double median = MedianSpreadPoints();
   bool absolute_bad = InpAbsoluteMaximumSpreadPoints > 0 && spread > InpAbsoluteMaximumSpreadPoints;
   bool relative_bad = spread_sample_count >= 20 && median > 0.0 && spread > median * MathMax(1.05, InpSpreadMedianMultiplier);
   if(!absolute_bad && !relative_bad) return true;

   reason = StringFormat("WIDE SPREAD SAFETY: %.1f points versus %.1f median", spread, median);
   return false;
}

bool FindSinglePositionBySide(string side, ulong &ticket, double &entry, double &volume, double &sl, double &tp)
{
   ticket = 0;
   entry = 0.0;
   volume = 0.0;
   sl = 0.0;
   tp = 0.0;
   int found = 0;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong current = PositionGetTicket(i);
      if(current == 0 || !PositionSelectByTicket(current) || !IsOurSelectedPosition()) continue;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string position_side = type == POSITION_TYPE_BUY ? "BUY" : "SELL";
      if(position_side != side) continue;
      found++;
      ticket = current;
      entry = PositionGetDouble(POSITION_PRICE_OPEN);
      volume = PositionGetDouble(POSITION_VOLUME);
      sl = PositionGetDouble(POSITION_SL);
      tp = PositionGetDouble(POSITION_TP);
   }
   return found == 1 && ticket > 0;
}

double RoundProtectiveStop(string side, double price)
{
   double tick_size = SymbolInfoDouble(trade_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0) tick_size = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   if(tick_size <= 0.0) return NormalizePrice(price);
   if(side == "BUY")
      return NormalizePrice(MathCeil(price / tick_size - 0.0000000001) * tick_size);
   return NormalizePrice(MathFloor(price / tick_size + 0.0000000001) * tick_size);
}

bool CalculateProvisionalLockTarget(string side, double required_gross, double &target, string &reason)
{
   target = 0.0;
   reason = "";

   ulong ticket = 0;
   double entry = 0.0, volume = 0.0, existing_sl = 0.0, tp = 0.0;
   if(!FindSinglePositionBySide(side, ticket, entry, volume, existing_sl, tp))
   {
      reason = "Position 1 profit lock requires exactly one same-side position";
      return false;
   }

   MqlTick tick;
   if(!SymbolInfoTick(trade_symbol, tick)) return false;
   ENUM_ORDER_TYPE calc_type = side == "BUY" ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double current_close = side == "BUY" ? tick.bid : tick.ask;
   double current_gross = 0.0;
   if(!OrderCalcProfit(calc_type, trade_symbol, volume, entry, current_close, current_gross)) return false;
   if(current_gross + 0.0001 < required_gross)
   {
      reason = StringFormat("Current Position 1 gross $%.2f is below required lock $%.2f", current_gross, required_gross);
      return false;
   }

   double low = 0.0, high = 0.0, profit = 0.0;
   if(side == "BUY")
   {
      low = entry;
      high = current_close;
      for(int i=0; i<64; i++)
      {
         double mid = (low + high) * 0.5;
         if(!OrderCalcProfit(calc_type, trade_symbol, volume, entry, mid, profit)) return false;
         if(profit >= required_gross) high = mid;
         else low = mid;
      }
      target = high;
   }
   else
   {
      low = current_close;
      high = entry;
      for(int i=0; i<64; i++)
      {
         double mid = (low + high) * 0.5;
         if(!OrderCalcProfit(calc_type, trade_symbol, volume, entry, mid, profit)) return false;
         if(profit >= required_gross) low = mid;
         else high = mid;
      }
      target = low;
   }

   double reserve = MathMax(0, InpSharedSLSlippageReservePoints) * SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   target = side == "BUY" ? target + reserve : target - reserve;
   target = RoundProtectiveStop(side, target);

   double tick_size = SymbolInfoDouble(trade_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0) tick_size = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   double modify_distance = MathMax(BrokerStopsDistancePrice(), BrokerFreezeDistancePrice()) + 2.0 * tick_size;
   if(side == "BUY" && target >= tick.bid - modify_distance)
   {
      reason = StringFormat("Waiting for Bid to move far enough above Position 1 lock %.2f", target);
      return false;
   }
   if(side == "SELL" && target <= tick.ask + modify_distance)
   {
      reason = StringFormat("Waiting for Ask to move far enough below Position 1 lock %.2f", target);
      return false;
   }

   return target > 0.0;
}

bool MaintainProvisionalProfitLock()
{
   string side = campaign_current_side;
   if(side != "BUY" && side != "SELL" || CountOurPositionsBySide(side) != 1) return false;

   UpdateNewestCanary();
   double peak = newest_leg_peak_profit;
   if(peak + 0.0001 < MathMax(0.0, InpProvisionalLockTriggerMoney))
   {
      provisional_profit_lock_state = StringFormat("WAITING: Position 1 peak $%.2f / trigger $%.2f", peak, InpProvisionalLockTriggerMoney);
      return false;
   }

   ulong ticket = 0;
   double entry = 0.0, volume = 0.0, existing_sl = 0.0, tp = 0.0;
   if(!FindSinglePositionBySide(side, ticket, entry, volume, existing_sl, tp)) return false;

   double keep_fraction = 1.0 - MathMax(0.0, MathMin(95.0, InpProvisionalLockGivebackPercent)) / 100.0;
   double desired_net = MathMax(MathMax(0.0, InpProvisionalLockMinimumMoney), peak * keep_fraction);
   double commission_reserve = MathMax(0.0, InpSharedSLCommissionReservePerLot) * volume;
   double required_gross = desired_net + commission_reserve;
   double estimated_current_net = newest_leg_current_profit - commission_reserve;

   bool already_profit_locked = side == "BUY" ? existing_sl > entry : existing_sl > 0.0 && existing_sl < entry;
   if(!already_profit_locked && estimated_current_net <= desired_net + 0.0001)
   {
      provisional_profit_lock_state = StringFormat("Position 1 gave back to $%.2f before broker SL could be armed; banking now", estimated_current_net);
      BankBasket("POSITION 1 PROFIT GIVEBACK EXIT", BasketProfit());
      return true;
   }

   double target = 0.0;
   string reason = "";
   if(!CalculateProvisionalLockTarget(side, required_gross, target, reason))
   {
      provisional_profit_lock_state = reason;
      // Once Position 1 has earned enough to activate its profit lock, do not arm
      // Position 2 with a weaker stop. Wait until the promised lock is broker-valid.
      return true;
   }

   bool existing_is_stronger = existing_sl > 0.0 && (side == "BUY" ? existing_sl >= target : existing_sl <= target);
   if(existing_is_stronger)
   {
      provisional_profit_lock_stop = existing_sl;
      provisional_profit_locked_money = desired_net;
      provisional_profit_lock_state = StringFormat("POSITION 1 PROFIT LOCKED: SL %.2f protects about $%.2f net", existing_sl, desired_net);
      return false;
   }

   if(!TradeRequestAvailable()) return true;
   MarkTradeRequest();
   bool submitted = trade.PositionModify(ticket, target, tp);
   uint code = trade.ResultRetcode();
   if(!submitted || !TradeResultAccepted(code))
   {
      RegisterPendingFailure(code);
      provisional_profit_lock_state = StringFormat("Position 1 SL modify failed: %u %s", code, trade.ResultRetcodeDescription());
      last_event = provisional_profit_lock_state;
      return true;
   }

   provisional_profit_lock_stop = target;
   provisional_profit_locked_money = desired_net;
   provisional_profit_lock_state = StringFormat("POSITION 1 PROFIT LOCK ARMED: SL %.2f protects about $%.2f net", target, desired_net);
   pending_sync_state = provisional_profit_lock_state;
   last_event = provisional_profit_lock_state;
   SendEvent("provisional-lock", last_event);
   return true;
}

bool FindPendingBySideAndRole(string side, string role, ulong &ticket, double &entry, double &sl)
{
   ticket = 0;
   entry = 0.0;
   sl = 0.0;
   ENUM_ORDER_TYPE wanted = StopTypeForSide(side);
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong current = OrderGetTicket(i);
      if(current == 0 || !OrderSelect(current) || !IsOurSelectedOrder()) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != wanted) continue;
      if(SelectedPendingRole() != role) continue;
      ticket = current;
      entry = OrderGetDouble(ORDER_PRICE_OPEN);
      sl = OrderGetDouble(ORDER_SL);
      return true;
   }
   return false;
}

bool SynchronizeExistingPositionsToTarget(string side, double target, string purpose)
{
   if(side != "BUY" && side != "SELL" || target <= 0.0) return false;
   MqlTick tick;
   if(!SymbolInfoTick(trade_symbol, tick)) return false;

   double tick_size = SymbolInfoDouble(trade_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0) tick_size = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   double modify_distance = MathMax(BrokerStopsDistancePrice(), BrokerFreezeDistancePrice()) + 2.0 * tick_size;
   if(side == "BUY" && target >= tick.bid - modify_distance)
   {
      pending_sync_state = StringFormat("%s: waiting for Bid above pre-armed SL %.2f", purpose, target);
      return false;
   }
   if(side == "SELL" && target <= tick.ask + modify_distance)
   {
      pending_sync_state = StringFormat("%s: waiting for Ask below pre-armed SL %.2f", purpose, target);
      return false;
   }

   int total = CountOurPositionsBySide(side);
   int synced = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string position_side = type == POSITION_TYPE_BUY ? "BUY" : "SELL";
      if(position_side != side) continue;

      if(PositionHasSharedStop(ticket, target))
      {
         synced++;
         continue;
      }

      double existing_sl = PositionGetDouble(POSITION_SL);
      bool existing_is_stronger = existing_sl > 0.0 && (side == "BUY" ? existing_sl > target : existing_sl < target);
      if(existing_is_stronger)
      {
         pending_sync_state = purpose + ": existing stop is stronger; recalculating next pending level";
         return false;
      }

      if(!TradeRequestAvailable()) return false;
      double tp = PositionGetDouble(POSITION_TP);
      MarkTradeRequest();
      bool submitted = trade.PositionModify(ticket, target, tp);
      uint code = trade.ResultRetcode();
      if(!submitted || !TradeResultAccepted(code))
      {
         RegisterPendingFailure(code);
         pending_sync_state = StringFormat("%s modify failed for %I64u: %u %s", purpose, ticket, code, trade.ResultRetcodeDescription());
         last_event = pending_sync_state;
         return false;
      }
      pending_sync_state = StringFormat("%s: synchronising %.2f (%d/%d already confirmed)", purpose, target, synced, total);
      last_event = pending_sync_state;
      return false;
   }

   pending_sync_state = StringFormat("%s COMPLETE: all %d existing positions share %.2f before the next stop is armed", purpose, total, target);
   return total > 0 && synced == total;
}

bool PlacePendingOrderExact(ENUM_ORDER_TYPE type, string role, double volume, double entry, double sl, string reason)
{
   if(volume <= 0.0 || entry <= 0.0 || sl <= 0.0 || !TradeRequestAvailable()) return false;

   MqlTick tick;
   if(!SymbolInfoTick(trade_symbol, tick)) return false;
   double distance = PendingEntryDistancePrice();
   double tick_size = SymbolInfoDouble(trade_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0) tick_size = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   entry = RoundPendingPrice(type, entry);
   string side = type == ORDER_TYPE_BUY_STOP ? "BUY" : "SELL";
   sl = RoundProtectiveStop(side, sl);

   if(type == ORDER_TYPE_BUY_STOP)
   {
      if(entry < tick.ask + distance || sl >= entry - tick_size) return false;
   }
   else
   {
      if(entry > tick.bid - distance || sl <= entry + tick_size) return false;
   }

   string comment = "EVE30-LAD";
   if(role == "INITIAL" || role == "ENTRY-BRACKET") comment = "EVE30-INIT";
   else if(role == "CONFIRMATION" || role == "REVERSAL") comment = "EVE30-CONF";

   MarkTradeRequest();
   bool submitted = type == ORDER_TYPE_BUY_STOP
      ? trade.BuyStop(NormalizeVolume(volume), entry, trade_symbol, sl, 0.0, ORDER_TIME_GTC, 0, comment)
      : trade.SellStop(NormalizeVolume(volume), entry, trade_symbol, sl, 0.0, ORDER_TIME_GTC, 0, comment);
   uint code = trade.ResultRetcode();
   if(!submitted || !TradeResultAccepted(code))
   {
      RegisterPendingFailure(code);
      last_event = StringFormat("%s exact pending rejected: %u %s", role, code, trade.ResultRetcodeDescription());
      SendOrderActivity("REJECTED", role, type, 0, volume, entry, reason + " | exact pre-armed SL | " + trade.ResultRetcodeDescription());
      return false;
   }

   pending_invalid_price_streak = 0;
   ulong ticket = trade.ResultOrder();
   if(type == ORDER_TYPE_BUY_STOP) last_bracket_buy_price = entry;
   if(type == ORDER_TYPE_SELL_STOP) last_bracket_sell_price = entry;
   SendOrderActivity("PLACED", role, type, ticket, volume, entry, reason + StringFormat(" | PRE-ARMED SHARED SL %.2f | no TP", sl));
   return true;
}

void MaintainProvisionalCampaign()
{
   string side = campaign_current_side;
   if(side != "BUY" && side != "SELL") return;
   if(DeleteOneForProvisional(side)) return;

   string spread_reason = "";
   if(!EntrySpreadSafe(spread_reason))
   {
      engine_state = "WIDE SPREAD - POSITION 1 SL ONLY";
      pending_sync_state = spread_reason + " - removing pending entries";
      CancelPendingOrders();
      MaintainProvisionalProfitLock();
      return;
   }

   double lot = CalculateLegLot();
   double atr_value = CurrentOrderAtr();
   string opposite = OppositeSide(side);

   // The failed-breakout guard is restored first and remains until Position 2 confirms.
   if(CountPendingBySide(opposite) == 0)
   {
      double desired = ProvisionalGuardPrice(opposite);
      pending_sync_state = "RESTORING OPPOSITE FALSE-BREAKOUT GUARD";
      PlacePendingOrder(StopTypeForSide(opposite), "CONFIRMATION", lot, desired, atr_value, 0.0, "opposite stop remains until second same-side trigger");
      return;
   }

   ulong confirmation_ticket = 0;
   double confirmation_entry = 0.0, confirmation_sl = 0.0;
   if(FindPendingBySideAndRole(side, "CONFIRMATION", confirmation_ticket, confirmation_entry, confirmation_sl))
   {
      double current_protection = MostProtectiveExistingStop(side);
      bool pending_is_weaker = current_protection > 0.0 &&
         (side == "BUY" ? current_protection > confirmation_sl : current_protection < confirmation_sl);
      if(pending_is_weaker && OrderSelect(confirmation_ticket))
      {
         DeleteSelectedPending("Position 1 protection advanced beyond the pending confirmation SL; rebuild exact pre-arm");
         return;
      }

      if(!SynchronizeExistingPositionsToTarget(side, confirmation_sl, "CONFIRMATION PRE-ARM"))
      {
         if(newest_ticket > 0 && PositionHasSharedStop(newest_ticket, confirmation_sl))
            pending_sync_state = StringFormat("CONFIRMATION READY: Position 1 and pending Position 2 share SL %.2f", confirmation_sl);
         return;
      }
      pending_sync_state = StringFormat("PROVISIONAL %s 1/2 - CONFIRMATION %.2f / SHARED SL %.2f / OPPOSITE LIVE", side, confirmation_entry, confirmation_sl);
      last_event = pending_sync_state;
      return;
   }

   // Protect a profitable Position 1 while it waits. No fixed TP is used.
   if(MaintainProvisionalProfitLock()) return;

   double base = last_add_price > 0.0 ? last_add_price : campaign_trigger_price;
   double desired = side == "BUY" ? base + LadderSpacingPrice(side) : base - LadderSpacingPrice(side);
   double planned_entry = 0.0, planned_sl = 0.0, planned_tp = 0.0;
   if(!BuildSafePendingLevels(StopTypeForSide(side), "CONFIRMATION", lot, desired, atr_value, base, planned_entry, planned_sl, planned_tp))
   {
      pending_sync_state = "WAITING TO CALCULATE SAFE CONFIRMATION ENTRY";
      return;
   }

   // Position 2 is not armed until Position 1 already carries the exact same SL.
   if(!SynchronizeExistingPositionsToTarget(side, planned_sl, "CONFIRMATION PRE-ARM")) return;

   pending_sync_state = "PLACING ONE PRE-ARMED CONFIRMATION STOP";
   PlacePendingOrderExact(StopTypeForSide(side), "CONFIRMATION", lot, planned_entry, planned_sl,
      "second same-side trigger confirms momentum; Position 1 already carries the exact same broker-side SL");
}

void MaintainActiveLadder()
{
   string side = campaign_current_side;
   if(side != "BUY" && side != "SELL") return;

   string spread_reason = "";
   if(!EntrySpreadSafe(spread_reason))
   {
      engine_state = "WIDE SPREAD - SHARED SL PROTECTION";
      pending_sync_state = spread_reason + " - removing the future ladder stop";
      CancelPendingOrders();
      return;
   }

   ulong ladder_ticket = 0;
   double ladder_entry = 0.0, ladder_sl = 0.0;
   if(FindPendingBySideAndRole(side, "LADDER", ladder_ticket, ladder_entry, ladder_sl))
   {
      double current_protection = MostProtectiveExistingStop(side);
      bool pending_is_weaker = current_protection > 0.0 &&
         (side == "BUY" ? current_protection > ladder_sl : current_protection < ladder_sl);
      if(pending_is_weaker && OrderSelect(ladder_ticket))
      {
         DeleteSelectedPending("Shared basket protection advanced beyond the future ladder SL; rebuild exact pre-arm");
         return;
      }

      if(!SynchronizeExistingPositionsToTarget(side, ladder_sl, "NEXT LADDER PRE-ARM")) return;
      pending_sync_state = StringFormat("%s LADDER READY - ONE STOP %.2f AHEAD / SHARED SL %.2f", side, ladder_entry, ladder_sl);
      return;
   }

   double base = last_add_price;
   if(base <= 0.0) base = AverageBasketEntry();
   double desired = side == "BUY" ? base + LadderSpacingPrice(side) : base - LadderSpacingPrice(side);
   double planned_entry = 0.0, planned_sl = 0.0, planned_tp = 0.0;
   double lot = CalculateLegLot();
   if(!BuildSafePendingLevels(StopTypeForSide(side), "LADDER", lot, desired, CurrentOrderAtr(), base, planned_entry, planned_sl, planned_tp))
   {
      pending_sync_state = "WAITING TO CALCULATE SAFE NEXT LADDER STOP";
      return;
   }

   // Exactly one next stop exists, and it is not armed until every current position
   // already has the same SL the future position will receive.
   if(!SynchronizeExistingPositionsToTarget(side, planned_sl, "NEXT LADDER PRE-ARM")) return;

   pending_sync_state = "PLACING ONE PRE-ARMED LADDER STOP";
   PlacePendingOrderExact(StopTypeForSide(side), "LADDER", lot, planned_entry, planned_sl,
      "one stop ahead only; all current positions already share this broker-side SL");
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
   scan_dirty = true;
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
   string block = "ANALYTICS ONLY - no live momentum burst; price engine remains independent";

   if(regime == "CHAOTIC")
   {
      state = "CHAOTIC";
      block = "ANALYTICS ONLY - spread/feed conditions are abnormal; price engine remains independent";
   }
   else if(best_score < InpAnalyticsReferenceScore)
   {
      state = "IDLE";
      block = StringFormat("ANALYTICS ONLY - live score %d/11 is below reference %d/11; PRICE ENGINE IS NOT GATED", best_score, InpAnalyticsReferenceScore);
   }
   else if(extension_atr > extension_limit)
   {
      state = "EXHAUSTED";
      block = StringFormat("ANALYTICS ONLY - move is %.2f ATR extended; reference limit %.2f ATR; PRICE ENGINE IS NOT GATED", extension_atr, extension_limit);
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
      if(best_score < threshold) block = StringFormat("ANALYTICS ONLY - %s score %d/11 versus reference %d/11", best, best_score, threshold);
      else if(gap < InpMinimumScoreDifference) block = StringFormat("ANALYTICS ONLY - score gap %d versus reference %d", gap, InpMinimumScoreDifference);
      else if(!best_accelerating) block = "ANALYTICS ONLY - direction is strong but live speed is not accelerating";
      else if(!burst_break) block = "ANALYTICS ONLY - waiting for micro-breakout or stronger live candle expansion";
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

   if(!remote_autonomous || local_paused)
   {
      scan.decision = "WAIT";
      scan.block_reason = local_paused ? "PAUSED - pending entries are removed; open positions retain broker-side SL protection" : "AUTONOMOUS OFF";
      return;
   }
   if(emergency_stopped)
   {
      scan.decision = "WAIT";
      scan.block_reason = "EMERGENCY STOP ACTIVE";
      return;
   }
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      scan.decision = "WAIT";
      scan.block_reason = "WAITING FOR MT5 CONNECTION OR ALGO TRADING PERMISSION";
      return;
   }
   if(close_pending)
   {
      scan.decision = "WAIT";
      scan.block_reason = "NEWEST-LEG EXIT IS BANKING THE FULL BASKET";
      return;
   }
   if(CountOurPositions() > 0)
   {
      scan.block_reason = campaign_phase == CAMPAIGN_OCO_CANCELLING
         ? "POSITION 1 PROVISIONAL - PROFIT LOCK / PRE-ARMED POSITION 2"
         : "CONFIRMED CAMPAIGN - ONE PRE-ARMED LADDER STOP AHEAD";
      return;
   }

   datetime current_bar = iTime(trade_symbol, InpExecutionTimeframe, 0);
   if(InpOneCampaignAttemptPerCandle && last_campaign_finished_candle > 0 && current_bar > 0 && current_bar <= last_campaign_finished_candle)
   {
      scan.block_reason = "ONE CAMPAIGN ATTEMPT USED - WAITING FOR NEXT M1 CANDLE";
      return;
   }

   string spread_reason = "";
   if(!EntrySpreadSafe(spread_reason))
   {
      scan.block_reason = spread_reason + " - PENDING ENTRIES DISARMED";
      return;
   }

   scan.block_reason = "24/5 PRICE ENGINE - ONE BUY STOP AND ONE SELL STOP FOR THIS M1 CANDLE";
}


bool OpenMarketLeg(ENUM_POSITION_TYPE direction, double volume, double atr_value)
{
   // v2.10 never adds with market orders. This helper remains only for backward compatibility.
   return false;
}


bool IsLegacyEveComment(string comment)
{
   return StringFind(comment, "EVE29-") >= 0 || StringFind(comment, "EVE-MOMENTUM-V2.09") >= 0 ||
      StringFind(comment, "EVE28-") >= 0 || StringFind(comment, "EVE-MOMENTUM-V2.08") >= 0 ||
      StringFind(comment, "EVE26-") >= 0 || StringFind(comment, "EVE-MOMENTUM-V2.06") >= 0 || StringFind(comment, "EVE-MOMENTUM-V2.07") >= 0 ||
      StringFind(comment, "EVE-MB2-") >= 0 || StringFind(comment, "EVE25-") >= 0 || StringFind(comment, "EVE-MOMENTUM-V2.04") >= 0 || StringFind(comment, "EVE-MOMENTUM-V2.05") >= 0;
}

int CountLegacyEvePendingOrders()
{
   if(!InpDeleteLegacyPendingOrders || InpLegacyMagicNumber == InpMagicNumber) return 0;
   int count = 0;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL) != trade_symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpLegacyMagicNumber) continue;
      if(!IsLegacyEveComment(OrderGetString(ORDER_COMMENT))) continue;
      count++;
   }
   return count;
}

int CountLegacyEvePositions()
{
   if(InpLegacyMagicNumber == InpMagicNumber) return 0;
   int count = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != trade_symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpLegacyMagicNumber) continue;
      string comment = PositionGetString(POSITION_COMMENT);
      if(comment != "" && !IsLegacyEveComment(comment)) continue;
      count++;
   }
   return count;
}

bool HandleLegacyPendingCleanup()
{
   int legacy_orders = CountLegacyEvePendingOrders();
   if(legacy_orders <= 0) return false;

   engine_state = "ONE-TIME LEGACY CLEANUP";
   pending_sync_state = StringFormat("REMOVING %d OLD EVE PENDING ORDER(S)", legacy_orders);
   last_event = "v2.10 is deleting v2.09 pending orders before starting its own bracket";

   if(!TradeRequestAvailable()) return true;

   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL) != trade_symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpLegacyMagicNumber) continue;
      string comment = OrderGetString(ORDER_COMMENT);
      if(!IsLegacyEveComment(comment)) continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      double volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
      double price = OrderGetDouble(ORDER_PRICE_OPEN);
      if(PendingOrderInsideFreeze(type, price))
      {
         pending_sync_state = "WAITING BROKER FREEZE TO REMOVE OLD ORDER";
         return true;
      }

      MarkTradeRequest();
      bool submitted = trade.OrderDelete(ticket);
      uint code = trade.ResultRetcode();
      if(!submitted || !DeleteResultAccepted(code))
      {
         RegisterPendingFailure(code);
         SendOrderActivity("LEGACY-DELETE-FAILED", "LEGACY", type, ticket, volume, price, trade.ResultRetcodeDescription());
         return true;
      }

      delete_wait_ticket = ticket;
      delete_wait_started_ms = GetTickCount64();
      SendOrderActivity("LEGACY-CANCEL-REQUESTED", "LEGACY", type, ticket, volume, price, "v2.10 version isolation cleanup");
      return true;
   }
   return true;
}


void ManageBasket()
{
   ResetDailyIfNeeded();

   if(HandleLegacyPendingCleanup()) return;

   if(InpBlockOnLegacyOpenPosition && CountLegacyEvePositions() > 0)
   {
      engine_state = "OLD EVE POSITION DETECTED";
      pending_sync_state = "CLOSE OLD V2.09 POSITION BEFORE V2.10";
      last_event = "v2.10 is isolated and will not overlap an open v2.09 position";
      CancelPendingOrders();
      return;
   }

   if(execution_integrity_breach && !close_pending)
   {
      string reason = execution_integrity_reason == "" ? "EXECUTION INTEGRITY BREACH" : execution_integrity_reason;
      execution_integrity_breach = false;
      BankBasket(reason, BasketProfit());
      return;
   }

   if(close_pending)
   {
      campaign_phase = CAMPAIGN_CLOSING;
      engine_state = "BANKING FULL BASKET";
      ContinuePendingClose();
      return;
   }

   if(newest_leg_sl_exit_detected)
   {
      string reason = newest_leg_sl_exit_reason == "" ? "SHARED BASKET STOP LOSS HIT - BANK ALL" : newest_leg_sl_exit_reason;
      newest_leg_sl_exit_detected = false;
      BankBasket(reason, BasketProfit());
      return;
   }

   int positions = CountOurPositions();

   if(positions == 0)
   {
      bank_candidate = false;
      bank_candidate_reason = "";
      newest_ticket = 0;
      newest_position_id = 0;
      newest_leg_peak_profit = 0.0;
      newest_leg_current_profit = 0.0;
      newest_leg_open_time = 0;
      shared_basket_stop = 0.0;
      shared_stop_state = "NOT ACTIVE";
      shared_stop_synced_positions = 0;

      if(basket_started_at > 0)
      {
         if(CountOurPendingOrders() > 0)
         {
            campaign_phase = CAMPAIGN_CLOSING;
            pending_sync_state = "CLEARING FINISHED CAMPAIGN ORDERS";
            CancelPendingOrders();
            return;
         }
         FinaliseBasketClose("Campaign became flat");
         return;
      }

      campaign_phase = CAMPAIGN_BUILDING_STRADDLE;
      engine_state = "EVERY-CANDLE STRADDLE";
      MaintainMovingStraddle();
      return;
   }

   campaign_flat_seen_at = 0;

   if(basket_started_at == 0)
   {
      basket_started_at = EarliestBasketPositionTime();
      if(basket_started_at <= 0) basket_started_at = TimeCurrent();
      basket_id = ((long)basket_started_at * 1000) + (long)(InpMagicNumber % 1000);
      basket_side = BasketSideText();
      campaign_start_side = basket_side;
      campaign_current_side = basket_side;
      campaign_triggered_at = basket_started_at;
      campaign_phase = CountOurPositionsBySide(basket_side) >= 2 ? CAMPAIGN_ACTIVE : CAMPAIGN_OCO_CANCELLING;
   }

   UpdateNewestCanary();
   positions = CountOurPositions();
   double profit = BasketProfit();
   peak_basket_profit = MathMax(peak_basket_profit, profit);
   basket_mae = MathMin(basket_mae, profit);
   basket_max_concurrent_positions = MathMax(basket_max_concurrent_positions, positions);
   bank_candidate = true;
   bank_candidate_reason = positions >= 2 ? "Every position will share one broker-side basket SL" : "First provisional position is protected by its own broker-side SL";

   if(emergency_stopped)
   {
      BankBasket("EMERGENCY STOP", profit);
      return;
   }

   if(!remote_autonomous || local_paused)
   {
      engine_state = "PAUSED - SL PROTECTION";
      pending_sync_state = "REMOVING PENDING ENTRIES";
      CancelPendingOrders();
      SavePersistentState();
      return;
   }

   // During a provisional false-breakout flip, keep the newly triggered side and close the failed side.
   if(ResolveMixedDirectionIfNeeded()) return;

   campaign_current_side = BasketSideText();
   if(campaign_current_side != "BUY" && campaign_current_side != "SELL")
      campaign_current_side = basket_side;
   basket_side = campaign_current_side;

   if(campaign_phase == CAMPAIGN_OCO_CANCELLING)
   {
      if(CountOurPositionsBySide(campaign_current_side) >= 2)
      {
         campaign_phase = CAMPAIGN_ACTIVE;
         pending_sync_state = "SECOND TRIGGER CONFIRMED";
         last_event = "Second " + campaign_current_side + " position confirmed the direction; cancelling the opposite stop and building the ladder";
         SendEvent("confirmed", last_event);
      }
      else
      {
         engine_state = "PROVISIONAL 1/2";
         MaintainProvisionalCampaign();
         SavePersistentState();
         return;
      }
   }

   campaign_phase = CAMPAIGN_ACTIVE;
   engine_state = "SHARED BASKET SL";

   // The opposite stop is removed immediately after the second same-side trigger.
   // No further ladder order is added until every open position has the same broker-side SL.
   if(DeleteOneForActiveLadder(campaign_current_side))
   {
      SavePersistentState();
      return;
   }
   if(!SynchronizeSharedBasketStop())
   {
      SavePersistentState();
      return;
   }

   engine_state = "CONTINUOUS LADDER - SHARED SL ARMED";
   MaintainActiveLadder();
   SavePersistentState();
}


void MaintainMovingStraddle()
{
   if(!InpUseMovingStraddle || !remote_autonomous || local_paused || emergency_stopped || close_pending)
   {
      pending_sync_state = "CLEARING";
      CancelPendingOrders();
      return;
   }
   if(!BasicTradingAvailable()) return;

   datetime current_bar = iTime(trade_symbol, InpExecutionTimeframe, 0);
   if(current_bar <= 0) return;

   if(InpOneCampaignAttemptPerCandle && last_campaign_finished_candle > 0 && current_bar <= last_campaign_finished_candle)
   {
      campaign_phase = CAMPAIGN_WAIT_NEXT_CANDLE;
      engine_state = "WAITING FOR NEXT M1 CANDLE";
      pending_sync_state = "ONE CAMPAIGN ATTEMPT USED - NO SAME-CANDLE RESTART";
      last_event = pending_sync_state;
      CancelPendingOrders();
      return;
   }

   string spread_reason = "";
   if(!EntrySpreadSafe(spread_reason))
   {
      campaign_phase = CAMPAIGN_BUILDING_STRADDLE;
      engine_state = "WIDE SPREAD - ENTRIES DISARMED";
      pending_sync_state = spread_reason + " - waiting with no pending entries";
      last_event = pending_sync_state;
      CancelPendingOrders();
      return;
   }

   // v2.10 keeps the two-sided bracket intact while a candle is eligible.
   // The old bracket stays live while BUY and SELL are refreshed one at a time.
   if(straddle_candle_time == 0 || current_bar != straddle_candle_time)
   {
      if(!CaptureCurrentCandleAnchor()) return;
      pending_sync_state = "NEW CANDLE - SAFE TWO-SIDED REFRESH";
   }

   if(DeleteOneForFlatStraddle()) return;

   double distance = StraddleDistancePrice();
   double desired_buy = RoundPendingPrice(ORDER_TYPE_BUY_STOP, straddle_anchor_high + distance);
   double desired_sell = RoundPendingPrice(ORDER_TYPE_SELL_STOP, straddle_anchor_low - distance);
   double lot = CalculateLegLot();
   double atr_value = CurrentOrderAtr();
   ulong ticket = 0;
   double price = 0.0, sl = 0.0, tp = 0.0;
   datetime setup = 0;

   campaign_phase = CAMPAIGN_BUILDING_STRADDLE;

   if(!FindOurPendingOrder(ORDER_TYPE_BUY_STOP, ticket, price, sl, tp, setup))
   {
      pending_sync_state = "PLACING CANDLE BUY STOP";
      if(PlacePendingOrder(ORDER_TYPE_BUY_STOP, "INITIAL", lot, desired_buy, atr_value, 0.0, "safe every-candle BUY STOP"))
         straddle_buy_synced_candle = current_bar;
      return;
   }
   if(straddle_buy_synced_candle != current_bar)
   {
      pending_sync_state = "REFRESHING BUY - SELL REMAINS LIVE";
      if(ModifyPendingOrder(ticket, ORDER_TYPE_BUY_STOP, "INITIAL", desired_buy, atr_value, "new-candle BUY refresh"))
         straddle_buy_synced_candle = current_bar;
      return;
   }

   if(!FindOurPendingOrder(ORDER_TYPE_SELL_STOP, ticket, price, sl, tp, setup))
   {
      pending_sync_state = "PLACING CANDLE SELL STOP";
      if(PlacePendingOrder(ORDER_TYPE_SELL_STOP, "INITIAL", lot, desired_sell, atr_value, 0.0, "safe every-candle SELL STOP"))
         straddle_sell_synced_candle = current_bar;
      return;
   }
   if(straddle_sell_synced_candle != current_bar)
   {
      pending_sync_state = "REFRESHING SELL - BUY REMAINS LIVE";
      if(ModifyPendingOrder(ticket, ORDER_TYPE_SELL_STOP, "INITIAL", desired_sell, atr_value, "new-candle SELL refresh"))
         straddle_sell_synced_candle = current_bar;
      return;
   }

   last_bracket_buy_price = PendingOrderPrice(ORDER_TYPE_BUY_STOP);
   last_bracket_sell_price = PendingOrderPrice(ORDER_TYPE_SELL_STOP);
   last_bracket_refresh_at = TimeCurrent();
   campaign_phase = CAMPAIGN_STRADDLE_READY;
   pending_sync_state = "CANDLE STRADDLE READY";
   last_event = StringFormat("Candle straddle ready: BUY STOP %.2f / SELL STOP %.2f; first trigger is provisional", last_bracket_buy_price, last_bracket_sell_price);
}


void MaintainReverseStop()
{
   // Legacy v2.04 hook intentionally disabled. v2.10 uses only the two-trigger
   // provisional flip and the confirmed same-direction stop ladder.
}


bool PlacePendingOrder(ENUM_ORDER_TYPE type, string role, double volume, double price, double atr_value, double protect_anchor_price, string reason)
{
   if(volume <= 0 || price <= 0 || atr_value <= 0 || !TradeRequestAvailable()) return false;

   double safe_price = 0.0, sl = 0.0, tp = 0.0;
   if(!BuildSafePendingLevels(type, role, volume, price, atr_value, protect_anchor_price, safe_price, sl, tp)) return false;

   string comment = "EVE30-LAD";
   if(role == "INITIAL" || role == "ENTRY-BRACKET") comment = "EVE30-INIT";
   else if(role == "CONFIRMATION" || role == "REVERSAL") comment = "EVE30-CONF";

   MarkTradeRequest();
   bool submitted = type == ORDER_TYPE_BUY_STOP
      ? trade.BuyStop(NormalizeVolume(volume), safe_price, trade_symbol, sl, 0.0, ORDER_TIME_GTC, 0, comment)
      : trade.SellStop(NormalizeVolume(volume), safe_price, trade_symbol, sl, 0.0, ORDER_TIME_GTC, 0, comment);
   uint code = trade.ResultRetcode();
   if(!submitted || !TradeResultAccepted(code))
   {
      RegisterPendingFailure(code);
      last_event = StringFormat("%s pending order rejected: %u %s; safe price %.2f", role, code, trade.ResultRetcodeDescription(), safe_price);
      SendOrderActivity("REJECTED", role, type, 0, volume, safe_price, reason + " | " + trade.ResultRetcodeDescription());
      return false;
   }

   pending_invalid_price_streak = 0;
   ulong ticket = trade.ResultOrder();
   if(type == ORDER_TYPE_BUY_STOP) last_bracket_buy_price = safe_price;
   if(type == ORDER_TYPE_SELL_STOP) last_bracket_sell_price = safe_price;
   SendOrderActivity("PLACED", role, type, ticket, volume, safe_price, reason + StringFormat(" | SL %.2f | no TP", sl));
   return true;
}


void TryAddRollingLeg()
{
   // Legacy v2.04 market-order adding intentionally disabled.
   // All v2.10 additions come from one broker-side pending stop order ahead.
}


bool ResolveMixedDirectionIfNeeded()
{
   int buys = CountOurPositionsBySide("BUY");
   int sells = CountOurPositionsBySide("SELL");
   if(buys == 0 || sells == 0) return false;

   string keep_side = campaign_current_side;
   if(keep_side != "BUY" && keep_side != "SELL") keep_side = basket_side;
   if(keep_side != "BUY" && keep_side != "SELL") keep_side = campaign_start_side;

   engine_state = campaign_phase == CAMPAIGN_OCO_CANCELLING ? "FALSE BREAKOUT FLIP" : "LATE OPPOSITE CLEANUP";
   pending_sync_state = "CLOSING NON-CAMPAIGN DIRECTION";

   if(!TradeRequestAvailable()) return true;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string side = type == POSITION_TYPE_BUY ? "BUY" : "SELL";
      if(side == keep_side) continue;

      MarkTradeRequest();
      bool submitted = trade.PositionClose(ticket, InpSlippagePoints);
      uint code = trade.ResultRetcode();
      if(!submitted || !CloseResultAccepted(code))
      {
         RegisterPendingFailure(code);
         last_event = StringFormat("Direction cleanup failed for %I64u: %u %s", ticket, code, trade.ResultRetcodeDescription());
      }
      else
      {
         last_event = StringFormat("%s retained; failed/accidental %s leg %I64u is closing", keep_side, side, ticket);
         SendEvent("direction-cleanup", last_event);
      }
      return true;
   }

   return true;
}


void UpdateNewestCanary()
{
   ulong ticket = 0;
   ulong identifier = 0;
   datetime latest = 0;
   long latest_msc = 0;
   double profit = 0.0;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !PositionSelectByTicket(t) || !IsOurSelectedPosition()) continue;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string side = type == POSITION_TYPE_BUY ? "BUY" : "SELL";
      if(campaign_current_side != "NONE" && side != campaign_current_side) continue;

      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      long opened_msc = PositionGetInteger(POSITION_TIME_MSC);
      if(opened > latest || (opened == latest && opened_msc >= latest_msc))
      {
         latest = opened;
         latest_msc = opened_msc;
         ticket = t;
         identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
         profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      }
   }

   if(ticket != newest_ticket)
   {
      newest_ticket = ticket;
      newest_position_id = identifier;
      newest_leg_peak_profit = profit;
      newest_leg_open_time = latest;
   }
   else if(identifier > 0)
   {
      newest_position_id = identifier;
   }

   newest_leg_current_profit = profit;
   newest_leg_peak_profit = MathMax(newest_leg_peak_profit, profit);
}


void BankBasket(string reason, double profit)
{
   int same_score = 0, opposite_score = 0;
   string side = BasketSideText();
   if(have_scan)
   {
      same_score = side == "BUY" ? last_scan.buy_score : last_scan.sell_score;
      opposite_score = side == "BUY" ? last_scan.sell_score : last_scan.buy_score;
   }
   SendBankDecision(reason, profit, same_score, opposite_score);
   RequestBasketClose(reason, profit);
}

void TrailAllPositions()
{
   // Legacy trailing logic intentionally disabled. Each position keeps the SL
   // submitted with its pending order; after confirmation all open positions are synchronised to one shared basket SL.
}


void SendLegRecord(string action, string side, ulong deal_ticket, ulong position_id, double volume, double price, double net, string reason)
{
   string json = StringFormat("{\"id\":\"%I64u-%s\",\"basketId\":\"%I64d\",\"account\":\"%I64d\",\"symbol\":\"%s\",\"magic\":\"%I64u\",\"action\":\"%s\",\"side\":\"%s\",\"ticket\":\"%I64u\",\"positionId\":\"%I64u\",\"volume\":%.2f,\"price\":%.5f,\"netProfit\":%.2f,\"reason\":\"%s\",\"dealTime\":%I64d}", deal_ticket, JsonEscape(action), basket_id, AccountInfoInteger(ACCOUNT_LOGIN), JsonEscape(trade_symbol), InpMagicNumber, JsonEscape(action), JsonEscape(side), deal_ticket, position_id, volume, price, net, JsonEscape(reason), (long)TimeCurrent() * 1000);
   QueueJson("/api/ea/leg", json);
}

void SendOrderActivity(string action, string role, ENUM_ORDER_TYPE type, ulong ticket, double volume, double price, string reason)
{
   string order_type = type == ORDER_TYPE_BUY_STOP ? "BUY_STOP" : type == ORDER_TYPE_SELL_STOP ? "SELL_STOP" : "OTHER";
   string json = StringFormat("{\"id\":\"%I64d-%I64u-%s\",\"basketId\":\"%I64d\",\"account\":\"%I64d\",\"symbol\":\"%s\",\"action\":\"%s\",\"role\":\"%s\",\"orderType\":\"%s\",\"ticket\":\"%I64u\",\"volume\":%.2f,\"price\":%.5f,\"reason\":\"%s\",\"at\":%I64d}", (long)TimeCurrent(), ticket, JsonEscape(action), basket_id, AccountInfoInteger(ACCOUNT_LOGIN), JsonEscape(trade_symbol), JsonEscape(action), JsonEscape(role), order_type, ticket, volume, price, JsonEscape(reason), (long)TimeCurrent() * 1000);
   QueueJson("/api/ea/order", json);
}

void SendBankDecision(string reason, double profit, int same_score, int opposite_score)
{
   string json = StringFormat("{\"id\":\"%I64d-%I64d\",\"basketId\":\"%I64d\",\"account\":\"%I64d\",\"symbol\":\"%s\",\"side\":\"%s\",\"basketProfit\":%.2f,\"peakBasketProfit\":%.2f,\"newestTicket\":\"%I64u\",\"newestProfit\":%.2f,\"newestPeak\":%.2f,\"sameScore\":%d,\"oppositeScore\":%d,\"momentumState\":\"%s\",\"reason\":\"%s\",\"at\":%I64d}", (long)TimeCurrent(), basket_id, basket_id, AccountInfoInteger(ACCOUNT_LOGIN), JsonEscape(trade_symbol), JsonEscape(BasketSideText()), profit, peak_basket_profit, newest_ticket, newest_leg_current_profit, newest_leg_peak_profit, same_score, opposite_score, have_scan ? JsonEscape(last_scan.momentum_state) : "UNKNOWN", JsonEscape(reason), (long)TimeCurrent() * 1000);
   QueueJson("/api/ea/bank", json);
}

string DealReasonText(ENUM_DEAL_REASON reason)
{
   if(reason == DEAL_REASON_SL) return "BROKER STOP LOSS";
   if(reason == DEAL_REASON_TP) return "BROKER TAKE PROFIT";
   if(reason == DEAL_REASON_EXPERT) return "EXPERT ADVISOR";
   if(reason == DEAL_REASON_CLIENT) return "MANUAL DESKTOP";
   if(reason == DEAL_REASON_MOBILE) return "MANUAL MOBILE";
   return EnumToString(reason);
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
      campaign_phase = CAMPAIGN_CLOSING;
      close_reason = reason;
      close_trigger_profit = trigger_profit;
      close_peak_profit = peak_basket_profit;
      close_requested_at = TimeCurrent();
      last_close_attempt_at = 0;
      close_attempts = 0;
      close_pending_cancel_attempted = false;
      last_close_retcode = 0;
      last_close_result = "Close requested; awaiting broker confirmation";
      pending_sync_state = "CLOSE PENDING";
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

   // v2.10 quarantines the campaign first: pending entries are cancelled before
   // any open position is closed, preventing another ladder leg from joining the exit.
   if(CountOurPendingOrders() > 0)
   {
      pending_sync_state = "CANCELLING ALL PENDING BEFORE BANKING";
      CancelPendingOrders();
      last_event = StringFormat("BANKING PENDING - clearing %d pending order(s) before positions", CountOurPendingOrders());
      SavePersistentState();

      // The first pass always quarantines pending orders. If a broker freeze prevents
      // cancellation, later passes also close positions while close_pending remains
      // active; any frozen order that subsequently fills is immediately absorbed.
      if(!close_pending_cancel_attempted)
      {
         close_pending_cancel_attempted = true;
         return;
      }
   }

   if(CountOurPositions() > 0)
   {
      if(!TradeRequestAvailable()) return;
      datetime now = TimeCurrent();

      for(int i=PositionsTotal()-1; i>=0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
         close_attempts++;
         last_close_attempt_at = now;
         MarkTradeRequest();
         ResetLastError();
         bool submitted = trade.PositionClose(ticket, InpSlippagePoints);
         uint code = trade.ResultRetcode();
         string description = trade.ResultRetcodeDescription();
         last_close_retcode = code;
         last_close_result = description;
         if(!submitted || !CloseResultAccepted(code))
         {
            RegisterPendingFailure(code);
            if(code == TRADE_RETCODE_MARKET_CLOSED)
               last_event = StringFormat("BANKING PENDING - MARKET CLOSED; automatic retry; %d position(s) remain", CountOurPositions());
            else
               last_event = StringFormat("BANKING PENDING - attempt %d failed for %I64u: %u %s", close_attempts, ticket, code, description);
         }
         else
            last_event = StringFormat("BANKING PENDING - close accepted for %I64u; %d position(s) remain", ticket, CountOurPositions());
         SavePersistentState();
         return;
      }
   }
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
   double lot_per_leg = entry_legs > 0 ? total_volume / entry_legs : runtime_fixed_lot;
   double giveback = MathMax(0.0, (close_peak_profit > 0 ? close_peak_profit : peak_basket_profit) - realised);
   string start_side = campaign_start_side == "NONE" ? basket_side : campaign_start_side;
   string final_side = campaign_current_side == "NONE" ? basket_side : campaign_current_side;

   string json = StringFormat(
      "{\"id\":\"%I64d-%I64u\",\"account\":\"%I64d\",\"symbol\":\"%s\",\"magic\":\"%I64u\",\"side\":\"%s\",\"startSide\":\"%s\",\"finalSide\":\"%s\",\"buyLegs\":%d,\"sellLegs\":%d,\"reversalCount\":%d,\"volume\":%.2f,\"lotPerLeg\":%.2f,\"maxTotalLotsUsed\":%.2f,\"positionsOpened\":%d,\"maxConcurrentPositions\":%d,\"entryTime\":%I64d,\"exitTime\":%I64d,\"entryPrice\":%.5f,\"exitPrice\":%.5f,\"entryScore\":%d,\"oppositeScore\":%d,\"entryRegime\":\"%s\",\"entryState\":\"%s\",\"entryReason\":\"%s\",\"exitReason\":\"%s\",\"netProfit\":%.2f,\"peakBasketProfit\":%.2f,\"profitGiveback\":%.2f,\"mfe\":%.2f,\"mae\":%.2f,\"durationSeconds\":%d,\"closeAttempts\":%d,\"closeTriggerProfit\":%.2f,\"newestTicket\":\"%I64u\",\"newestProfitAtBank\":%.2f,\"newestPeak\":%.2f,\"reversalTriggered\":%s,\"status\":\"CLOSED\"}",
      basket_id, InpMagicNumber, AccountInfoInteger(ACCOUNT_LOGIN), JsonEscape(trade_symbol), InpMagicNumber,
      JsonEscape(start_side), JsonEscape(start_side), JsonEscape(final_side), campaign_buy_legs, campaign_sell_legs, campaign_reversal_count,
      total_volume, lot_per_leg, total_volume, entry_legs, basket_max_concurrent_positions,
      (long)basket_started_at * 1000, (long)exit_time * 1000, avg_entry, avg_exit,
      basket_entry_score, basket_opposite_score, JsonEscape(basket_entry_regime), JsonEscape(basket_entry_state),
      JsonEscape(basket_entry_reason), JsonEscape(reason), realised, peak_basket_profit, giveback, peak_basket_profit, basket_mae, duration,
      close_attempts, close_trigger_profit, newest_ticket, newest_leg_current_profit, newest_leg_peak_profit, reversal_triggered ? "true" : "false");
   QueueJson("/api/ea/basket", json);

   daily_pnl += realised;
   if(realised < 0) consecutive_losses++;
   else if(realised > 0) consecutive_losses = 0;

   last_basket_closed_at = exit_time;
   campaign_cooldown_until = 0;
   last_campaign_finished_candle = iTime(trade_symbol, InpExecutionTimeframe, 0);
   post_campaign_anchor_price = avg_exit;
   last_event = StringFormat("Campaign confirmed flat: %s to %s, net $%.2f; %d legs (%d BUY/%d SELL); %d reversal(s); reason %s",
      start_side, final_side, realised, entry_legs, campaign_buy_legs, campaign_sell_legs, campaign_reversal_count, reason);
   SendEvent("basket", last_event);

   ResetBasketState();
   campaign_phase = CAMPAIGN_FLAT;
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
   last_add_price = 0.0;
   last_add_at = 0;
   newest_ticket = 0;
   newest_leg_peak_profit = 0.0;
   newest_leg_current_profit = 0.0;
   newest_leg_open_time = 0;
   bank_candidate = false;
   bank_candidate_reason = "";
   reversal_triggered = false;
   campaign_start_side = "NONE";
   campaign_current_side = "NONE";
   campaign_reversal_target = "NONE";
   campaign_triggered_at = 0;
   campaign_trigger_price = 0.0;
   campaign_invalidation_price = 0.0;
   campaign_buy_legs = 0;
   campaign_sell_legs = 0;
   campaign_reversal_count = 0;
   campaign_first_position_id = 0;
   campaign_flat_seen_at = 0;
   newest_position_id = 0;
   newest_leg_sl_exit_detected = false;
   newest_leg_sl_exit_reason = "";
   campaign_attempt_candle = 0;
   provisional_profit_lock_stop = 0.0;
   provisional_profit_locked_money = 0.0;
   provisional_profit_lock_state = "NOT ACTIVE";
   shared_basket_stop = 0.0;
   shared_stop_state = "NOT ACTIVE";
   shared_stop_synced_positions = 0;
   execution_integrity_breach = false;
   execution_integrity_reason = "";
   execution_integrity_position_id = 0;
   ResetStraddleAnchor();
   campaign_phase = CAMPAIGN_FLAT;
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
   close_pending_cancel_attempted = false;
   last_close_retcode = 0;
   last_close_result = "No close pending";
}

bool CancelPendingOrders()
{
   if(delete_wait_ticket > 0)
   {
      if(!OrderSelect(delete_wait_ticket))
      {
         delete_wait_ticket = 0;
         delete_wait_started_ms = 0;
      }
      else if(GetTickCount64() - delete_wait_started_ms < (ulong)MathMax(1, InpOrderDeleteTimeoutSeconds) * 1000)
         return false;
      else
      {
         // The server did not confirm within the timeout. Release the lock and allow a controlled retry.
         delete_wait_ticket = 0;
         delete_wait_started_ms = 0;
      }
   }
   if(!TradeRequestAvailable()) return CountOurPendingOrders() == 0;

   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket) || !IsOurSelectedOrder()) continue;
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      double volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
      double price = OrderGetDouble(ORDER_PRICE_OPEN);
      string role = SelectedPendingRole();

      if(PendingOrderInsideFreeze(type, price))
      {
         pending_sync_state = "WAITING FREEZE";
         last_event = StringFormat("Pending order %I64u is inside the broker freeze zone; waiting for trigger or safe cancellation", ticket);
         return false;
      }

      MarkTradeRequest();
      ResetLastError();
      bool submitted = trade.OrderDelete(ticket);
      uint code = trade.ResultRetcode();
      if(!submitted || !DeleteResultAccepted(code))
      {
         // A pending stop can change into a position between selection and deletion.
         // Refresh state instead of hammering the same stale ticket with invalid requests.
         if(!OrderSelect(ticket) || code == TRADE_RETCODE_INVALID || code == 10035)
         {
            delete_wait_ticket = 0;
            delete_wait_started_ms = 0;
            pending_retry_after_ms = GetTickCount64() + 300;
            pending_sync_state = "ORDER CHANGED STATE - REFRESHING";
            last_event = StringFormat("Pending ticket %I64u changed state while cancellation was requested; refreshing live orders", ticket);
            return false;
         }
         RegisterPendingFailure(code);
         last_close_retcode = code;
         last_close_result = trade.ResultRetcodeDescription();
         SendOrderActivity("DELETE-FAILED", role, type, ticket, volume, price, trade.ResultRetcodeDescription());
         return false;
      }

      delete_wait_ticket = ticket;
      delete_wait_started_ms = GetTickCount64();
      pending_sync_state = "DELETE REQUESTED";
      SendOrderActivity("CANCEL-REQUESTED", role, type, ticket, volume, price, "waiting for terminal confirmation before another request");
      return false;
   }
   return true;
}

bool TradeRequestAvailable()
{
   ulong now_ms = GetTickCount64();

   if(delete_wait_ticket > 0)
   {
      if(!OrderSelect(delete_wait_ticket))
      {
         delete_wait_ticket = 0;
         delete_wait_started_ms = 0;
      }
      else if(now_ms - delete_wait_started_ms < (ulong)MathMax(1, InpOrderDeleteTimeoutSeconds) * 1000)
         return false;
      else
      {
         delete_wait_ticket = 0;
         delete_wait_started_ms = 0;
      }
   }

   if(pending_retry_after_ms > 0 && now_ms < pending_retry_after_ms) return false;
   if(InpTradeRequestCooldownMs > 0 && last_trade_request_ms > 0 && now_ms - last_trade_request_ms < (ulong)InpTradeRequestCooldownMs) return false;
   return true;
}


void MarkTradeRequest()
{
   last_trade_request_ms = GetTickCount64();
}

void RegisterPendingFailure(uint code)
{
   if(code == TRADE_RETCODE_INVALID_PRICE || code == TRADE_RETCODE_INVALID_STOPS || code == TRADE_RETCODE_PRICE_CHANGED ||
      code == TRADE_RETCODE_PRICE_OFF || code == TRADE_RETCODE_TOO_MANY_REQUESTS || code == TRADE_RETCODE_LOCKED ||
      code == TRADE_RETCODE_FROZEN || code == TRADE_RETCODE_TIMEOUT || code == TRADE_RETCODE_CONNECTION ||
      code == TRADE_RETCODE_INVALID || code == 10035)
   {
      pending_invalid_price_streak = (int)MathMin(20, pending_invalid_price_streak + 1);
   }

   // Broker/terminal communication backoff only. This does not delay a valid strategy
   // entry; it prevents the same rejected request being hammered on every tick.
   pending_retry_after_ms = GetTickCount64() + (ulong)MathMax(1, InpPendingInvalidPriceBackoffSeconds) * 1000;
   pending_sync_state = "BROKER BACKOFF";
}


double BrokerStopsDistancePrice()
{
   double point = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   long stops = SymbolInfoInteger(trade_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   return MathMax(0.0, (double)stops * point);
}

double BrokerFreezeDistancePrice()
{
   double point = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   long freeze = SymbolInfoInteger(trade_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return MathMax(0.0, (double)freeze * point);
}

double PendingAdaptiveBufferPrice()
{
   double point = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   int adaptive_points = InpPendingSafetyBufferPoints + pending_invalid_price_streak * 6;
   adaptive_points = MathMin(MathMax(2, adaptive_points), MathMax(InpPendingSafetyBufferPoints, InpPendingMaximumAdaptiveBufferPoints));
   double tick_size = SymbolInfoDouble(trade_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0) tick_size = point;
   return adaptive_points * point + 2.0 * tick_size;
}

double PendingEntryDistancePrice()
{
   return MathMax(BrokerStopsDistancePrice(), BrokerFreezeDistancePrice()) + PendingAdaptiveBufferPrice();
}

double RoundPendingPrice(ENUM_ORDER_TYPE type, double price)
{
   double tick_size = SymbolInfoDouble(trade_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0) tick_size = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(trade_symbol, SYMBOL_DIGITS);
   if(tick_size <= 0) return NormalizeDouble(price, digits);
   double steps = price / tick_size;
   double rounded = type == ORDER_TYPE_BUY_STOP ? MathCeil(steps - 0.0000000001) * tick_size : MathFloor(steps + 0.0000000001) * tick_size;
   return NormalizeDouble(rounded, digits);
}

bool BuildSafePendingLevels(ENUM_ORDER_TYPE type, string role, double pending_volume, double requested_price, double atr_value, double protect_anchor_price, double &entry, double &sl, double &tp)
{
   MqlTick tick;
   if(!SymbolInfoTick(trade_symbol, tick)) return false;

   double point = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   double tick_size = SymbolInfoDouble(trade_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0) tick_size = point;
   double distance = PendingEntryDistancePrice();
   double stops_distance = BrokerStopsDistancePrice() + PendingAdaptiveBufferPrice();
   bool profit_lock_role = (role == "CONFIRMATION" || role == "LADDER") && protect_anchor_price > 0.0;
   string side = type == ORDER_TYPE_BUY_STOP ? "BUY" : "SELL";

   if(type == ORDER_TYPE_BUY_STOP)
      entry = RoundPendingPrice(type, MathMax(requested_price, tick.ask + distance));
   else
      entry = RoundPendingPrice(type, MathMin(requested_price, tick.bid - distance));

   if(!profit_lock_role)
   {
      double sl_distance = MathMax(atr_value * InpStopLossATR, stops_distance);
      sl = type == ORDER_TYPE_BUY_STOP
         ? NormalizePrice(entry - sl_distance)
         : NormalizePrice(entry + sl_distance);
      tp = 0.0;
      return entry > 0.0 && sl > 0.0 && (type == ORDER_TYPE_BUY_STOP ? sl < entry : sl > entry);
   }

   double lock_fraction = MathMax(0.10, MathMin(0.80, InpNewestSLPreviousLegLockFraction));
   double existing_protection = MostProtectiveExistingStop(side);
   double required_gross = MathMax(0.0, InpSharedSLMinimumNetProfitMoney) + SharedStopCommissionReserveMoney(pending_volume);
   double reserve = MathMax(0, InpSharedSLSlippageReservePoints) * point;
   double minimum_lock = MathMax(2.0 * tick_size, 2.0 * point);

   // Recalculate entry and target together. A stronger Position 1/shared stop can force
   // the future entry farther away, but the stop is never weakened.
   for(int attempt=0; attempt<24; attempt++)
   {
      double gap = MathAbs(entry - protect_anchor_price);
      double candidate = type == ORDER_TYPE_BUY_STOP
         ? protect_anchor_price + gap * lock_fraction
         : protect_anchor_price - gap * lock_fraction;

      double target_price = 0.0;
      if(!FindProjectedTargetPrice(side, required_gross, entry, entry, pending_volume, target_price))
      {
         entry = type == ORDER_TYPE_BUY_STOP
            ? RoundPendingPrice(type, entry + MathMax(tick_size, gap * 0.12))
            : RoundPendingPrice(type, entry - MathMax(tick_size, gap * 0.12));
         continue;
      }

      candidate = type == ORDER_TYPE_BUY_STOP ? MathMax(candidate, target_price) : MathMin(candidate, target_price);
      candidate = type == ORDER_TYPE_BUY_STOP ? candidate + reserve : candidate - reserve;
      if(existing_protection > 0.0)
         candidate = type == ORDER_TYPE_BUY_STOP ? MathMax(candidate, existing_protection) : MathMin(candidate, existing_protection);
      candidate = RoundProtectiveStop(side, candidate);

      bool anchor_locked = type == ORDER_TYPE_BUY_STOP
         ? candidate > protect_anchor_price + minimum_lock
         : candidate < protect_anchor_price - minimum_lock;
      bool geometry_ok = type == ORDER_TYPE_BUY_STOP
         ? candidate < entry - stops_distance
         : candidate > entry + stops_distance;

      if(anchor_locked && geometry_ok)
      {
         sl = candidate;
         tp = 0.0;
         return entry > 0.0 && sl > 0.0;
      }

      double required_entry = type == ORDER_TYPE_BUY_STOP
         ? candidate + stops_distance + tick_size
         : candidate - stops_distance - tick_size;
      entry = RoundPendingPrice(type, required_entry);

      MqlTick latest;
      if(SymbolInfoTick(trade_symbol, latest))
      {
         if(type == ORDER_TYPE_BUY_STOP)
            entry = RoundPendingPrice(type, MathMax(entry, latest.ask + distance));
         else
            entry = RoundPendingPrice(type, MathMin(entry, latest.bid - distance));
      }
   }

   return false;
}

bool PendingOrderInsideFreeze(ENUM_ORDER_TYPE type, double existing_price)
{
   double freeze = BrokerFreezeDistancePrice();
   if(freeze <= 0) return false;
   MqlTick tick;
   if(!SymbolInfoTick(trade_symbol, tick)) return true;
   double buffer = PendingAdaptiveBufferPrice();
   if(type == ORDER_TYPE_BUY_STOP) return existing_price - tick.ask <= freeze + buffer;
   if(type == ORDER_TYPE_SELL_STOP) return tick.bid - existing_price <= freeze + buffer;
   return false;
}

bool FindOurPendingOrder(ENUM_ORDER_TYPE wanted, ulong &ticket, double &price, double &sl, double &tp, datetime &setup)
{
   ticket = 0; price = 0.0; sl = 0.0; tp = 0.0; setup = 0;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong current = OrderGetTicket(i);
      if(current == 0 || !OrderSelect(current) || !IsOurSelectedOrder()) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != wanted) continue;
      ticket = current;
      price = OrderGetDouble(ORDER_PRICE_OPEN);
      sl = OrderGetDouble(ORDER_SL);
      tp = OrderGetDouble(ORDER_TP);
      setup = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      return true;
   }
   return false;
}

bool DeleteOneUnwantedPending(bool want_buy, bool want_sell)
{
   bool kept_buy = false;
   bool kept_sell = false;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket) || !IsOurSelectedOrder()) continue;
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      bool keep = false;
      if(type == ORDER_TYPE_BUY_STOP && want_buy && !kept_buy) { kept_buy = true; keep = true; }
      if(type == ORDER_TYPE_SELL_STOP && want_sell && !kept_sell) { kept_sell = true; keep = true; }
      if(keep) continue;

      double price = OrderGetDouble(ORDER_PRICE_OPEN);
      if(PendingOrderInsideFreeze(type, price))
      {
         pending_sync_state = "WAITING FREEZE";
         return false;
      }
      if(!TradeRequestAvailable()) return false;

      double volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
      string role = SelectedPendingRole();
      MarkTradeRequest();
      bool submitted = trade.OrderDelete(ticket);
      uint code = trade.ResultRetcode();
      if(!submitted || !DeleteResultAccepted(code))
      {
         RegisterPendingFailure(code);
         SendOrderActivity("DELETE-FAILED", role, type, ticket, volume, price, trade.ResultRetcodeDescription());
         return false;
      }
      delete_wait_ticket = ticket;
      delete_wait_started_ms = GetTickCount64();
      SendOrderActivity("CANCEL-REQUESTED", role, type, ticket, volume, price, "removing duplicate or wrong-side pending order");
      return true;
   }
   return false;
}

bool ModifyPendingOrder(ulong ticket, ENUM_ORDER_TYPE type, string role, double desired_price, double atr_value, string reason)
{
   if(ticket == 0 || !OrderSelect(ticket) || !IsOurSelectedOrder() || !TradeRequestAvailable()) return false;
   double existing_price = OrderGetDouble(ORDER_PRICE_OPEN);
   if(PendingOrderInsideFreeze(type, existing_price))
   {
      pending_sync_state = "WAITING FREEZE";
      return false;
   }

   double safe_price = 0.0, sl = 0.0, tp = 0.0;
   if(!BuildSafePendingLevels(type, role, OrderGetDouble(ORDER_VOLUME_CURRENT), desired_price, atr_value, 0.0, safe_price, sl, tp)) return false;
   MarkTradeRequest();
   bool submitted = trade.OrderModify(ticket, safe_price, sl, tp, ORDER_TIME_GTC, 0, 0.0);
   uint code = trade.ResultRetcode();
   if(!submitted || !TradeResultAccepted(code))
   {
      RegisterPendingFailure(code);
      SendOrderActivity("MODIFY-FAILED", role, type, ticket, OrderGetDouble(ORDER_VOLUME_CURRENT), safe_price, reason + " | " + trade.ResultRetcodeDescription());
      return false;
   }
   pending_invalid_price_streak = 0;
   SendOrderActivity("MODIFIED", role, type, ticket, OrderGetDouble(ORDER_VOLUME_CURRENT), safe_price, reason);
   if(type == ORDER_TYPE_BUY_STOP) last_bracket_buy_price = safe_price;
   if(type == ORDER_TYPE_SELL_STOP) last_bracket_sell_price = safe_price;
   return true;
}

bool SyncPendingOrderSet(bool want_buy, bool want_sell, double desired_buy, double desired_sell, double volume, double atr_value, string role, string reason)
{
   if(delete_wait_ticket > 0 && OrderSelect(delete_wait_ticket)) return false;
   if(DeleteOneUnwantedPending(want_buy, want_sell)) return false;

   ulong ticket = 0;
   double price = 0.0, sl = 0.0, tp = 0.0;
   datetime setup = 0;
   double refresh_distance = MathMax(atr_value * InpBracketRefreshATR, PendingAdaptiveBufferPrice());

   if(want_buy)
   {
      if(!FindOurPendingOrder(ORDER_TYPE_BUY_STOP, ticket, price, sl, tp, setup))
      {
         PlacePendingOrder(ORDER_TYPE_BUY_STOP, role, volume, desired_buy, atr_value, 0.0, reason);
         return false;
      }
      bool buy_age_expired = InpBracketMaximumAgeSeconds > 0 && TimeCurrent() - setup >= InpBracketMaximumAgeSeconds;
      if((MathAbs(price - desired_buy) >= refresh_distance || buy_age_expired) && !PendingOrderInsideFreeze(ORDER_TYPE_BUY_STOP, price))
      {
         ModifyPendingOrder(ticket, ORDER_TYPE_BUY_STOP, role, desired_buy, atr_value, reason + " refresh");
         return false;
      }
   }

   if(want_sell)
   {
      if(!FindOurPendingOrder(ORDER_TYPE_SELL_STOP, ticket, price, sl, tp, setup))
      {
         PlacePendingOrder(ORDER_TYPE_SELL_STOP, role, volume, desired_sell, atr_value, 0.0, reason);
         return false;
      }
      bool sell_age_expired = InpBracketMaximumAgeSeconds > 0 && TimeCurrent() - setup >= InpBracketMaximumAgeSeconds;
      if((MathAbs(price - desired_sell) >= refresh_distance || sell_age_expired) && !PendingOrderInsideFreeze(ORDER_TYPE_SELL_STOP, price))
      {
         ModifyPendingOrder(ticket, ORDER_TYPE_SELL_STOP, role, desired_sell, atr_value, reason + " refresh");
         return false;
      }
   }

   return (!want_buy || PendingOrderPrice(ORDER_TYPE_BUY_STOP) > 0) && (!want_sell || PendingOrderPrice(ORDER_TYPE_SELL_STOP) > 0);
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

double PendingOrderPrice(ENUM_ORDER_TYPE wanted)
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket) || !IsOurSelectedOrder()) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) == wanted) return OrderGetDouble(ORDER_PRICE_OPEN);
   }
   return 0.0;
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

double SharedStopCommissionReserveMoney(double extra_volume)
{
   double total_lots = BasketLots() + MathMax(0.0, extra_volume);
   return MathMax(0.0, InpSharedSLCommissionReservePerLot) * total_lots;
}

bool ProjectedBasketProfitAtPrice(string side, double close_price, double extra_entry, double extra_volume, double &total_profit)
{
   total_profit = 0.0;
   ENUM_ORDER_TYPE calc_type;
   if(side == "BUY") calc_type = ORDER_TYPE_BUY;
   else if(side == "SELL") calc_type = ORDER_TYPE_SELL;
   else return false;
   if(close_price <= 0.0) return false;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string position_side = type == POSITION_TYPE_BUY ? "BUY" : "SELL";
      if(position_side != side) continue;

      double leg_profit = 0.0;
      if(!OrderCalcProfit(calc_type, trade_symbol, PositionGetDouble(POSITION_VOLUME), PositionGetDouble(POSITION_PRICE_OPEN), close_price, leg_profit))
         return false;
      total_profit += leg_profit;
   }

   if(extra_volume > 0.0 && extra_entry > 0.0)
   {
      double extra_profit = 0.0;
      if(!OrderCalcProfit(calc_type, trade_symbol, NormalizeVolume(extra_volume), extra_entry, close_price, extra_profit))
         return false;
      total_profit += extra_profit;
   }
   return true;
}

bool LatestTwoSameSideEntries(string side, double &previous_entry, double &newest_entry, ulong &newest_position_identifier)
{
   previous_entry = 0.0;
   newest_entry = 0.0;
   newest_position_identifier = 0;
   bool found_latest = false;
   bool found_previous = false;
   datetime latest_time = 0;
   datetime previous_time = 0;
   long latest_msc = 0;
   long previous_msc = 0;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string position_side = type == POSITION_TYPE_BUY ? "BUY" : "SELL";
      if(position_side != side) continue;

      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      long opened_msc = PositionGetInteger(POSITION_TIME_MSC);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);

      if(!found_latest || opened > latest_time || (opened == latest_time && opened_msc > latest_msc))
      {
         if(found_latest)
         {
            found_previous = true;
            previous_time = latest_time;
            previous_msc = latest_msc;
            previous_entry = newest_entry;
         }
         found_latest = true;
         latest_time = opened;
         latest_msc = opened_msc;
         newest_entry = entry;
         newest_position_identifier = identifier;
      }
      else if(!found_previous || opened > previous_time || (opened == previous_time && opened_msc > previous_msc))
      {
         found_previous = true;
         previous_time = opened;
         previous_msc = opened_msc;
         previous_entry = entry;
      }
   }
   return found_latest && found_previous;
}

double MostProtectiveExistingStop(string side)
{
   double selected = 0.0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string position_side = type == POSITION_TYPE_BUY ? "BUY" : "SELL";
      if(position_side != side) continue;
      double sl = PositionGetDouble(POSITION_SL);
      if(sl <= 0.0) continue;
      if(selected <= 0.0) selected = sl;
      else if(side == "BUY") selected = MathMax(selected, sl);
      else selected = MathMin(selected, sl);
   }
   return selected;
}

bool FindProjectedTargetPrice(string side, double required_gross_profit, double newest_entry, double extra_entry, double extra_volume, double &target_price)
{
   target_price = 0.0;
   double tick_size = SymbolInfoDouble(trade_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0) tick_size = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   double atr_value = MathMax(CurrentOrderAtr(), InpFallbackATRPrice);
   double profit = 0.0;

   if(side == "BUY")
   {
      double high = newest_entry - tick_size;
      double low = MathMax(tick_size, AverageBasketEntry() - MathMax(20.0 * atr_value, newest_entry * 0.05));
      if(!ProjectedBasketProfitAtPrice(side, high, extra_entry, extra_volume, profit) || profit < required_gross_profit) return false;
      for(int i=0; i<64; i++)
      {
         double mid = (low + high) * 0.5;
         if(!ProjectedBasketProfitAtPrice(side, mid, extra_entry, extra_volume, profit)) return false;
         if(profit >= required_gross_profit) high = mid;
         else low = mid;
      }
      target_price = high;
      return true;
   }

   if(side == "SELL")
   {
      double low = newest_entry + tick_size;
      double high = MathMax(AverageBasketEntry(), newest_entry) + MathMax(20.0 * atr_value, newest_entry * 0.05);
      if(!ProjectedBasketProfitAtPrice(side, low, extra_entry, extra_volume, profit) || profit < required_gross_profit) return false;
      for(int i=0; i<64; i++)
      {
         double mid = (low + high) * 0.5;
         if(!ProjectedBasketProfitAtPrice(side, mid, extra_entry, extra_volume, profit)) return false;
         if(profit >= required_gross_profit) low = mid;
         else high = mid;
      }
      target_price = low;
      return true;
   }
   return false;
}

int CalculateSharedBasketStop(string side, double &stop_price, string &reason)
{
   stop_price = 0.0;
   reason = "";
   if(side != "BUY" && side != "SELL") return 0;
   if(CountOurPositionsBySide(side) < 2) return 0;

   double previous_entry = 0.0;
   double newest_entry = 0.0;
   ulong newest_identifier = 0;
   if(!LatestTwoSameSideEntries(side, previous_entry, newest_entry, newest_identifier)) return 0;
   if(!SequentialFillProgressed(side, previous_entry, newest_entry))
   {
      reason = StringFormat("%s shared-stop sequence invalid: newest %.2f / previous %.2f", side, newest_entry, previous_entry);
      return -2;
   }

   double lock_fraction = MathMax(0.10, MathMin(0.80, InpNewestSLPreviousLegLockFraction));
   double fraction_candidate = side == "BUY"
      ? previous_entry + (newest_entry - previous_entry) * lock_fraction
      : previous_entry - (previous_entry - newest_entry) * lock_fraction;

   double required_gross = MathMax(0.0, InpSharedSLMinimumNetProfitMoney) + SharedStopCommissionReserveMoney(0.0);
   double target_price = 0.0;
   if(!FindProjectedTargetPrice(side, required_gross, newest_entry, 0.0, 0.0, target_price))
   {
      reason = "Actual fill spacing cannot create the requested profitable shared stop";
      return -2;
   }

   double candidate = side == "BUY" ? MathMax(fraction_candidate, target_price) : MathMin(fraction_candidate, target_price);

   double point = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   double tick_size = SymbolInfoDouble(trade_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0) tick_size = point;
   double reserve = MathMax(0, InpSharedSLSlippageReservePoints) * point;
   candidate = side == "BUY" ? candidate + reserve : candidate - reserve;

   // Never weaken an already-protected basket, but do not add the reserve again to
   // an existing shared stop on every timer/tick pass.
   double existing = MostProtectiveExistingStop(side);
   if(existing > 0.0)
      candidate = side == "BUY" ? MathMax(candidate, existing) : MathMin(candidate, existing);

   if(side == "BUY")
      candidate = MathFloor(candidate / tick_size + 0.0000000001) * tick_size;
   else
      candidate = MathCeil(candidate / tick_size - 0.0000000001) * tick_size;
   candidate = NormalizePrice(candidate);

   if(side == "BUY" && (candidate <= previous_entry || candidate >= newest_entry))
   {
      reason = StringFormat("BUY shared stop %.2f is not between previous %.2f and newest %.2f", candidate, previous_entry, newest_entry);
      return -2;
   }
   if(side == "SELL" && (candidate >= previous_entry || candidate <= newest_entry))
   {
      reason = StringFormat("SELL shared stop %.2f is not between previous %.2f and newest %.2f", candidate, previous_entry, newest_entry);
      return -2;
   }

   double projected = 0.0;
   if(!ProjectedBasketProfitAtPrice(side, candidate, 0.0, 0.0, projected))
   {
      reason = "Could not calculate shared-stop basket profit";
      return 0;
   }
   double projected_net = projected - SharedStopCommissionReserveMoney(0.0);
   if(projected_net + 0.0001 < MathMax(0.0, InpSharedSLMinimumNetProfitMoney))
   {
      reason = StringFormat("Shared stop %.2f protects only $%.2f after reserve", candidate, projected_net);
      return -2;
   }

   MqlTick tick;
   if(!SymbolInfoTick(trade_symbol, tick)) return 0;
   double modification_distance = MathMax(BrokerStopsDistancePrice(), BrokerFreezeDistancePrice()) + 2.0 * tick_size;
   if(side == "BUY")
   {
      if(tick.bid <= candidate + tick_size)
      {
         stop_price = candidate;
         reason = StringFormat("Bid %.2f reached shared basket stop %.2f before all positions synchronised", tick.bid, candidate);
         return -1;
      }
      if(candidate > tick.bid - modification_distance)
      {
         stop_price = candidate;
         reason = StringFormat("Waiting for Bid to move far enough above shared stop %.2f", candidate);
         return 0;
      }
   }
   else
   {
      if(tick.ask >= candidate - tick_size)
      {
         stop_price = candidate;
         reason = StringFormat("Ask %.2f reached shared basket stop %.2f before all positions synchronised", tick.ask, candidate);
         return -1;
      }
      if(candidate < tick.ask + modification_distance)
      {
         stop_price = candidate;
         reason = StringFormat("Waiting for Ask to move far enough below shared stop %.2f", candidate);
         return 0;
      }
   }

   stop_price = candidate;
   reason = StringFormat("All positions will share %s SL %.2f", side, candidate);
   return 1;
}

bool PositionHasSharedStop(ulong ticket, double target)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) return true;
   double point = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   double tick_size = SymbolInfoDouble(trade_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0) tick_size = point;
   double tolerance = MathMax(tick_size * 0.25, MathMax(0, InpSharedSLSyncTolerancePoints) * point);
   return MathAbs(PositionGetDouble(POSITION_SL) - target) <= tolerance;
}

bool SynchronizeSharedBasketStop()
{
   string side = campaign_current_side;
   if(side != "BUY" && side != "SELL" || CountOurPositionsBySide(side) < 2)
   {
      shared_basket_stop = 0.0;
      shared_stop_state = "NOT ACTIVE";
      shared_stop_synced_positions = 0;
      return true;
   }

   double target = 0.0;
   string reason = "";
   int status = CalculateSharedBasketStop(side, target, reason);
   if(status == -2)
   {
      FlagExecutionIntegrityBreach(reason, newest_position_id);
      shared_stop_state = reason;
      return false;
   }
   if(status == -1)
   {
      shared_basket_stop = target;
      shared_stop_state = reason;
      BankBasket("SHARED BASKET SL LEVEL REACHED", BasketProfit());
      return false;
   }
   if(status == 0)
   {
      shared_stop_state = reason == "" ? "WAITING TO CALCULATE SHARED SL" : reason;
      pending_sync_state = "WAITING TO ARM SHARED BASKET SL";
      return false;
   }

   shared_basket_stop = target;
   shared_stop_synced_positions = 0;
   int total = CountOurPositionsBySide(side);
   UpdateNewestCanary();

   // Protect the newest leg first. If price reverses during synchronisation, its SL remains
   // the immediate basket-exit canary while the older positions are being updated.
   if(newest_ticket > 0 && PositionSelectByTicket(newest_ticket) && IsOurSelectedPosition())
   {
      ENUM_POSITION_TYPE newest_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string newest_side = newest_type == POSITION_TYPE_BUY ? "BUY" : "SELL";
      if(newest_side == side && !PositionHasSharedStop(newest_ticket, target))
      {
         if(!TradeRequestAvailable()) return false;
         double tp = PositionGetDouble(POSITION_TP);
         MarkTradeRequest();
         bool submitted = trade.PositionModify(newest_ticket, target, tp);
         uint code = trade.ResultRetcode();
         if(!submitted || !TradeResultAccepted(code))
         {
            RegisterPendingFailure(code);
            shared_stop_state = StringFormat("Shared SL modify failed for newest %I64u: %u %s", newest_ticket, code, trade.ResultRetcodeDescription());
            last_event = shared_stop_state;
            return false;
         }
         shared_stop_state = StringFormat("Shared SL %.2f applied to newest position; synchronising older positions", target);
         last_event = shared_stop_state;
         return false;
      }
   }

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsOurSelectedPosition()) continue;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string position_side = type == POSITION_TYPE_BUY ? "BUY" : "SELL";
      if(position_side != side) continue;
      if(PositionHasSharedStop(ticket, target))
      {
         shared_stop_synced_positions++;
         continue;
      }
      if(!TradeRequestAvailable()) return false;
      double tp = PositionGetDouble(POSITION_TP);
      MarkTradeRequest();
      bool submitted = trade.PositionModify(ticket, target, tp);
      uint code = trade.ResultRetcode();
      if(!submitted || !TradeResultAccepted(code))
      {
         RegisterPendingFailure(code);
         shared_stop_state = StringFormat("Shared SL modify failed for %I64u: %u %s", ticket, code, trade.ResultRetcodeDescription());
         last_event = shared_stop_state;
         return false;
      }
      shared_stop_state = StringFormat("Synchronising shared SL %.2f: %d/%d positions confirmed", target, shared_stop_synced_positions, total);
      last_event = shared_stop_state;
      return false;
   }

   shared_stop_synced_positions = total;
   shared_stop_state = StringFormat("ALL %d %s POSITIONS SHARE SL %.2f", total, side, target);
   pending_sync_state = shared_stop_state;
   bank_candidate = true;
   bank_candidate_reason = "Every open position has the same broker-side basket SL";
   return true;
}



double BasketProtectedStop()
{
   if(shared_basket_stop > 0.0) return shared_basket_stop;
   UpdateNewestCanary();
   if(newest_ticket > 0 && PositionSelectByTicket(newest_ticket))
      return PositionGetDouble(POSITION_SL);
   return 0.0;
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
   QueueJson("/api/ea/scan", json);
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
   int newest_age = newest_leg_open_time > 0 ? (int)(TimeCurrent() - newest_leg_open_time) : 0;

   string json = StringFormat(
      "{\"account\":\"%I64d\",\"symbol\":\"%s\",\"version\":\"2.10\",\"balance\":%.2f,\"equity\":%.2f,\"margin\":%.2f,\"freeMargin\":%.2f,\"marginLevel\":%.2f,\"bid\":%.5f,\"ask\":%.5f,\"spreadPoints\":%.1f,\"medianSpreadPoints\":%.1f,\"terminalConnected\":%s,\"algoAllowed\":%s,\"autonomous\":%s,\"emergency\":%s,\"engineState\":\"%s\",\"bracketState\":\"%s\",\"campaignPhase\":\"%s\",\"campaignStartSide\":\"%s\",\"campaignCurrentSide\":\"%s\",\"campaignInvalidationPrice\":%.5f,\"campaignBuyLegs\":%d,\"campaignSellLegs\":%d,\"campaignReversalCount\":%d,\"telemetryQueueDepth\":%d,\"bracketBuyPrice\":%.5f,\"bracketSellPrice\":%.5f,\"positionOpen\":%s,\"positionCount\":%d,\"pendingCount\":%d,\"side\":\"%s\",\"totalLots\":%.2f,\"averageEntry\":%.5f,\"currentPrice\":%.5f,\"protectedStop\":%.5f,\"floatingProfit\":%.2f,\"peakBasketProfit\":%.2f,\"basketMae\":%.2f,\"basketStartedAt\":%I64d,\"positionsOpened\":%d,\"maxConcurrentPositions\":%d,\"newestTicket\":\"%I64u\",\"newestLegProfit\":%.2f,\"newestLegPeak\":%.2f,\"newestLegAgeSeconds\":%d,\"bankCandidate\":%s,\"bankReason\":\"%s\",\"closePending\":%s,\"closeReason\":\"%s\",\"closeAttempts\":%d,\"dailyPnl\":%.2f,\"basketsToday\":%d,\"consecutiveLosses\":%d,\"momentumState\":\"%s\",\"liveDirection\":\"%s\",\"buyScore\":%d,\"sellScore\":%d,\"velocity1s\":%.5f,\"velocity3s\":%.5f,\"velocity10s\":%.5f,\"tickRateRatio\":%.3f,\"acceleration\":%.5f,\"bodyAtr\":%.3f,\"extensionAtr\":%.3f,\"testingMode\":%s,\"settingsVersion\":%d,\"lastEvent\":\"%s\",\"consumedCommandId\":%I64d,\"lastCommandSucceeded\":%s,\"lastCommandResult\":\"%s\"}",
      AccountInfoInteger(ACCOUNT_LOGIN), JsonEscape(trade_symbol), AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY),
      AccountInfoDouble(ACCOUNT_MARGIN), AccountInfoDouble(ACCOUNT_MARGIN_FREE), AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), tick.bid, tick.ask,
      CurrentSpreadPoints(), MedianSpreadPoints(), TerminalInfoInteger(TERMINAL_CONNECTED) ? "true" : "false",
      MQLInfoInteger(MQL_TRADE_ALLOWED) ? "true" : "false", (remote_autonomous && !local_paused) ? "true" : "false", emergency_stopped ? "true" : "false",
      JsonEscape(engine_state), JsonEscape(pending_sync_state), JsonEscape(CampaignPhaseText()), JsonEscape(campaign_start_side), JsonEscape(campaign_current_side),
      campaign_invalidation_price, campaign_buy_legs, campaign_sell_legs, campaign_reversal_count, http_queue_count,
      PendingOrderPrice(ORDER_TYPE_BUY_STOP), PendingOrderPrice(ORDER_TYPE_SELL_STOP), positions > 0 ? "true" : "false", positions, pending, JsonEscape(side), lots, average, current,
      BasketProtectedStop(), BasketProfit(), peak_basket_profit, basket_mae, (long)basket_started_at * 1000, basket_positions_opened, basket_max_concurrent_positions,
      newest_ticket, newest_leg_current_profit, newest_leg_peak_profit, newest_age, bank_candidate ? "true" : "false", JsonEscape(bank_candidate_reason),
      close_pending ? "true" : "false", JsonEscape(close_reason), close_attempts, daily_pnl, baskets_today, consecutive_losses,
      have_scan ? JsonEscape(last_scan.momentum_state) : "WARMING", have_scan ? JsonEscape(last_scan.watch_direction) : "NONE",
      have_scan ? last_scan.buy_score : 0, have_scan ? last_scan.sell_score : 0, have_scan ? last_scan.velocity_1s : 0.0,
      have_scan ? last_scan.velocity_3s : 0.0, have_scan ? last_scan.velocity_10s : 0.0, have_scan ? last_scan.tick_rate_ratio : 0.0,
      have_scan ? last_scan.acceleration : 0.0, have_scan ? last_scan.body_atr : 0.0, have_scan ? last_scan.extension_atr : 0.0,
      runtime_testing_mode ? "true" : "false", runtime_settings_version, JsonEscape(last_event), last_command_id, last_command_succeeded ? "true" : "false", JsonEscape(last_command_result));
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

   int incoming_version = (int)StringToInteger(ParseLineValue(body, "settings_version"));
   if(incoming_version > runtime_settings_version)
   {
      runtime_testing_mode = ParseLineValue(body, "testing_mode") == "true";
      runtime_fixed_lot = StringToDouble(ParseLineValue(body, "fixed_lot"));
      runtime_use_equity_scaling = ParseLineValue(body, "use_equity_scaling") == "true";
      runtime_equity_per_001 = StringToDouble(ParseLineValue(body, "equity_per_001_lot"));
      runtime_initial_positions = 1;
      runtime_maximum_positions = 0;
      runtime_maximum_total_lots = 0.0;
      runtime_fixed_lot = MathMax(0.01, runtime_fixed_lot);
      runtime_settings_version = incoming_version;
      last_event = StringFormat("Dashboard lot settings applied: %.2f per triggered position; no position, lot, session or cooldown gate", runtime_fixed_lot);
      SendEvent("settings", last_event);
      SavePersistentState();
   }

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
   else if(action == "REBUILD_BRACKET")
   {
      CancelPendingOrders();
      last_bracket_refresh_at = 0;
      last_event = "Current candle straddle rebuild requested";
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
   else if(action == "RESET_TEST_COUNTERS")
   {
      consecutive_losses = 0;
      daily_pnl = 0.0;
      baskets_today = 0;
      day_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      last_event = "Demo testing counters reset; performance database records were retained";
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


bool QueueJson(string endpoint, string json)
{
   if(http_queue_count >= HTTP_QUEUE_SIZE)
   {
      // Drop the oldest telemetry record rather than blocking trade execution.
      http_queue_head = (http_queue_head + 1) % HTTP_QUEUE_SIZE;
      http_queue_count--;
   }

   http_queue_endpoint[http_queue_tail] = endpoint;
   http_queue_payload[http_queue_tail] = json;
   http_queue_attempts[http_queue_tail] = 0;
   http_queue_tail = (http_queue_tail + 1) % HTTP_QUEUE_SIZE;
   http_queue_count++;
   return true;
}

bool FlushOneQueuedPost()
{
   if(http_queue_count <= 0) return true;
   if(http_queue_retry_after_ms > 0 && GetTickCount64() < http_queue_retry_after_ms) return false;

   string endpoint = http_queue_endpoint[http_queue_head];
   string payload = http_queue_payload[http_queue_head];
   bool sent = PostJson(endpoint, payload);
   if(sent)
   {
      http_queue_endpoint[http_queue_head] = "";
      http_queue_payload[http_queue_head] = "";
      http_queue_attempts[http_queue_head] = 0;
      http_queue_head = (http_queue_head + 1) % HTTP_QUEUE_SIZE;
      http_queue_count--;
      http_queue_retry_after_ms = 0;
      return true;
   }

   http_queue_attempts[http_queue_head]++;
   if(http_queue_attempts[http_queue_head] >= 3)
   {
      // Evidence remains in MT5 history even if one telemetry record cannot be delivered.
      http_queue_endpoint[http_queue_head] = "";
      http_queue_payload[http_queue_head] = "";
      http_queue_attempts[http_queue_head] = 0;
      http_queue_head = (http_queue_head + 1) % HTTP_QUEUE_SIZE;
      http_queue_count--;
   }
   http_queue_retry_after_ms = GetTickCount64() + 2000;
   return false;
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
      PrintFormat("EVE Momentum v2.10 POST %s failed. HTTP=%d MQL=%d response=%s", endpoint, status, GetLastError(), CharArrayToString(result));
      return false;
   }
   return true;
}

void SendEvent(string type, string message)
{
   string json = StringFormat("{\"type\":\"%s\",\"message\":\"%s\",\"data\":{\"account\":\"%I64d\",\"symbol\":\"%s\",\"magic\":\"%I64u\"}}",
      JsonEscape(type), JsonEscape(message), AccountInfoInteger(ACCOUNT_LOGIN), JsonEscape(trade_symbol), InpMagicNumber);
   QueueJson("/api/ea/event", json);
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
   // Manual pause and emergency state persist across UTC midnight.
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
   runtime_settings_version = (int)GVGet("settingsver", 0.0);
   runtime_testing_mode = true;
   runtime_fixed_lot = GVGet("fixedlot", InpFixedLotPerPosition);
   runtime_use_equity_scaling = GVGet("equityscale", InpUseEquityLotScaling ? 1.0 : 0.0) > 0.5;
   runtime_equity_per_001 = GVGet("equityper001", InpEquityPer001Lot);
   basket_id = (long)GVGet("basketid", 0.0);
   basket_started_at = (datetime)GVGet("basketstart", 0.0);
   basket_side = GVGet("basketside", 0.0) > 0.5 ? "BUY" : GVGet("basketside", 0.0) < -0.5 ? "SELL" : "NONE";
   peak_basket_profit = GVGet("peak", 0.0);
   basket_mae = GVGet("mae", 0.0);
   basket_positions_opened = (int)GVGet("opened", 0.0);
   basket_max_concurrent_positions = (int)GVGet("maxconcurrent", 0.0);
   close_pending = GVGet("closepending", 0.0) > 0.5;
   close_requested_at = (datetime)GVGet("closerequested", 0.0);
   close_attempts = (int)GVGet("closeattempts", 0.0);
   campaign_start_side = GVGet("campaignstartside", 0.0) > 0.5 ? "BUY" : GVGet("campaignstartside", 0.0) < -0.5 ? "SELL" : "NONE";
   campaign_current_side = GVGet("campaigncurrentside", 0.0) > 0.5 ? "BUY" : GVGet("campaigncurrentside", 0.0) < -0.5 ? "SELL" : "NONE";
   campaign_triggered_at = (datetime)GVGet("campaigntriggered", 0.0);
   campaign_trigger_price = GVGet("campaigntriggerprice", 0.0);
   campaign_buy_legs = (int)GVGet("campaignbuylegs", 0.0);
   campaign_sell_legs = (int)GVGet("campaignselllegs", 0.0);
   campaign_reversal_count = (int)GVGet("campaignreversals", 0.0);
   shared_basket_stop = GVGet("sharedstop", 0.0);
   campaign_attempt_candle = (datetime)GVGet("attemptcandle", 0.0);
   last_campaign_finished_candle = (datetime)GVGet("finishedcandle", 0.0);
   provisional_profit_lock_stop = GVGet("provisionallockstop", 0.0);
   provisional_profit_locked_money = GVGet("provisionallockmoney", 0.0);

   ResetDailyIfNeeded();

   if(CountOurPositions() > 0)
   {
      string live_side = BasketSideText();
      if(campaign_current_side != "BUY" && campaign_current_side != "SELL") campaign_current_side = live_side;
      if(campaign_start_side != "BUY" && campaign_start_side != "SELL") campaign_start_side = campaign_current_side;
      basket_side = campaign_current_side;
      if(basket_started_at <= 0) basket_started_at = EarliestBasketPositionTime();
      if(campaign_triggered_at <= 0) campaign_triggered_at = basket_started_at;
      if(campaign_attempt_candle <= 0)
      {
         campaign_attempt_candle = iTime(trade_symbol, InpExecutionTimeframe, 0);
         if(campaign_attempt_candle <= 0) campaign_attempt_candle = basket_started_at;
      }
      campaign_phase = CountOurPositionsBySide(campaign_current_side) >= 2 ? CAMPAIGN_ACTIVE : CAMPAIGN_OCO_CANCELLING;
      UpdateNewestCanary();
      last_event = close_pending ? "Recovered campaign with full-basket close pending" : "Recovered v2.10 price-triggered ladder campaign";
   }
   else
   {
      basket_started_at = 0;
      basket_id = 0;
      campaign_phase = CAMPAIGN_FLAT;
      ResetStraddleAnchor();
      if(CountOurPendingOrders() > 0)
      {
         datetime current_bar = iTime(trade_symbol, InpExecutionTimeframe, 0);
         straddle_candle_time = current_bar > 0 ? current_bar - 1 : 1;
         CancelPendingOrders();
         last_event = "Recovered flat EA; old pending orders are being replaced with the current candle straddle";
      }
      else
      {
         last_event = "Recovered flat EA; ready for current candle straddle";
      }
   }

   SavePersistentState();
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
   GVSet("settingsver", runtime_settings_version);
   GVSet("testingmode", runtime_testing_mode ? 1.0 : 0.0);
   GVSet("fixedlot", runtime_fixed_lot);
   GVSet("scalelot", runtime_use_equity_scaling ? 1.0 : 0.0);
   GVSet("equityper001", runtime_equity_per_001);
   GVSet("initialpositions", runtime_initial_positions);
   GVSet("runtimepositions", runtime_maximum_positions);
   GVSet("runtimelots", runtime_maximum_total_lots);
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
   GVSet("newestticket", (double)newest_ticket);
   GVSet("newestpeak", newest_leg_peak_profit);
   GVSet("newesttime", (double)newest_leg_open_time);
   GVSet("lastaddprice", last_add_price);
   GVSet("lastaddtime", (double)last_add_at);
   GVSet("sharedstop", shared_basket_stop);
   GVSet("attemptcandle", (double)campaign_attempt_candle);
   GVSet("finishedcandle", (double)last_campaign_finished_candle);
   GVSet("provisionallockstop", provisional_profit_lock_stop);
   GVSet("provisionallockmoney", provisional_profit_locked_money);

   GVSet("campaignphase", (double)campaign_phase);
   GVSet("campaignstartside", campaign_start_side == "BUY" ? 1.0 : campaign_start_side == "SELL" ? -1.0 : 0.0);
   GVSet("campaigncurrentside", campaign_current_side == "BUY" ? 1.0 : campaign_current_side == "SELL" ? -1.0 : 0.0);
   GVSet("campaigntriggered", (double)campaign_triggered_at);
   GVSet("campaigntriggerprice", campaign_trigger_price);
   GVSet("campaigninvalidation", campaign_invalidation_price);
   GVSet("campaignbuylegs", campaign_buy_legs);
   GVSet("campaignselllegs", campaign_sell_legs);
   GVSet("campaignreversals", campaign_reversal_count);
   GVSet("campaigncooldown", (double)campaign_cooldown_until);
   GVSet("campaignanchor", post_campaign_anchor_price);
}

string PersistentPrefix()
{
   return StringFormat("EMB210_%I64d_%I64u_", AccountInfoInteger(ACCOUNT_LOGIN), InpMagicNumber);
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
   double lot = runtime_fixed_lot;
   if(runtime_use_equity_scaling && runtime_equity_per_001 > 0)
   {
      double units = MathFloor(AccountInfoDouble(ACCOUNT_EQUITY) / runtime_equity_per_001);
      lot = MathMax(0.01, units * 0.01);
   }
   return NormalizeVolume(lot);
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
   CreateLabel(PANEL_PREFIX+"TITLE", 10, 18, "EVE MOMENTUM BURST v2.10 - ONE ATTEMPT / PROFIT LOCK", 12, clrWhite);
   CreateLabel(PANEL_PREFIX+"STATUS", 10, 42, "WARMING | Position NONE", 10, clrWhite);
   CreateLabel(PANEL_PREFIX+"SCORE", 10, 62, "BUY 0/11 | SELL 0/11", 10, clrWhite);
   CreateLabel(PANEL_PREFIX+"LIVE", 10, 80, "v1 0.000 | tick x0.00 | extension 0.00 ATR", 9, clrLightSteelBlue);
   CreateButton(PANEL_PREFIX+"PAUSE", 10, 108, 120, 28, "PAUSE EA", clrDarkOrange);
   CreateButton(PANEL_PREFIX+"CLOSE", 136, 108, 120, 28, "CLOSE BASKET", clrSlateGray);
   CreateButton(PANEL_PREFIX+"STOP", 262, 108, 130, 28, "EMERGENCY", clrFireBrick);
}

void UpdatePanel()
{
   string side = BasketSideText();
   string status = StringFormat("%s | %s | %s | Positions %d | Pending %d | Lots %.2f | P/L $%.2f",
      engine_state, CampaignPhaseText(), side, CountOurPositions(), CountOurPendingOrders(), BasketLots(), BasketProfit());
   string scores = have_scan ? StringFormat("ANALYTICS ONLY: BUY %d/11 | SELL %d/11 | %s", last_scan.buy_score, last_scan.sell_score, pending_sync_state) : pending_sync_state;
   string live = have_scan ? StringFormat("v1 %.3f | v3 %.3f | spread %.1f/%.1f | protected SL %.2f", last_scan.velocity_1s, last_scan.velocity_3s, CurrentSpreadPoints(), MedianSpreadPoints(), BasketProtectedStop()) : "Live tick engine warming";
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

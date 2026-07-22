# Strategy specification — v2.05

## 1. Fresh straddle on every candle

While flat, the EA anchors one BUY STOP above the current M1 candle and one SELL STOP below it. The pair remains fixed for that candle. If a new M1 candle begins without a trigger, the old pair is removed and replaced with a fresh pair.

Orders are adjusted only as required for the symbol tick size and the broker's stop/freeze distance.

## 2. First trigger is provisional

Example: the BUY STOP triggers first.

- BUY position 1 opens with its own broker-side SL.
- The original SELL STOP remains active.
- The EA places BUY STOP 2 above BUY position 1.
- The campaign state is `PROVISIONAL 1/2`.

The first trigger does not cancel the opposite side.

## 3. Second same-direction trigger confirms momentum

If BUY STOP 2 triggers before the SELL STOP:

- BUY position 2 opens with its own SL.
- The BUY direction is confirmed.
- The remaining SELL STOP is cancelled.
- No further ladder orders are added until any opposite/legacy pending order has been removed or has otherwise resolved.
- The EA then builds the same-direction pending-stop ladder.

The SELL sequence is identical in reverse.

## 4. False-breakout flip before confirmation

If the SELL STOP triggers before BUY STOP 2:

- The first BUY is treated as a failed breakout.
- The new SELL is retained as SELL position 1.
- The failed BUY is closed.
- The existing BUY STOP becomes the opposite provisional guard.
- The EA places SELL STOP 2 below price.
- SELL must obtain its own second same-direction trigger before confirmation.

This can repeat without a cooldown.

## 5. Continuous confirmed ladder

After confirmation, v2.05 stages `InpLadderOrdersAhead` same-direction pending stops. The default is 12 orders ahead.

As price triggers one order:

- a new position opens from that pending stop;
- the position has a real broker-side SL and no TP;
- it becomes the newest controlling leg;
- the EA replenishes another pending stop beyond the furthest remaining order.

The queue depth is finite, but it is replenished continuously; the campaign has no programmed position-count or total-lot ceiling.

There is no market-order adding, P/L gate, momentum-score gate or add cooldown.

## 6. Profit-lock spacing and individual SLs

Every initial, confirmation and ladder position has its own SL.

For confirmation and ladder orders, the next trigger is widened when necessary so that its SL can sit beyond the previous trigger price while still respecting broker minimum-distance rules. With the default 65% lock fraction:

- BUY ladder: new BUY entry > new BUY SL > previous BUY trigger;
- SELL ladder: new SELL entry < new SELL SL < previous SELL trigger.

Therefore, when the newest SL is reached, the immediately previous position is already on the profitable side by price, and all still-older same-direction entries are farther into profit. Trading costs, slippage and gaps can affect net realised money.

Initial straddle orders and provisional opposite guards use the normal ATR/broker-distance SL because they do not yet have a same-direction predecessor to lock.

## 7. Newest-leg SL banks the basket

The newest active same-direction position is the controlling leg.

When its closing deal is reported as a broker-side stop-loss exit:

1. the EA marks the full basket for closure;
2. it closes every older open position first;
3. it then deletes all untriggered ladder orders;
4. it records the completed campaign;
5. it immediately rebuilds the current-candle two-sided straddle.

An older position closing independently does not trigger the basket close. The controlling event is the SL of the newest tracked position.

## 8. No automatic strategy restrictions

v2.05 does not stop or delay entries because of:

- time of day;
- momentum score;
- spread analysis;
- basket profit or loss;
- number of positions;
- total lots;
- daily result;
- consecutive losses;
- campaign age;
- post-campaign cooldown;
- dashboard news-lock state.

It operates whenever ticks are arriving and the terminal/broker permits trading. Direct user controls—Pause, Autonomous Off, Close Basket and Emergency Stop—remain available.

## 9. Restart recovery

After an EA or terminal restart:

- a one-leg same-direction basket is recovered as provisional;
- a basket with at least two positions in the retained direction is recovered as confirmed;
- the newest live position identifier and SL are rediscovered;
- stale flat pending orders are cleared and replaced with a current-candle straddle;
- v2.05 uses a new persistent-state prefix so it does not inherit v2.04 campaign globals.

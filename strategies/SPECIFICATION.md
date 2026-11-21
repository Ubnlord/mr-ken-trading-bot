# Shared strategy specification

## Timeframes
- Execution chart: H1.
- Bias timeframe: D1 by default; H4 is configurable.

## Bias
Use only the last completed higher-timeframe candle. Bullish bias requires close above fast EMA, fast EMA above slow EMA, and rising fast EMA. Bearish bias is the inverse. Optional ADX threshold blocks weak/unclear trends.

## Pattern
A directional impulse must precede a bounded H1 consolidation. Consolidation geometry is classified as a flag (parallel sloping boundaries) or pennant (converging boundaries). Minimum impulse, maximum retracement, maximum consolidation height and quality threshold are configurable. Pattern boundaries are based on completed candles only.

## Breakout and retest
- Bullish: confirmed H1 close above the upper boundary, then price returns to the breakout level and holds it.
- Bearish: confirmed H1 close below the lower boundary, then price retests from below and holds it.
- Entry is only after a later directional confirmation candle.
- Pending setups expire after a configurable number of H1 bars.

## Risk
- Equity risk is configurable from 0.1% to 1%; default 0.5%.
- Position size is calculated from equity risk and stop distance.
- Stop is beyond the retest swing with optional ATR buffer.
- R multiple supports 1.5, 2.0, 2.5 and 3.0.
- Optional daily equity-loss and trade-count limits, spread estimate guard and session filter.

## Non-repainting and parity
Only closed H1 bars and completed HTF bars are used. No future swing confirmation or lookahead data is permitted. The two implementations must use the same pattern window, impulse/retracement thresholds, breakout/retest timing, confirmation rule, stop buffer, risk model and execution-cost assumptions. Broker-specific lot sizing and tick-value conversion may differ by symbol and must be checked.

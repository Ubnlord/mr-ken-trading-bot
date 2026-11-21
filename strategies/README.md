# Higher-Timeframe Flag/Pennant Strategy

This folder adds a separate Forex strategy package without changing the existing Deriv Blockly bot.

## Files

- `tradingview/HTF_Flag_Pennant_Break_Retest.pine`: Pine Script v6 strategy for TradingView Strategy Tester.
- `mt5/HTF_Flag_Pennant_Break_Retest.mq5`: MetaTrader 5 Expert Advisor source.
- `SPECIFICATION.md`: shared rule definitions and parity checklist.

## TradingView

1. Open TradingView → Pine Editor.
2. Paste/open the Pine file and add it to an **H1** chart.
3. Set the higher-timeframe bias to D1 or H4.
4. Configure commission, slippage, contract sizing and test dates in Strategy Properties.
5. Review Strategy Tester results before considering paper trading.

The script samples the previous completed higher-timeframe candle and only evaluates closed H1 bars. It does not use future candles. Pine's historical data does not provide a reliable broker-specific spread series on all symbols, so the spread guard is a configurable assumed spread in ticks, not a measured historical spread.

## MT5

Compile the EA in MetaEditor, attach it to an H1 chart, enable Algo Trading, and test it in Strategy Tester using real ticks where available. Start on a demo account. Broker symbol contract specifications, tick value, lot step, minimum volume, commissions and execution rules affect sizing and results.

## Important boundaries

- The existing app is a Deriv WebSocket / Blockly application. Deriv options execution is not the same as spot-Forex position execution. The Forex EA is therefore a separate MT5 integration; this package does not silently route Forex orders through the Deriv options API.
- No profitability claim is made. A code-level strategy is not validated until Pine and MT5 builds are compiled, backtests are run on identical symbol/timezone/data/commission assumptions, and trade-by-trade differences are reconciled.
- The two implementations should be compared on the same H1 OHLC data, same D1/H4 bias timeframe, same costs, same risk percentage, same R multiple, same session and same daily limits.

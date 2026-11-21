# Free optimization and validation plan

This workflow is designed to use free tools only. It does not require a paid TradingView plan, paid data feed, VPS, or live account.

## Current baseline (user-provided TradingView screenshot)

- Symbol/timeframe: EURUSD, H1
- Backtest window shown: 2026-01-01 to 2026-11-20
- Closed trades: 4
- Net P&L: -$51.56 (-0.52%)
- Maximum drawdown: $104.55 (1.05%)
- Profitable trades: 1/4 (25%)
- Gross profit: $99.02
- Gross loss: $150.57
- Profit factor: approximately 0.66

This is a very small sample. It is a baseline observation, not evidence that the strategy is profitable or unprofitable over a meaningful sample. The figures are from the user's screenshot and have not been independently reproduced.

## Free workflow

1. Keep the existing strategy as the baseline. Do not overwrite the baseline rules just to improve a short sample.
2. Use TradingView Basic and the available Strategy Tester. No upgrade is required for the current test.
3. Keep EURUSD, H1, D1 bias, date range, initial capital, and risk percentage identical when comparing versions.
4. In Strategy Properties, enter the commission and slippage assumptions that match the intended broker. If unknown, record that costs are unknown; do not describe a zero-cost test as realistic.
5. Test the longest historical window the free chart/data access makes available. If the user can obtain a free EURUSD H1 CSV from a reputable source, the file can also be analyzed locally with free Python tools. Do not buy data.
6. Change one variable group at a time. Record each run before changing another group:
   - Pattern type: flags versus pennants (analyze separately; do not discard either based on four trades).
   - Quality threshold.
   - Breakout body and retest tolerance/expiry.
   - Reward/risk target: 1.5R, 2R, 2.5R, 3R.
   - HTF bias: D1 versus H4.
7. Keep out-of-sample data untouched while selecting settings. Select settings on an earlier period, then validate on a later period that was not used for tuning.
8. Include all costs and inspect trade count, net profit, profit factor, maximum drawdown, average trade, and consecutive losses. A setting that works only on one pair or one short date range is not robust evidence.

## Minimum evidence before considering paper trading

- Aim for at least 100 closed trades across multiple market conditions, if sufficient free history is available.
- Require positive net results after realistic costs on both the tuning and untouched validation periods.
- Prefer stable results across more than one major FX pair, rather than a single optimized pair.
- Review the full trade list and confirm position sizing, stop distance, and order fills.
- Paper/demo test before any live use. Never risk money needed for essentials.

These are conservative evaluation guidelines, not guarantees or a promise of profitability. If the free data/history available cannot produce a sufficiently large sample, report the limitation rather than inventing results.

## Current issue to investigate

The first visible run had four closed trades: three losses and one win. Before changing entry logic, collect a larger sample and apply realistic commission/slippage. The strategy's assumed-spread filter is only a gate; it does not itself subtract historical spread from simulated fills.

/* eslint-disable no-promise-executor-return */
import debounce from 'lodash.debounce';
import { getLocalizedErrorMessage } from '@/constants/backend-error-messages';
import { localize } from '@deriv-com/translations';
import { getLast } from '../../../utils/binary-utils';
import { observer as globalObserver } from '../../../utils/observer';
import { api_base } from '../../api/api-base';
import { getDirection, getLastDigit } from '../utils/helpers';
import { expectPositiveInteger } from '../utils/sanitize';
import * as constants from './state/constants';

let tickListenerKey;

export default Engine =>
    class Ticks extends Engine {
        async watchTicks(symbol) {
            if (symbol && this.symbol !== symbol) {
                this.symbol = symbol;
                const { ticksService } = this.$scope;

                await ticksService.stopMonitor({
                    symbol,
                    key: tickListenerKey,
                });
                const callback = ticks => {
                    if (this.is_proposal_subscription_required) {
                        this.checkProposalReady();
                    }
                    const lastTick = ticks.slice(-1)[0];
                    const { epoch } = lastTick;
                    this.store.dispatch({ type: constants.NEW_TICK, payload: epoch });
                };

                const key = await ticksService.monitor({ symbol, callback });
                tickListenerKey = key;
            }
        }

        checkTicksPromiseExists() {
            return this.$scope.ticksService.ticks_history_promise;
        }

        getTicks(toString = false) {
            return new Promise(resolve => {
                this.$scope.ticksService.request({ symbol: this.symbol }).then(ticks => {
                    const ticks_list = ticks.map(tick => {
                        if (toString) {
                            return tick.quote.toFixed(this.getPipSize());
                        }
                        return tick.quote;
                    });

                    resolve(ticks_list);
                });
            });
        }

        getLastTick(raw, toString = false) {
            return new Promise((resolve, reject) =>
                this.$scope.ticksService
                    .request({ symbol: this.symbol })
                    .then(ticks => {
                        try {
                            let last_tick = raw ? getLast(ticks) : getLast(ticks).quote;
                            if (!raw && toString) {
                                last_tick = last_tick.toFixed(this.getPipSize());
                            }
                            resolve(last_tick);
                        } catch (error) {
                            reject(error);
                        }
                    })
                    .catch(e => {
                        if (e.code === 'MarketIsClosed') {
                            const localizedError = {
                                ...e,
                                message: getLocalizedErrorMessage(e.code, e.details),
                            };
                            globalObserver.emit('Error', localizedError);
                            resolve(e.code);
                        }
                    })
            );
        }

        getLastDigit() {
            return new Promise(resolve => this.getLastTick(false, true).then(tick => resolve(getLastDigit(tick))));
        }

        getLastDigitList() {
            return new Promise(resolve => this.getTicks().then(ticks => resolve(this.getLastDigitsFromList(ticks))));
        }
        getLastDigitsFromList(ticks) {
            const digits = ticks.map(tick => {
                return getLastDigit(tick.toFixed(this.getPipSize()));
            });
            return digits;
        }

        checkDirection(dir) {
            return new Promise(resolve =>
                this.$scope.ticksService
                    .request({ symbol: this.symbol })
                    .then(ticks => resolve(getDirection(ticks) === dir))
            );
        }

        getOhlc(args) {
            const { granularity = this.options.candleInterval || 60, field } = args || {};

            return new Promise(resolve =>
                this.$scope.ticksService
                    .request({ symbol: this.symbol, granularity })
                    .then(ohlc => resolve(field ? ohlc.map(o => o[field]) : ohlc))
            );
        }


        async getStrategySignal(strategy = 'EMA_RSI', granularity = 300) {
            const validGranularity = [60, 300, 900, 1800, 3600, 14400, 86400].includes(Number(granularity))
                ? Number(granularity)
                : 300;
            const candles = await this.getOhlc({ granularity: validGranularity });
            // The newest candle may still be forming. Only closed candles are used.
            const closed = (Array.isArray(candles) ? candles : []).slice(0, -1).filter(candle =>
                ['open', 'high', 'low', 'close'].every(key => Number.isFinite(Number(candle?.[key])))
            );
            if (closed.length < 35) return 'WAIT';

            const closes = closed.map(candle => Number(candle.close));
            const last = closes.length - 1;
            const ema = (values, period) => {
                if (values.length < period) return [];
                const multiplier = 2 / (period + 1);
                let value = values.slice(0, period).reduce((sum, item) => sum + item, 0) / period;
                const output = Array(period - 1).fill(null);
                output.push(value);
                for (let i = period; i < values.length; i += 1) {
                    value = (values[i] - value) * multiplier + value;
                    output.push(value);
                }
                return output;
            };
            const rsi = (values, period = 14) => {
                if (values.length <= period) return [];
                let gains = 0;
                let losses = 0;
                for (let i = 1; i <= period; i += 1) {
                    const change = values[i] - values[i - 1];
                    gains += Math.max(change, 0);
                    losses += Math.max(-change, 0);
                }
                let averageGain = gains / period;
                let averageLoss = losses / period;
                const output = Array(period).fill(null);
                const value = () => (averageLoss === 0 ? 100 : 100 - 100 / (1 + averageGain / averageLoss));
                output.push(value());
                for (let i = period + 1; i < values.length; i += 1) {
                    const change = values[i] - values[i - 1];
                    averageGain = (averageGain * (period - 1) + Math.max(change, 0)) / period;
                    averageLoss = (averageLoss * (period - 1) + Math.max(-change, 0)) / period;
                    output.push(value());
                }
                return output;
            };
            const selected = String(strategy).toUpperCase();
            const fast = ema(closes, 20);
            const slow = ema(closes, 50);
            const strength = rsi(closes, 14);
            const current = closes[last];
            const previous = closes[last - 1];
            if (selected === 'EMA_RSI') {
                if (fast[last] > slow[last] && strength[last] >= 55) return 'CALL';
                if (fast[last] < slow[last] && strength[last] <= 45) return 'PUT';
                return 'WAIT';
            }
            if (selected === 'MACD') {
                const fastEma = ema(closes, 12);
                const slowEma = ema(closes, 26);
                const macdLine = fastEma
                    .map((value, index) => (value == null || slowEma[index] == null ? null : value - slowEma[index]))
                    .filter(value => value != null);
                const signalLine = ema(macdLine, 9);
                const currentSignal = signalLine[signalLine.length - 1];
                const previousSignal = signalLine[signalLine.length - 2];
                const currentMacd = macdLine[macdLine.length - 1];
                const previousMacd = macdLine[macdLine.length - 2];
                if ([currentSignal, previousSignal, currentMacd, previousMacd].some(value => value == null)) return 'WAIT';
                if (previousMacd <= previousSignal && currentMacd > currentSignal) return 'CALL';
                if (previousMacd >= previousSignal && currentMacd < currentSignal) return 'PUT';
                return 'WAIT';
            }
            if (selected === 'RSI_REVERSAL') {
                if (strength[last - 1] < 30 && strength[last] >= 30) return 'CALL';
                if (strength[last - 1] > 70 && strength[last] <= 70) return 'PUT';
                return 'WAIT';
            }
            if (selected === 'BOLLINGER') {
                const bands = values => {
                    const mean = values.reduce((sum, value) => sum + value, 0) / values.length;
                    const deviation = Math.sqrt(values.reduce((sum, value) => sum + (value - mean) ** 2, 0) / values.length);
                    return { upper: mean + 2 * deviation, lower: mean - 2 * deviation };
                };
                const previousBands = bands(closes.slice(-21, -1));
                const currentBands = bands(closes.slice(-20));
                if (previous < previousBands.lower && current >= currentBands.lower) return 'CALL';
                if (previous > previousBands.upper && current <= currentBands.upper) return 'PUT';
                return 'WAIT';
            }
            if (selected === 'BREAKOUT') {
                const range = closed.slice(-21, -1);
                if (range.length < 20) return 'WAIT';
                const high = Math.max(...range.map(candle => Number(candle.high)));
                const low = Math.min(...range.map(candle => Number(candle.low)));
                if (current > high) return 'CALL';
                if (current < low) return 'PUT';
                return 'WAIT';
            }
            return 'WAIT';
        }

        getOhlcFromEnd(args) {
            const { index: i = 1 } = args || {};

            const index = expectPositiveInteger(Number(i), localize('Index must be a positive integer'));

            return new Promise(resolve => this.getOhlc(args).then(ohlc => resolve(ohlc.slice(-index)[0])));
        }

        getPipSize() {
            return this.$scope.ticksService.pipSizes[this.symbol];
        }

        async requestAccumulatorStats() {
            const subscription_id = this.subscription_id_for_accumulators;
            const is_proposal_requested = this.is_proposal_requested_for_accumulators;
            const proposal_request = {
                ...window.Blockly.accumulators_request,
                amount: this?.tradeOptions?.amount,
                basis: this?.tradeOptions?.basis,
                contract_type: 'ACCU',
                currency: this?.tradeOptions?.currency,
                growth_rate: this?.tradeOptions?.growth_rate,
                proposal: 1,
                subscribe: 1,
                underlying_symbol: this?.tradeOptions?.symbol,
            };
            if (!subscription_id && !is_proposal_requested) {
                this.is_proposal_requested_for_accumulators = true;
                if (proposal_request) {
                    await api_base?.api?.send(proposal_request);
                }
            }
        }

        async handleOnMessageForAccumulators() {
            let ticks_stayed_in_list = [];
            return new Promise(resolve => {
                const subscription = api_base.api.onMessage().subscribe(({ data }) => {
                    if (data.msg_type === 'proposal') {
                        try {
                            this.subscription_id_for_accumulators = data.subscription.id;
                            // this was done because we can multile arrays in the respone and the list comes in reverse order
                            const stat_list = (data.proposal.contract_details.ticks_stayed_in || []).flat().reverse();
                            ticks_stayed_in_list = [...stat_list, ...ticks_stayed_in_list];
                            if (ticks_stayed_in_list.length > 0) resolve(ticks_stayed_in_list);
                        } catch (error) {
                            globalObserver.emit('Unexpected message type or no proposal found:', error);
                        }
                    }
                });
                api_base.pushSubscription(subscription);
            });
        }

        async fetchStatsForAccumulators() {
            try {
                // request stats for accumulators
                const debouncedAccumulatorsRequest = debounce(() => this.requestAccumulatorStats(), 300);
                debouncedAccumulatorsRequest();
                // wait for proposal response
                const ticks_stayed_in_list = await this.handleOnMessageForAccumulators();
                return ticks_stayed_in_list;
            } catch (error) {
                globalObserver.emit('Error in subscription promise:', error);
                throw error;
            } finally {
                // forget all proposal subscriptions so we can fetch new stats data on new call
                await api_base?.api?.send({ forget_all: 'proposal' });
                this.is_proposal_requested_for_accumulators = false;
                this.subscription_id_for_accumulators = null;
            }
        }

        async getCurrentStat() {
            try {
                const ticks_stayed_in = await this.fetchStatsForAccumulators();
                return ticks_stayed_in?.[0];
            } catch (error) {
                globalObserver.emit('Error fetching current stat:', error);
            }
        }

        async getStatList() {
            try {
                const ticks_stayed_in = await this.fetchStatsForAccumulators();
                // we need to send only lastest 100 ticks
                return ticks_stayed_in?.slice(0, 100);
            } catch (error) {
                globalObserver.emit('Error fetching current stat:', error);
            }
        }

        async getDelayTickValue(tick_value) {
            return new Promise((resolve, reject) => {
                try {
                    const ticks = [];
                    const symbol = this.symbol;

                    const resolveAndExit = () => {
                        this.$scope.ticksService.stopMonitor({
                            symbol,
                            key: '',
                        });
                        resolve(ticks);
                        ticks.length = 0;
                    };

                    const watchTicks = tick_list => {
                        ticks.push(tick_list);
                        const current_tick = ticks.length;
                        if (current_tick === tick_value) {
                            resolveAndExit();
                        }
                    };

                    const delayExecution = tick_list => watchTicks(tick_list);

                    if (Number(tick_value) <= 0) resolveAndExit();
                    this.$scope.ticksService.monitor({ symbol, callback: delayExecution });
                } catch (error) {
                    reject(new Error(`Failed to start tick monitoring: ${error.message}`));
                }
            });
        }
    };

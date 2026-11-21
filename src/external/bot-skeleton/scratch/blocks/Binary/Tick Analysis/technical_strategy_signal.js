import { localize } from '@deriv-com/translations';
import { modifyContextMenu } from '../../../utils';

window.Blockly.Blocks.technical_strategy_signal = {
    init() {
        this.jsonInit({
            message0: localize('technical strategy signal %1 on timeframe %2'),
            args0: [
                {
                    type: 'field_dropdown',
                    name: 'STRATEGY',
                    options: [
                        [localize('EMA 20/50 + RSI'), 'EMA_RSI'],
                        [localize('MACD crossover'), 'MACD'],
                        [localize('RSI reversal'), 'RSI_REVERSAL'],
                        [localize('Bollinger Bands reversal'), 'BOLLINGER'],
                        [localize('20-candle breakout'), 'BREAKOUT'],
                    ],
                },
                {
                    type: 'field_dropdown',
                    name: 'GRANULARITY',
                    options: [
                        [localize('1 minute'), '60'],
                        [localize('5 minutes'), '300'],
                        [localize('15 minutes'), '900'],
                        [localize('30 minutes'), '1800'],
                        [localize('1 hour'), '3600'],
                        [localize('4 hours'), '14400'],
                        [localize('1 day'), '86400'],
                    ],
                },
            ],
            inputsInline: true,
            output: 'String',
            outputShape: window.Blockly.OUTPUT_SHAPE_ROUND,
            colour: window.Blockly.Colours.Base.colour,
            colourSecondary: window.Blockly.Colours.Base.colourSecondary,
            colourTertiary: window.Blockly.Colours.Base.colourTertiary,
            tooltip: localize('Returns CALL, PUT, or WAIT using completed candles only. It does not place trades.'),
            category: window.Blockly.Categories.Tick_Analysis,
        });
    },
    meta() {
        return {
            display_name: localize('Technical strategy signal'),
            description: localize('Reads completed Deriv candles and returns CALL, PUT, or WAIT. Connect the result to your own trade logic.'),
        };
    },
    customContextMenu(menu) {
        modifyContextMenu(menu);
    },
};

window.Blockly.JavaScript.javascriptGenerator.forBlock.technical_strategy_signal = block => {
    const strategy = block.getFieldValue('STRATEGY');
    const granularity = block.getFieldValue('GRANULARITY');
    return [`Bot.getStrategySignal('${strategy}', ${granularity})`, window.Blockly.JavaScript.Order.ATOMIC];
};

import { localize } from '@deriv-com/translations';
import { modifyContextMenu } from '../../../utils';

window.Blockly.Blocks.technical_strategy_trade = {
    init() {
        this.jsonInit({
            message0: localize('Auto trade signal %1 on timeframe %2'),
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
            previousStatement: 'Purchase',
            nextStatement: false,
            colour: window.Blockly.Colours.Special1.colour,
            colourSecondary: window.Blockly.Colours.Special1.colourSecondary,
            colourTertiary: window.Blockly.Colours.Special1.colourTertiary,
            tooltip: localize('Checks completed candles and automatically purchases CALL or PUT when a fresh signal appears. Use Rise/Fall contracts and test on a demo account first.'),
            category: window.Blockly.Categories.Before_Purchase,
        });
    },
    meta() {
        return {
            display_name: localize('Auto trade technical signal'),
            description: localize('Automatically checks a technical strategy and purchases CALL or PUT when a new signal appears. It is designed for the Purchase conditions block and requires a compatible Rise/Fall trade definition.'),
        };
    },
    restricted_parents: ['before_purchase'],
    customContextMenu(menu) {
        modifyContextMenu(menu);
    },
};

window.Blockly.JavaScript.javascriptGenerator.forBlock.technical_strategy_trade = block => {
    const strategy = block.getFieldValue('STRATEGY');
    const granularity = block.getFieldValue('GRANULARITY');
    return `Bot.executeStrategyTrade('${strategy}', ${granularity});\n`;
};

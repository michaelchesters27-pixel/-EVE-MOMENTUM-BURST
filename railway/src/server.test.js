import test from 'node:test';
import assert from 'node:assert/strict';
import { calculateStats, csvEscape } from './server.js';

test('calculateStats calculates profit factor and win rate', () => {
  const result = calculateStats([
    { side: 'BUY', netProfit: 5, entryScore: 8 },
    { side: 'SELL', netProfit: -2, entryScore: 7 },
    { side: 'BUY', netProfit: 3, entryScore: 10 }
  ]);
  assert.equal(result.trades, 3);
  assert.equal(result.wins, 2);
  assert.equal(result.losses, 1);
  assert.equal(result.netProfit, 6);
  assert.equal(result.profitFactor, 4);
  assert.ok(Math.abs(result.winRate - 66.6666667) < 0.001);
});

test('calculateStats handles no losses', () => {
  const result = calculateStats([{ side: 'BUY', netProfit: 2, entryScore: 9 }]);
  assert.equal(result.profitFactor, 999);
  assert.equal(result.bestTrade, 2);
});

test('csvEscape protects commas and quotes', () => {
  assert.equal(csvEscape('plain'), 'plain');
  assert.equal(csvEscape('a,b'), '"a,b"');
  assert.equal(csvEscape('a"b'), '"a""b"');
});

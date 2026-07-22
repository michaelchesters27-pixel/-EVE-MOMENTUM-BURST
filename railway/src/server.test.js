import test from 'node:test';
import assert from 'node:assert/strict';
import { calculateStats, csvEscape, createHttpServer } from './server.js';

test('calculateStats calculates basket profit factor, legs and win rate', () => {
  const result = calculateStats([
    { side: 'BUY', netProfit: 5, entryScore: 8, positionsOpened: 3, durationSeconds: 20 },
    { side: 'SELL', netProfit: -2, entryScore: 7, positionsOpened: 4, durationSeconds: 30 },
    { side: 'BUY', netProfit: 3, entryScore: 10, positionsOpened: 5, durationSeconds: 10 }
  ]);
  assert.equal(result.baskets, 3);
  assert.equal(result.totalLegs, 12);
  assert.equal(result.averageLegs, 4);
  assert.equal(result.averageDurationSeconds, 20);
  assert.equal(result.wins, 2);
  assert.equal(result.losses, 1);
  assert.equal(result.netProfit, 6);
  assert.equal(result.profitFactor, 4);
  assert.ok(Math.abs(result.winRate - 66.6666667) < 0.001);
});

test('calculateStats handles no losses', () => {
  const result = calculateStats([{ side: 'BUY', netProfit: 2, entryScore: 9, positionsOpened: 3 }]);
  assert.equal(result.profitFactor, 999);
  assert.equal(result.bestTrade, 2);
  assert.equal(result.totalLegs, 3);
});

test('csvEscape protects commas and quotes', () => {
  assert.equal(csvEscape('plain'), 'plain');
  assert.equal(csvEscape('a,b'), '"a,b"');
  assert.equal(csvEscape('a"b'), '"a""b"');
});

test('HTTP server can be constructed without listening', () => {
  const server = createHttpServer();
  assert.equal(typeof server.listen, 'function');
  server.close();
});

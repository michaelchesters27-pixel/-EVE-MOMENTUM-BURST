import test from 'node:test';
import assert from 'node:assert/strict';
import { calculatePerformance, csvEscape, createHttpServer, filterRecordsByMagic, validateSettings, DEFAULT_SETTINGS } from './server.js';

test('performance includes detailed basket metrics', () => {
  const result = calculatePerformance([
    { side: 'BUY', netProfit: 5, positionsOpened: 3, durationSeconds: 20, peakBasketProfit: 7, mae: -1, exitReason: 'CANARY', entryRegime: 'HIGH_MOMENTUM', entryTime: Date.UTC(2026, 6, 22, 12), lotPerLeg: .01 },
    { side: 'SELL', netProfit: -2, positionsOpened: 5, durationSeconds: 40, peakBasketProfit: 1, mae: -3, exitReason: 'STOP', entryRegime: 'NORMAL', entryTime: Date.UTC(2026, 6, 22, 13), lotPerLeg: .01 }
  ]);
  assert.equal(result.summary.baskets, 2);
  assert.equal(result.summary.totalLegs, 8);
  assert.equal(result.summary.netProfit, 3);
  assert.equal(result.summary.profitFactor, 2.5);
  assert.equal(result.bySide.length, 2);
  assert.equal(result.byBankReason.length, 2);
});

test('settings keep lot controls and publish demo ceilings', () => {
  const s = validateSettings({ fixedLot: 0, initialPositions: 50, maxPositions: 4, maxTotalLots: .001 }, DEFAULT_SETTINGS);
  assert.equal(s.fixedLot, .01);
  assert.equal(s.initialPositions, 1);
  assert.equal(s.maxPositions, 10);
  assert.equal(s.maxTotalLots, 0.10);
  assert.equal(s.testingMode, true);
});

test('csv escaping works', () => {
  assert.equal(csvEscape('a,b'), '"a,b"');
  assert.equal(csvEscape('a"b'), '"a""b"');
});

test('server constructs', () => {
  const server = createHttpServer(); assert.equal(typeof server.listen, 'function'); server.close();
});

test('current EA magic excludes older bot records', () => {
  const records = [
    { id: 'old', magic: '2207202630', netProfit: 99 },
    { id: 'current', magic: '2407202641', netProfit: 1.25 },
    { id: 'missing', netProfit: 5 }
  ];
  assert.deepEqual(filterRecordsByMagic(records).map(item => item.id), ['current']);
});

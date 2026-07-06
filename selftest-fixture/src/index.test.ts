import { expect, test } from 'vitest';
import { add } from './index.js';

test('add sums two numbers', () => {
  expect(add(2, 3)).toBe(5);
});

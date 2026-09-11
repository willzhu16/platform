import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['tests/**/*.test.ts'],
    coverage: {
      // `test` already collected coverage; these turn the number into a gate instead of a
      // report nobody reads. Scoped to src/ so config and test files cannot inflate it,
      // and so a brand-new untested source file counts as 0 rather than being invisible.
      include: ['src/**/*.ts'],
      // Opening floor, set below current coverage on purpose. Raise it as the suite grows.
      // Never lower it to turn a red build green — add the missing test instead.
      // Branches opens lower than the rest: the request router has branches no shipped
      // test reaches yet, and the least informative metric should not be the one that
      // blocks. Raise all four together once selftest reports the real numbers.
      thresholds: { lines: 60, functions: 60, statements: 60, branches: 40 },
    },
  },
});

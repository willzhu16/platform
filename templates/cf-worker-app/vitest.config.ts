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
      // Measured on the rendered template by selftest: 76.27 lines/statements, 71.42
      // functions, 52.63 branches. These sit a few points under that, so ordinary churn
      // does not go red but a real regression does. Ratchet up as the suite grows.
      thresholds: { lines: 70, functions: 65, statements: 70, branches: 45 },
    },
  },
});

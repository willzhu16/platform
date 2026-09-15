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
      // Measured on both selftest renders: worst case 98.36 lines, 98.38 statements,
      // 93.33 functions, 90 branches. These sit several points under that, so ordinary
      // churn does not go red but a real regression does. Ratchet up as the suite grows.
      //
      // These are the scaffolding's numbers, and the scaffolding is small. Once this repo
      // has real code, re-baseline against what it actually measures — but do that as a
      // deliberate edit that shows up in a diff, never as a reflex to turn a build green.
      //
      // Coverage is the weaker of the two gates here: it only proves a line ran. See
      // stryker.config.json for the mutation score, which proves a test would object.
      thresholds: { lines: 90, functions: 85, statements: 90, branches: 80 },
    },
  },
});

/**
 * Minimal function exercised by the reusable CI workflow's selftest.
 * Its only job is to give `lint`, `typecheck`, and `test` something real to run so
 * that changes to `ci.yml` are gated by the workflow itself (spec 01 §6.4).
 */
export const add = (first: number, second: number): number => first + second;

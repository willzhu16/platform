/**
 * Structured logger emitting the handbook log schema (spec 05 §2.3): one JSON object per
 * line, `event` as the primary query key. Never log secrets or the bodies of auth/billing
 * routes.
 *
 * Levels filter rather than merely label. A logger drops anything below its minimum, and the
 * default minimum is `info`, so a `debug` line never reaches production logs unless the
 * deployment asks for it by setting `LOG_LEVEL`. Filtering at runtime rather than stripping
 * at build time is deliberate: wrangler bundles with esbuild and nothing in that pipeline
 * reliably removes a call by level, so a build-time promise would be one more comment that
 * describes behaviour the code does not have.
 */

export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

/** Ordered so a level can be compared, not just matched. */
const SEVERITY: Record<LogLevel, number> = { debug: 10, info: 20, warn: 30, error: 40 };

/** Quiet enough that diagnostic detail stays out of production unless asked for. */
export const DEFAULT_LOG_LEVEL: LogLevel = 'info';

/**
 * Read a level from untrusted configuration. Anything unrecognised — absent, misspelled, or
 * a key inherited from Object.prototype — falls back to the default rather than throwing,
 * because a logger that crashes on a typo takes the request down with it.
 */
export const toLogLevel = (value: string | undefined): LogLevel =>
  value !== undefined && Object.hasOwn(SEVERITY, value) ? (value as LogLevel) : DEFAULT_LOG_LEVEL;

export interface LogFields {
  event: string;
  requestId?: string;
  route?: string;
  durationMs?: number;
  userId?: string;
  err?: { message: string; stack?: string; code?: string };
  [key: string]: unknown;
}

export interface Logger {
  debug(fields: LogFields): void;
  info(fields: LogFields): void;
  warn(fields: LogFields): void;
  error(fields: LogFields): void;
}

/**
 * Build one schema-conformant log line. Exported for testing without touching stdout.
 * Schema keys win: caller fields spread first, so a stray `fields.level` can never
 * misreport severity or shadow `ts`/`projectVersion`.
 */
export const formatLine = (level: LogLevel, projectVersion: string, fields: LogFields): string =>
  JSON.stringify({
    ...fields,
    ts: new Date().toISOString(),
    level,
    projectVersion,
  });

/**
 * Create a logger bound to a release version (spec 07 tag), writing JSON lines to console.
 * `minLevel` defaults to `info`; pass `toLogLevel(env.LOG_LEVEL)` to let a deployment widen
 * it. Raising verbosity is a deploy-time decision, never a code change.
 */
export const createLogger = (
  projectVersion: string,
  minLevel: LogLevel = DEFAULT_LOG_LEVEL,
): Logger => {
  const emit = (level: LogLevel, fields: LogFields): void => {
    if (SEVERITY[level] < SEVERITY[minLevel]) {
      return;
    }
    const line = formatLine(level, projectVersion, fields);
    if (level === 'error' || level === 'warn') {
      console.error(line);
    } else {
      console.log(line);
    }
  };
  return {
    debug: (fields) => emit('debug', fields),
    info: (fields) => emit('info', fields),
    warn: (fields) => emit('warn', fields),
    error: (fields) => emit('error', fields),
  };
};

/**
 * Structured logger emitting the handbook log schema (spec 05 §2.3): one JSON object per
 * line, `event` as the primary query key. Never log secrets or the bodies of auth/billing
 * routes. `debug` is intended to be stripped in production builds.
 */

export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

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

/** Create a logger bound to a release version (spec 07 tag), writing JSON lines to console. */
export const createLogger = (projectVersion: string): Logger => {
  const emit = (level: LogLevel, fields: LogFields): void => {
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

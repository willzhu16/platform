import { afterEach, describe, expect, it, vi } from 'vitest';
import { createLogger, DEFAULT_LOG_LEVEL, formatLine, toLogLevel } from '../src/lib/log.js';

afterEach(() => {
  vi.restoreAllMocks();
});

const parse = (line: string) => JSON.parse(line) as Record<string, unknown>;

describe('formatLine', () => {
  it('emits one JSON object per line carrying the schema keys', () => {
    const line = formatLine('info', '1.4.0', { event: 'request.complete', durationMs: 12 });

    expect(line).not.toContain('\n');
    expect(parse(line)).toMatchObject({
      event: 'request.complete',
      durationMs: 12,
      level: 'info',
      projectVersion: '1.4.0',
    });
  });

  it('stamps ts as an ISO 8601 instant', () => {
    expect(parse(formatLine('info', '1.0.0', { event: 'x' })).ts).toMatch(
      /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/,
    );
  });

  it('lets the schema win over caller fields, so severity cannot be misreported', () => {
    // Regression: fields used to spread last, so a stray `level` misreported severity.
    // The dangerous version of that mistake is an error line that queries as info.
    const line = formatLine('error', '1.0.0', {
      event: 'payment.failed',
      level: 'debug',
      projectVersion: '0.0.0-fake',
      ts: 'not a timestamp',
    });

    const entry = parse(line);
    expect(entry.level).toBe('error');
    expect(entry.projectVersion).toBe('1.0.0');
    expect(entry.ts).not.toBe('not a timestamp');
  });
});

describe('createLogger', () => {
  const capture = () => ({
    out: vi.spyOn(console, 'log').mockImplementation(() => undefined),
    err: vi.spyOn(console, 'error').mockImplementation(() => undefined),
  });

  it('sends warn and error to stderr', () => {
    // Log level is the routing, not just a label: an error on stdout is one nobody pages on.
    const { out, err } = capture();
    const log = createLogger('1.0.0');

    log.warn({ event: 'quota.near' });
    log.error({ event: 'quota.exceeded' });

    expect(out).not.toHaveBeenCalled();
    expect(err).toHaveBeenCalledTimes(2);
    expect(parse(err.mock.calls[0]?.[0] as string).level).toBe('warn');
    expect(parse(err.mock.calls[1]?.[0] as string).level).toBe('error');
  });

  it('sends debug and info to stdout', () => {
    const { out, err } = capture();
    const log = createLogger('1.0.0', 'debug');

    log.debug({ event: 'cache.miss' });
    log.info({ event: 'request.start' });

    expect(err).not.toHaveBeenCalled();
    expect(out).toHaveBeenCalledTimes(2);
    expect(parse(out.mock.calls[0]?.[0] as string).level).toBe('debug');
    expect(parse(out.mock.calls[1]?.[0] as string).level).toBe('info');
  });

  it('binds the release version to every line it writes', () => {
    const { out } = capture();

    createLogger('2.3.1').info({ event: 'boot' });

    expect(parse(out.mock.calls[0]?.[0] as string).projectVersion).toBe('2.3.1');
  });
});

describe('log levels filter, they do not just label', () => {
  const capture = () => ({
    out: vi.spyOn(console, 'log').mockImplementation(() => undefined),
    err: vi.spyOn(console, 'error').mockImplementation(() => undefined),
  });

  it('drops debug by default, so diagnostic detail cannot leak into production', () => {
    // The whole point of the default: shipping a debug line must not be enough to publish
    // it. A deployment opts in via LOG_LEVEL; code alone cannot.
    const { out, err } = capture();

    createLogger('1.0.0').debug({ event: 'cache.miss', userId: 'u_123' });

    expect(out).not.toHaveBeenCalled();
    expect(err).not.toHaveBeenCalled();
  });

  it('emits debug when the deployment asks for it', () => {
    const { out } = capture();

    createLogger('1.0.0', 'debug').debug({ event: 'cache.miss' });

    expect(parse(out.mock.calls[0]?.[0] as string).level).toBe('debug');
  });

  it('keeps every level at or above the minimum', () => {
    const { out, err } = capture();
    const log = createLogger('1.0.0', 'warn');

    log.debug({ event: 'a' });
    log.info({ event: 'b' });
    log.warn({ event: 'c' });
    log.error({ event: 'd' });

    expect(out).not.toHaveBeenCalled();
    expect(err).toHaveBeenCalledTimes(2);
    expect(parse(err.mock.calls[0]?.[0] as string).event).toBe('c');
    expect(parse(err.mock.calls[1]?.[0] as string).event).toBe('d');
  });

  it('never silences error, whatever the minimum says', () => {
    // error is the level someone gets paged on. A misconfigured LOG_LEVEL must not be able
    // to hide it, which is why the scale tops out at error rather than going past it.
    const { err } = capture();

    createLogger('1.0.0', 'error').error({ event: 'quota.exceeded' });

    expect(err).toHaveBeenCalledTimes(1);
  });
});

describe('toLogLevel', () => {
  it.each(['debug', 'info', 'warn', 'error'] as const)('accepts %s', (level) => {
    expect(toLogLevel(level)).toBe(level);
  });

  it('falls back to info when the value is absent', () => {
    expect(toLogLevel(undefined)).toBe(DEFAULT_LOG_LEVEL);
    expect(DEFAULT_LOG_LEVEL).toBe('info');
  });

  it('falls back to info on a misspelling rather than throwing', () => {
    // A typo in wrangler.jsonc must not take the request down with it.
    expect(toLogLevel('verbose')).toBe('info');
    expect(toLogLevel('DEBUG')).toBe('info');
    expect(toLogLevel('')).toBe('info');
  });

  it('rejects a key inherited from Object.prototype', () => {
    // `'constructor' in SEVERITY` is true, so an `in` check would accept it and then index
    // to undefined, making every comparison NaN and silently emitting everything.
    expect(toLogLevel('constructor')).toBe('info');
    expect(toLogLevel('toString')).toBe('info');
  });
});

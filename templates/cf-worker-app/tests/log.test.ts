import { afterEach, describe, expect, it, vi } from 'vitest';
import { createLogger, formatLine } from '../src/lib/log.js';

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
    const log = createLogger('1.0.0');

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

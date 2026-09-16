import { afterEach, describe, expect, it, vi } from 'vitest';
import worker, { handleRequest, sentryOptions } from '../src/index.js';

// Two arguments, not three: the handler declares `fetch(request, env)`, so that is the
// arity the wrapped export is typed with. The runtime still passes its own ctx.
const getHealthz = (env: Record<string, string>) =>
  worker.fetch(new Request('https://example.com/healthz'), env as never);

// The default export is wrapped by Sentry.withSentry (spec 08). These cover both DSN
// states, because the wrapper sits in front of every request: a misconfigured client
// would break the whole Worker, not just error reporting.
describe('worker fetch through the Sentry wrapper', () => {
  it('serves /healthz when SENTRY_DSN is unset, so Sentry stays disabled', async () => {
    const response = await getHealthz({ PROJECT_VERSION: 'v1.2.3' });
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ version: 'v1.2.3' });
  });

  it('serves /healthz when SENTRY_DSN is set, so client init does not break the request', async () => {
    const response = await getHealthz({
      PROJECT_VERSION: 'v1.2.3',
      SENTRY_DSN: 'https://examplePublicKey@o0.ingest.sentry.io/0',
    });
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ version: 'v1.2.3' });
  });
});

const get = (path: string, env: Record<string, unknown> = { PROJECT_VERSION: 'v1.2.3' }) =>
  worker.fetch(new Request(`https://example.com${path}`), env as never);

describe('worker routes', () => {
  it('serves the RFC 9116 disclosure record as plain text', async () => {
    // Scanners fetch this path on any public Worker. Serving it as anything but plain text
    // means the record exists and is not read.
    const response = await get('/.well-known/security.txt');

    expect(response.status).toBe(200);
    expect(response.headers.get('content-type')).toBe('text/plain; charset=utf-8');
    expect(await response.text()).toContain('Contact: https://github.com/');
  });

  it('answers an unrouted path rather than 404ing the scaffold', async () => {
    const response = await get('/nothing/here');

    expect(response.status).toBe(200);
    expect(await response.text()).toContain('Hello from ');
  });

  it('puts the security headers on every response, not only the routed ones', async () => {
    for (const path of ['/healthz', '/.well-known/security.txt', '/nothing/here']) {
      const response = await get(path);
      expect(response.headers.get('X-Content-Type-Options')).toBe('nosniff');
    }
  });
});

describe('the request contract', () => {
  const capture = () => ({
    out: vi.spyOn(console, 'log').mockImplementation(() => undefined),
    err: vi.spyOn(console, 'error').mockImplementation(() => undefined),
  });
  const env = { PROJECT_VERSION: 'v1.2.3' } as never;
  const request = () => new Request('https://example.com/some/route');

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('turns a throwing handler into a 500 instead of an unhandled rejection', () => {
    // The guarantee every route depends on and no request can provoke: the Worker still
    // answers, still carries its headers, and does not leak the error to the caller.
    const { err } = capture();

    const response = handleRequest(request(), env, () => {
      throw new Error('handler exploded');
    });

    expect(response.status).toBe(500);
    expect(response.headers.get('x-frame-options')).toBe('DENY');
    expect(err).toHaveBeenCalledTimes(1);
  });

  it('logs the failure as request_failed with the route and the message', () => {
    // If this line is wrong, an outage is invisible in the logs and Sentry is the only
    // place the error exists.
    const { err } = capture();

    handleRequest(request(), env, () => {
      throw new Error('handler exploded');
    });
    const entry = JSON.parse(err.mock.calls[0]?.[0] as string);

    expect(entry.event).toBe('request_failed');
    expect(entry.route).toBe('/some/route');
    expect(entry.level).toBe('error');
    expect(entry.err.message).toBe('handler exploded');
    expect(entry.requestId).toEqual(expect.any(String));
  });

  it('does not answer 500 with the thrown message, which could carry internals', () => {
    capture();

    const response = handleRequest(request(), env, () => {
      throw new Error('connection string postgres://user:hunter2@db');
    });

    return expect(response.text()).resolves.toBe('Internal Error');
  });

  it('logs a successful request once, with its route and duration', () => {
    const { out, err } = capture();

    const response = handleRequest(request(), env, () => new Response('ok'));
    const entry = JSON.parse(out.mock.calls[0]?.[0] as string);

    expect(response.status).toBe(200);
    expect(err).not.toHaveBeenCalled();
    expect(out).toHaveBeenCalledTimes(1);
    expect(entry.event).toBe('request_handled');
    expect(entry.route).toBe('/some/route');
    expect(typeof entry.durationMs).toBe('number');
  });

  it('defaults the release to dev so a log line is never tagged with an empty version', () => {
    const { out } = capture();

    handleRequest(request(), { PROJECT_VERSION: '' } as never, () => new Response('ok'));

    expect(JSON.parse(out.mock.calls[0]?.[0] as string).projectVersion).toBe('dev');
  });
});

describe('sentryOptions', () => {
  it('keeps tracing off and PII out', () => {
    // Both are cost and privacy controls rather than preferences: tracing on would leave
    // the free quota, and sendDefaultPii would ship request data to a third party.
    const options = sentryOptions({
      PROJECT_VERSION: 'v1.2.3',
      SENTRY_DSN: 'https://k@o0.in/0',
    } as never);

    expect(options.tracesSampleRate).toBe(0);
    expect(options.sendDefaultPii).toBe(false);
    expect(options.dsn).toBe('https://k@o0.in/0');
    expect(options.release).toBe('v1.2.3');
  });

  it('tags releases as dev when no version is set, rather than as an empty release', () => {
    const options = sentryOptions({ PROJECT_VERSION: '' } as never);

    expect(options.release).toBe('dev');
    expect(options.dsn).toBeUndefined();
  });
});

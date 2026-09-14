import { describe, expect, it } from 'vitest';
import worker, { sentryOptions } from '../src/index.js';

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

  // The catch branch in src/index.ts is deliberately not covered here. Forcing `handle`
  // to throw means poisoning PROJECT_VERSION, and the catch logs with that same value, so
  // the failure lands in the logger rather than on the path under test. Covering it needs
  // a seam in the worker (an injectable handler), which is a design change, not a test.
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

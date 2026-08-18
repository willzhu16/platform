import { describe, expect, it } from 'vitest';
import worker from '../src/index.js';

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

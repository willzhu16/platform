import fc from 'fast-check';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { verifyTurnstile } from '../src/lib/turnstile.js';

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('verifyTurnstile', () => {
  it('fails closed when siteverify is unavailable', async () => {
    // Regression: a siteverify outage used to throw mid-handler instead of rejecting.
    vi.stubGlobal('fetch', async () => new Response('service unavailable', { status: 503 }));
    await expect(verifyTurnstile('token', 'secret')).resolves.toBe(false);
  });

  it('accepts a submission siteverify confirms', async () => {
    vi.stubGlobal('fetch', async () => Response.json({ success: true }));
    await expect(verifyTurnstile('token', 'secret')).resolves.toBe(true);
  });

  it('rejects a submission siteverify denies', async () => {
    vi.stubGlobal('fetch', async () => Response.json({ success: false }));
    await expect(verifyTurnstile('token', 'secret')).resolves.toBe(false);
  });
});

describe('verifyTurnstile request', () => {
  /** Capture the call siteverify receives, answering with a success the caller can trust. */
  const captureCall = () => {
    const calls: { url: string; init: RequestInit }[] = [];
    vi.stubGlobal('fetch', async (url: string, init: RequestInit) => {
      calls.push({ url, init });
      return Response.json({ success: true });
    });
    return calls;
  };

  const fields = (init: RequestInit) => {
    const body = init.body as FormData;
    return Object.fromEntries([...body.entries()]);
  };

  it('posts to the siteverify endpoint', async () => {
    const calls = captureCall();

    await verifyTurnstile('token', 'secret');

    expect(calls).toHaveLength(1);
    expect(calls[0]?.url).toBe('https://challenges.cloudflare.com/turnstile/v0/siteverify');
    expect(calls[0]?.init.method).toBe('POST');
  });

  it('sends the secret and the token under the field names siteverify expects', async () => {
    // Swapping these two, or renaming either, makes every verification fail closed — which
    // looks exactly like a working bot filter until a real submission is rejected.
    const calls = captureCall();

    await verifyTurnstile('the-token', 'the-secret');

    expect(fields(calls[0]?.init as RequestInit)).toEqual({
      secret: 'the-secret',
      response: 'the-token',
    });
  });

  it('forwards the client IP only when one was given', async () => {
    const calls = captureCall();

    await verifyTurnstile('token', 'secret', '203.0.113.7');
    await verifyTurnstile('token', 'secret');

    expect(fields(calls[0]?.init as RequestInit).remoteip).toBe('203.0.113.7');
    expect(fields(calls[1]?.init as RequestInit)).not.toHaveProperty('remoteip');
  });

  it('rejects a success field that is not the boolean true', async () => {
    // Fail closed on a response shape that is not the documented one, rather than letting
    // a truthy string through.
    vi.stubGlobal('fetch', async () => Response.json({ success: 'true' }));

    await expect(verifyTurnstile('token', 'secret')).resolves.toBe(false);
  });
});

describe('verifyTurnstile fails closed', () => {
  // Bot protection is only worth having if every unclear answer counts as a rejection.
  // These state that as a rule rather than naming the three responses someone thought of.
  it('rejects any success value that is not the boolean true', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.jsonValue().filter((value) => value !== true),
        async (success) => {
          vi.stubGlobal('fetch', async () => Response.json({ success }));

          await expect(verifyTurnstile('token', 'secret')).resolves.toBe(false);
        },
      ),
      { numRuns: 100 },
    );
  });

  it('rejects any non-2xx answer from siteverify', async () => {
    await fc.assert(
      fc.asyncProperty(fc.integer({ min: 400, max: 599 }), async (status) => {
        vi.stubGlobal('fetch', async () => new Response('nope', { status }));

        await expect(verifyTurnstile('token', 'secret')).resolves.toBe(false);
      }),
      { numRuns: 60 },
    );
  });
});

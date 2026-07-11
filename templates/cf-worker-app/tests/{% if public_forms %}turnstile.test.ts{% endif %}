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

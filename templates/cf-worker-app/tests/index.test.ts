import { describe, expect, it } from 'vitest';
import { withSecurityHeaders } from '../src/middleware/security-headers.js';

describe('withSecurityHeaders', () => {
  it('applies the standard security headers', () => {
    const response = withSecurityHeaders(new Response('ok'));
    expect(response.headers.get('X-Content-Type-Options')).toBe('nosniff');
    expect(response.headers.get('Content-Security-Policy')).toContain("default-src 'self'");
  });

  it('sets every header in the starter policy, with its exact value', () => {
    // These are the whole of a new project's browser-side defence until someone tightens
    // them. A weakened value here is invisible in a test that only checks the name is set.
    const headers = withSecurityHeaders(new Response('ok')).headers;

    expect(Object.fromEntries(headers.entries())).toMatchObject({
      'strict-transport-security': 'max-age=31536000; includeSubDomains',
      'content-security-policy': "default-src 'self'; frame-ancestors 'none'",
      'x-content-type-options': 'nosniff',
      'referrer-policy': 'strict-origin-when-cross-origin',
      'x-frame-options': 'DENY',
    });
  });

  it('keeps the body, status and status text of the response it wraps', () => {
    const wrapped = withSecurityHeaders(
      new Response('not found', { status: 404, statusText: 'Not Found' }),
    );

    expect(wrapped.status).toBe(404);
    expect(wrapped.statusText).toBe('Not Found');
    return expect(wrapped.text()).resolves.toBe('not found');
  });

  it('keeps headers the response already carried', () => {
    const wrapped = withSecurityHeaders(
      new Response('{}', { headers: { 'content-type': 'application/json' } }),
    );

    expect(wrapped.headers.get('content-type')).toBe('application/json');
    expect(wrapped.headers.get('X-Frame-Options')).toBe('DENY');
  });
});

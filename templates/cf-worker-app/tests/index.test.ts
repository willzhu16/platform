import { describe, expect, it } from 'vitest';
import { formatLine } from '../src/lib/log.js';
import { withSecurityHeaders } from '../src/middleware/security-headers.js';

describe('withSecurityHeaders', () => {
  it('applies the standard security headers', () => {
    const response = withSecurityHeaders(new Response('ok'));
    expect(response.headers.get('X-Content-Type-Options')).toBe('nosniff');
    expect(response.headers.get('Content-Security-Policy')).toContain("default-src 'self'");
  });
});

describe('formatLine', () => {
  it('emits a schema-conformant JSON line', () => {
    const parsed = JSON.parse(formatLine('info', 'v1.0.0', { event: 'test_event' }));
    expect(parsed).toMatchObject({ level: 'info', projectVersion: 'v1.0.0', event: 'test_event' });
    expect(typeof parsed.ts).toBe('string');
  });

  it('never lets caller fields shadow the schema keys', () => {
    // Regression: fields used to spread last, so a stray `level` misreported severity.
    const parsed = JSON.parse(
      formatLine('info', 'v1.0.0', { event: 'test_event', level: 'error', projectVersion: 'v9' }),
    );
    expect(parsed.level).toBe('info');
    expect(parsed.projectVersion).toBe('v1.0.0');
  });
});

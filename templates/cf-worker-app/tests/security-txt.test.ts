import { describe, expect, it } from 'vitest';
import { buildSecurityTxt } from '../src/lib/security-txt.js';

describe('buildSecurityTxt', () => {
  it('emits an RFC 9116 record with the contact and an expiry one year out', () => {
    const now = new Date('2026-01-01T00:00:00.000Z');
    const txt = buildSecurityTxt('https://example.test/report', now);
    expect(txt).toContain('Contact: https://example.test/report');
    expect(txt).toContain('Expires: 2027-01-01T00:00:00.000Z');
    expect(txt).toContain('Preferred-Languages: en');
    expect(txt.endsWith('\n')).toBe(true);
  });

  it('defaults Expires to a future date so scanners never see a stale record', () => {
    const now = new Date('2026-01-01T00:00:00.000Z');
    const txt = buildSecurityTxt('https://example.test/report', now);
    const expires = txt.match(/Expires: (.+)/)?.[1];
    expect(new Date(expires ?? '').getTime()).toBeGreaterThan(now.getTime());
  });
});

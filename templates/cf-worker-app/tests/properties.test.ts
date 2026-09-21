import fc from 'fast-check';
import { describe, expect, it } from 'vitest';
import { createLogger, formatLine, type LogFields, type LogLevel } from '../src/lib/log.js';
import { buildSecurityTxt } from '../src/lib/security-txt.js';
import { withSecurityHeaders } from '../src/middleware/security-headers.js';

/**
 * Property-based tests. An ordinary test names three inputs; these state a rule and let
 * fast-check attack it with hundreds, including the empty strings, newlines and unicode
 * nobody thinks to write down.
 *
 * The seed is fixed on purpose. A random seed would move the mutation score between runs,
 * which a ratcheted floor cannot tolerate, and would turn a real failure into one nobody
 * can reproduce. To explore more, raise numRuns or change the seed deliberately — a failure
 * prints the counterexample and the seed that found it.
 */
fc.configureGlobal({ seed: 20260914, numRuns: 200 });

const logLevel = fc.constantFrom('debug', 'info', 'warn', 'error' as const);

/** Arbitrary caller fields, including keys that collide with the schema's own. */
const logFields = fc
  .dictionary(fc.string(), fc.jsonValue())
  .map((extra) => ({ ...extra, event: 'generated.event' }) as LogFields);

describe('a log line is always one parseable line', () => {
  it('never emits a raw newline, whatever the caller puts in the fields', () => {
    // The log schema is one JSON object per line. A field carrying a newline would split
    // one event into two half-events, and every downstream query would quietly disagree
    // with reality.
    fc.assert(
      fc.property(logLevel, fc.string(), logFields, (level, version, fields) => {
        expect(formatLine(level, version, fields)).not.toContain('\n');
      }),
    );
  });

  it('always parses back to an object carrying the schema keys', () => {
    fc.assert(
      fc.property(logLevel, fc.string(), logFields, (level, version, fields) => {
        const entry = JSON.parse(formatLine(level, version, fields));

        expect(entry.level).toBe(level);
        expect(entry.projectVersion).toBe(version);
        expect(typeof entry.ts).toBe('string');
      }),
    );
  });

  it('lets the schema win over any caller field of the same name', () => {
    // Asserted against fields deliberately generated to collide.
    fc.assert(
      fc.property(logLevel, fc.jsonValue(), fc.jsonValue(), (level, spoofed, spoofedTs) => {
        const entry = JSON.parse(
          formatLine(level, 'v1.0.0', {
            event: 'e',
            level: spoofed,
            projectVersion: spoofed,
            ts: spoofedTs,
          } as LogFields),
        );

        expect(entry.level).toBe(level);
        expect(entry.projectVersion).toBe('v1.0.0');
      }),
    );
  });

  it('routes warn and error to stderr and everything else to stdout', () => {
    fc.assert(
      fc.property(logLevel, logFields, (level, fields) => {
        const out: unknown[] = [];
        const err: unknown[] = [];
        const realLog = console.log;
        const realError = console.error;
        console.log = (line: unknown) => out.push(line);
        console.error = (line: unknown) => err.push(line);
        try {
          // 'debug' as the minimum on purpose: this property is about ROUTING, so every
          // level has to actually reach a stream. Filtering is the property below.
          createLogger('v1.0.0', 'debug')[level](fields);
        } finally {
          console.log = realLog;
          console.error = realError;
        }

        const toStderr = level === 'warn' || level === 'error';
        expect(err).toHaveLength(toStderr ? 1 : 0);
        expect(out).toHaveLength(toStderr ? 0 : 1);
      }),
    );
  });

  it('emits a level if and only if it is at or above the minimum', () => {
    // Stated as a rule over every (minimum, level) pair rather than the four cases someone
    // thinks to write down. The failure this guards is a comparison that works for the
    // pair you tested and inverts for one you did not.
    const order: LogLevel[] = ['debug', 'info', 'warn', 'error'];
    fc.assert(
      fc.property(logLevel, logLevel, logFields, (minLevel, level, fields) => {
        const lines: unknown[] = [];
        const realLog = console.log;
        const realError = console.error;
        console.log = (line: unknown) => lines.push(line);
        console.error = (line: unknown) => lines.push(line);
        try {
          createLogger('v1.0.0', minLevel)[level](fields);
        } finally {
          console.log = realLog;
          console.error = realError;
        }

        const shouldEmit = order.indexOf(level) >= order.indexOf(minLevel);
        expect(lines).toHaveLength(shouldEmit ? 1 : 0);
      }),
    );
  });
});

describe('every response carries the security headers', () => {
  // 204, 205 and 304 are excluded because the Response constructor refuses a body with
  // them, not because the middleware mishandles them — the null-body case is asserted
  // explicitly below.
  const statusCode = fc
    .integer({ min: 200, max: 599 })
    .filter((status) => ![204, 205, 304].includes(status));

  it('sets all five headers whatever the response was', () => {
    fc.assert(
      fc.property(fc.string(), statusCode, (body, status) => {
        const headers = withSecurityHeaders(new Response(body, { status })).headers;

        for (const name of [
          'strict-transport-security',
          'content-security-policy',
          'x-content-type-options',
          'referrer-policy',
          'x-frame-options',
        ]) {
          expect(headers.get(name)).toBeTruthy();
        }
      }),
    );
  });

  it('preserves the status of the response it wraps', () => {
    fc.assert(
      fc.property(fc.string(), statusCode, (body, status) => {
        expect(withSecurityHeaders(new Response(body, { status })).status).toBe(status);
      }),
    );
  });

  it('applies them to a bodyless response too', () => {
    const response = withSecurityHeaders(new Response(null, { status: 204 }));

    expect(response.status).toBe(204);
    expect(response.headers.get('x-frame-options')).toBe('DENY');
  });

  it('overrides a weaker header the handler already set', () => {
    // A route that sets its own permissive CSP must not be able to opt out of the default.
    fc.assert(
      fc.property(fc.string({ minLength: 1 }), (weak) => {
        const response = withSecurityHeaders(
          new Response('ok', { headers: { 'content-security-policy': weak } }),
        );

        expect(response.headers.get('content-security-policy')).toBe(
          "default-src 'self'; frame-ancestors 'none'",
        );
      }),
    );
  });
});

describe('the disclosure record never serves an expired date', () => {
  it('expires in the future for any point in time', () => {
    // An expired security.txt is treated as invalid by scanners, which is the same as not
    // publishing one at all.
    fc.assert(
      // Bounded to dates a running Worker could actually see. Unbounded, fast-check finds
      // an instant within a year of the maximum representable Date, where adding a year
      // overflows and the helper throws. Unreachable while `now` defaults to new Date().
      fc.property(
        fc.date({
          min: new Date('1970-01-01T00:00:00.000Z'),
          max: new Date('2200-01-01T00:00:00.000Z'),
          noInvalidDate: true,
        }),
        fc.webUrl(),
        (now, contact) => {
          const expires = buildSecurityTxt(contact, now).match(/Expires: (.+)/)?.[1];

          expect(new Date(expires ?? '').getTime()).toBeGreaterThan(now.getTime());
        },
      ),
    );
  });

  it('always ends with a newline and names the contact it was given', () => {
    fc.assert(
      fc.property(fc.webUrl(), (contact) => {
        const txt = buildSecurityTxt(contact, new Date('2026-01-01T00:00:00.000Z'));

        expect(txt.endsWith('\n')).toBe(true);
        expect(txt).toContain(`Contact: ${contact}`);
      }),
    );
  });
});

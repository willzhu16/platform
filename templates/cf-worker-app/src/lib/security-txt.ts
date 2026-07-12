/**
 * Builds the `/.well-known/security.txt` body (spec 12 §2.2.6, RFC 9116). Served by the
 * worker rather than shipped as a static asset so `Expires` is always a live date — an
 * expired security.txt is treated as invalid by scanners, and a hard-coded date rots.
 * The contact points at the repo's GitHub private vulnerability reporting page.
 */

const ONE_YEAR_MS = 365 * 24 * 60 * 60 * 1000;

/** Render the RFC 9116 record. `now` is injectable so the expiry is testable. */
export const buildSecurityTxt = (contactUrl: string, now: Date = new Date()): string => {
  const expires = new Date(now.getTime() + ONE_YEAR_MS).toISOString();
  const lines = [`Contact: ${contactUrl}`, `Expires: ${expires}`, 'Preferred-Languages: en'];
  return `${lines.join('\n')}\n`;
};

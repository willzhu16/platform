/**
 * Server-side Cloudflare Turnstile verification (spec 12 §2.2.4). Call this on every
 * public form POST before trusting the submission. The secret is a wrangler secret
 * (TURNSTILE_SECRET), never in source — you get its name, not its value.
 */
export const verifyTurnstile = async (
  token: string,
  secret: string,
  ip?: string,
): Promise<boolean> => {
  const body = new FormData();
  body.append('secret', secret);
  body.append('response', token);
  if (ip) {
    body.append('remoteip', ip);
  }
  const response = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
    method: 'POST',
    body,
  });
  if (!response.ok) {
    // Fail closed: a siteverify outage must reject the submission, not throw mid-handler.
    return false;
  }
  const result = (await response.json()) as { success: boolean };
  return result.success === true;
};

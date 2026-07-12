# Perimeter checklist (per project)

External-facing hardening for a deployed Cloudflare app (spec 12 §2.2–2.3). Run this
**once per project at its first deploy**; the account-level pieces move into OpenTofu when
IaC exists (D-08). Everything here is **free tier** (D-15) and identity-based rather than
IP-based (D-27) — a solo dev gets "only trusted parties reach sensitive surfaces" from
Cloudflare Access, not from allowlisting IPs that don't stay stable.

Non-goals: compliance frameworks, WAF tuning beyond the free managed rules, anything on a
paid plan. Internal security (secret scanning, dependency policy) is specs 02/06.

## What the template already ships

These land in every `cf-worker-app` at generation — verify they survived, don't rebuild:

- [ ] **Security headers** on every response — `src/middleware/security-headers.ts`
      (HSTS, `default-src 'self'` CSP, `frame-ancestors 'none'`, `X-Content-Type-Options`,
      `Referrer-Policy`). Tighten the CSP as the app grows.
- [ ] **`/.well-known/security.txt`** served by the worker (RFC 9116) — points reporters at
      the repo's GitHub private vulnerability reporting page. Confirm it resolves.
- [ ] **Turnstile** verify helper (`src/lib/turnstile.ts`) — present when the project was
      generated with `public_forms`. Wire `verifyTurnstile` into every public form POST and
      add the widget to the form; it fails closed on a siteverify outage.

## Cloudflare dashboard — deployed app (§2.2)

Applied per zone once the app has a custom domain (workers.dev needs only steps 1–2):

- [ ] **DNS proxied** (orange cloud) on every record — the origin is never exposed.
- [ ] **Bot Fight Mode: on**; **Security level: medium**; **Browser integrity check: on**.
- [ ] **WAF free managed rules: on.** Add two custom rules per app:
  - [ ] Rate-limit the auth / expensive endpoints (login, signup, anything that hits a
        binding hard).
  - [ ] Block requests to `/admin*` (and similar privileged paths) that lack a Cloudflare
        Access JWT — belt to the Access suspenders in §2.3.
- [ ] **Turnstile** enabled on every public form (signup, login, contact) — the site key is
      public, the secret is a `wrangler secret` (`TURNSTILE_SECRET`, per spec 06 store rules).

## Cloudflare Access — admin / non-public surfaces (§2.3)

Cloudflare Access (Zero Trust free, ≤50 users) is the "only certain people" control (D-27),
replacing IP allowlisting. Put it in front of any admin route, internal tool, staging-like
environment, and — per project choice — preview URLs.

- [ ] Create the Access application (out-of-band, one-time — see §5 of the spec).
- [ ] Policy: **GitHub SSO, your account only**. Session **24h**.
- [ ] Verify: `/admin` from a clean browser returns the Access login wall; it passes with
      your GitHub identity and 404/200s as normal after auth.

An attacker without your GitHub identity gets a login wall, not an open port — and it works
from any machine you own, anywhere.

## Accounts (do this before anything else — §2.1)

Account takeover defeats every control below it, so the account sweep is the root task. It is
**out-of-band** (human, ~30 min) and lives in the spec, not automatable here:

- [ ] Passkey as primary 2FA on GitHub + Cloudflare + Bitwarden; TOTP fallback; **SMS removed**.
- [ ] Recovery codes exported to a Bitwarden secure note + one offline copy; tested once.
- [ ] Quarterly cadence reviews active sessions / devices / OAuth apps and revokes unknowns
      same-day (handbook/cadences.md → quarterly).
- Hardware key: deferred to the first project with real users (D-26).

## Public repos — hostile-contributor hardening (§2.4)

- [ ] GitHub Actions: **require approval for first-time contributors** (account-wide default).
- [ ] Workflow `permissions:` minimal everywhere (spec 01 already mandates). **Never** weaken
      a fork PR with `pull_request_target` + PR-code checkout — fork PRs get no secrets by
      GitHub default; keep it that way (zizmor rule enforces, spec 09 / P2).
- [ ] Private vulnerability reporting + Dependabot alerts enabled (bootstrap step, spec 03 §5).
- SSH commit signing + vigilant mode on your machines: low-effort, P2 (spec 12 §2.4).

## Related, tracked elsewhere

- **Domain hygiene** (DNSSEC, CAA, SPF/DKIM/DMARC): [`domain-checklist.md`](domain-checklist.md),
  dormant until the first domain purchase (D-15 hatch 1).
- **Canary tokens** (planted tripwires, P2): spec 12 §2.4b — cheapest intrusion detection a
  solo dev can own; land with Phase 2.

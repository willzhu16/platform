#!/usr/bin/env bash
# Smoke-check a deployed Worker: scripts/smoke.sh https://example.workers.dev
#
# The unit tests prove the code is right. This proves the deployment is: routes reachable,
# security headers actually arriving at a client, the disclosure record live and unexpired.
# Those are the things a green test suite cannot tell you, because they depend on
# wrangler.jsonc, routes, and whatever sits in front of the Worker — none of which the tests
# see.
#
# Deliberately small and dependency-free (curl + jq, both already used by the release
# workflow). It is a smoke test, not an end-to-end suite: it answers "is this deployment
# broken in an obvious way", quickly, on every preview and every release.
#
# Assertions are limited to contracts the template guarantees for every project built on it.
# Add project-specific checks below the marked section rather than replacing these.

set -euo pipefail

BASE="${1:-}"
if [ -z "$BASE" ]; then
  echo "usage: scripts/smoke.sh <base-url>" >&2
  exit 2
fi
BASE="${BASE%/}"

failures=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1" >&2; failures=$((failures + 1)); }

echo "Smoke: ${BASE}"

# --- liveness -----------------------------------------------------------------------
health="$(curl -fsS --max-time 10 "${BASE}/healthz" || true)"
version="$(printf '%s' "$health" | jq -r '.version // empty' 2>/dev/null || true)"
if [ -n "$version" ]; then
  pass "/healthz reports version ${version}"
else
  fail "/healthz did not return a JSON body with a version (got: ${health:-no response})"
fi

# --- security headers ---------------------------------------------------------------
# Checked on two paths, because middleware applied to one route and not another is exactly
# the mistake that looks fine in a unit test of the middleware itself.
for path in "/healthz" "/"; do
  headers="$(curl -fsS -D - -o /dev/null --max-time 10 "${BASE}${path}" || true)"
  if [ -z "$headers" ]; then
    fail "no response from ${path}"
    continue
  fi
  missing=''
  for header in \
    'strict-transport-security' \
    'content-security-policy' \
    'x-content-type-options' \
    'referrer-policy' \
    'x-frame-options'
  do
    if ! printf '%s' "$headers" | tr 'A-Z' 'a-z' | grep -q "^${header}:"; then
      missing="${missing}${missing:+, }${header}"
    fi
  done
  if [ -z "$missing" ]; then
    pass "${path} carries all five security headers"
  else
    fail "${path} is missing: ${missing}"
  fi
done

# --- disclosure record ---------------------------------------------------------------
# An expired security.txt is treated as invalid by scanners, which is the same as not
# publishing one — and it expires on a wall clock, so only a live check can catch it.
txt="$(curl -fsS --max-time 10 "${BASE}/.well-known/security.txt" || true)"
if printf '%s' "$txt" | grep -q '^Contact:'; then
  expires="$(printf '%s' "$txt" | sed -n 's/^Expires: //p' | head -1)"
  if [ -n "$expires" ] && [ "$(date -u -d "$expires" +%s 2>/dev/null || echo 0)" -gt "$(date -u +%s)" ]; then
    pass "/.well-known/security.txt is live and expires ${expires}"
  else
    fail "/.well-known/security.txt has no future Expires (got: ${expires:-none})"
  fi
else
  fail "/.well-known/security.txt did not return a Contact line"
fi

# --- project-specific checks ----------------------------------------------------------
# Add yours here. Keep them fast and keep them about the deployment, not the logic — logic
# belongs in tests/, where a failure is cheaper to diagnose than a red release.

if [ "$failures" -gt 0 ]; then
  echo "smoke FAILED: ${failures} check(s)" >&2
  exit 1
fi
echo "smoke OK"

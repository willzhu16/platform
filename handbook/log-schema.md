# Log schema

**Frozen contract.** One JSON object per line (JSONL). Implemented by the templates'
`src/lib/log.ts` (spec 03) and enforced by [`log-schema.json`](log-schema.json), which
spec 08 uses in a test. `event` is the primary query key — make it a stable, greppable
`snake_case` verb phrase, never a free-text sentence.

## Fields

| Field | Required | Type | Notes |
|---|---|---|---|
| `ts` | ✅ | string | ISO 8601, UTC (`2026-07-07T14:03:11.204Z`) |
| `level` | ✅ | enum | `debug` \| `info` \| `warn` \| `error` |
| `event` | ✅ | string | `snake_case` verb phrase, e.g. `request_handled` |
| `projectVersion` | ✅ | string | the release tag (spec 07), or `dev` locally |
| `requestId` | | string | correlates all lines of one request |
| `route` | | string | request path, no query string |
| `durationMs` | | number | wall-clock for the unit of work |
| `userId` | | string | **opaque id only, never PII** (no email/name) |
| `err` | | object | `{ message, stack?, code? }` |

Extra fields are allowed (the object is open) — but keep them queryable and cheap.

## Never log

- Secrets, tokens, or credentials in any field.
- Request/response bodies of **auth or billing** routes.
- Full request payloads (log the shape or the ids, not the contents).

`debug` is for local development. It is **filtered at runtime, not stripped at build time**:
a logger drops anything below its minimum level, and the minimum defaults to `info`, so a
`debug` call that ships still emits nothing until a deployment sets `LOG_LEVEL=debug`. The
earlier wording here promised build-time stripping that no part of the pipeline performed —
wrangler bundles with esbuild, which does not remove a call by log level.

`warn` and `error` go to stderr; `info`/`debug` to stdout.

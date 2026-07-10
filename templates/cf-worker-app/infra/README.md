# infra/

What is managed where (D-08):

- **`wrangler.jsonc`** (repo root) is the IaC for this project's own Cloudflare resources:
  the Worker, its bindings (KV/D1/R2/queues), routes, and per-environment config. It is
  already declarative — do not wrap it in another tool.
- **OpenTofu** (`infra/tofu/`, added only when needed) covers what wrangler cannot:
  account-level DNS, Cloudflare Access policies, R2 bucket policies, zone settings. State
  lives in R2 with OpenTofu native state encryption.

Until this project needs account-level infra, `wrangler.jsonc` is the whole story and this
directory holds only this note.

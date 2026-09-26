# secrets/

Versioned machine config, **encrypted with SOPS + age** before commit.

Configure the recipient once before the first value lands here. From a `platform` checkout:

```bash
bash scripts/sops-bootstrap.sh <path to this repo>
```

That generates a key for this project, writes the public half into `.sops.yaml`, and checks
that `sops` can actually encrypt with it. Pass `--recipient age1...` instead to reuse a key
you already hold. The private half is written outside the repo and never printed; move it
into your credential manager and delete the file.

## Convention

- One file per environment: `secrets/<env>.env` (e.g. `secrets/dev.env`, `secrets/preview.env`).
- Always encrypt in place before committing: `sops -e -i secrets/dev.env`.
- Load locally without decrypting to disk: `sops exec-env secrets/dev.env 'pnpm dev'`.

## Rules

- This store holds **non-production** machine config only. Production deploy credentials
  live in GitHub Environment secrets; runtime third-party keys live in `wrangler secret`.
- Never commit an unencrypted file here. The `security / gitleaks` job fails any file in
  this directory that is not SOPS output, so this is enforced rather than asked for. Note
  what that gate does and does not do: it checks whether a file is *encrypted*, not whether
  its contents look secret. gitleaks itself matches known credential shapes, so it catches a
  Cloudflare token or an age key anywhere in the repo, and misses a database URL or an
  internal hostname. The two cover different halves of the problem.
- Agents must not read or write under `secrets/`. T1 denies direct file-tool access;
  approved scripts still require an isolated environment to enforce that boundary.

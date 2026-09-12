# secrets/

Versioned machine config, **encrypted with SOPS + age** before commit. Configure the
public recipient in `.sops.yaml` first; store its private key in your credential manager,
outside agent environments. Inspect the encrypted output before publishing it.

## Convention

- One file per environment: `secrets/<env>.env` (e.g. `secrets/dev.env`, `secrets/preview.env`).
- Always encrypt in place before committing: `sops -e -i secrets/dev.env`.
- Load locally without decrypting to disk: `sops exec-env secrets/dev.env 'pnpm dev'`.

## Rules

- This store holds **non-production** machine config only. Production deploy credentials
  live in GitHub Environment secrets; runtime third-party keys live in `wrangler secret`.
- Never commit an unencrypted file here — the `security / gitleaks` gate is the backstop.
- Agents must not read or write under `secrets/`. T1 denies direct file-tool access;
  approved scripts still require an isolated environment to enforce that boundary.

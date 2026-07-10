# secrets/

Versioned machine config, **encrypted with SOPS + age** before commit (spec 06). Safe in
a public repo because the values are encrypted; the age private key lives only in Bitwarden
and on active dev machines.

## Convention

- One file per environment: `secrets/<env>.env` (e.g. `secrets/dev.env`, `secrets/preview.env`).
- Always encrypt in place before committing: `sops -e -i secrets/dev.env`.
- Load locally without decrypting to disk: `sops exec-env secrets/dev.env 'pnpm dev'`.

## Rules

- This store holds **non-production** machine config only. Production deploy credentials
  live in GitHub Environment secrets; runtime third-party keys live in `wrangler secret`.
- Never commit an unencrypted file here — the `security / gitleaks` gate is the backstop.
- Agents never read or write under `secrets/` (denied in the T1 permission profile).

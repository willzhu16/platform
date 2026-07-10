#!/usr/bin/env bash
# setup-machine — bring a fresh WSL2 (Ubuntu) environment to "productive" (spec 03 §5b,
# D-20 portability path). Idempotent: every install is guarded by a `command -v` check, so
# re-running only fills gaps. Ends with a self-check table (tool → version → ✔/✘).
#
# Acceptance: fresh WSL2 → clone/test/deploy-to-preview a project in ≤30 min, with only
# Bitwarden access (which holds the age key) as external input.
#
# Optional overrides: GIT_USER_NAME, GIT_USER_EMAIL (set git identity non-interactively).
set -euo pipefail

ok()   { printf '  \033[32m✔\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
step() { printf '\n\033[1m%s\033[0m\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

grep -qi microsoft /proc/version 2>/dev/null || warn 'not detected as WSL2 — this script targets Ubuntu/WSL2 (D-20)'

# ---- 1. OS packages (apt): git, curl, age, gitleaks -----------------------
step '1. Base OS packages'
if have apt-get; then
  sudo apt-get update -qq
  for pkg in git curl age gitleaks; do
    have "$pkg" || sudo apt-get install -y -qq "$pkg" || warn "apt could not install $pkg (install manually)"
  done
  ok 'git, curl, age, gitleaks'
else
  warn 'apt-get not found — install git, curl, age, gitleaks with your package manager'
fi

# ---- 2. mise → Node LTS + Python ------------------------------------------
step '2. Runtime manager (mise) + Node LTS + Python'
if ! have mise; then
  curl -fsSL https://mise.run | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
if have mise; then
  mise use -g node@lts >/dev/null
  mise use -g python@3.13 >/dev/null
  # Activate mise for future shells (idempotent append).
  grep -q 'mise activate bash' "$HOME/.bashrc" 2>/dev/null \
    || echo 'eval "$(mise activate bash)"' >> "$HOME/.bashrc"
  eval "$(mise activate bash)"
  ok 'mise + Node LTS + Python 3.13'
else
  warn 'mise install failed — see https://mise.jdx.dev'
fi

# ---- 3. pnpm (via corepack) ------------------------------------------------
step '3. pnpm'
if have corepack; then corepack enable >/dev/null 2>&1 || true; fi
have pnpm || (have npm && npm install -g pnpm >/dev/null 2>&1) || warn 'install pnpm: https://pnpm.io/installation'
have pnpm && ok "pnpm $(pnpm --version)"

# ---- 4. uv (Python packaging) + copier -------------------------------------
step '4. uv + copier'
if ! have uv; then curl -fsSL https://astral.sh/uv/install.sh | sh; export PATH="$HOME/.local/bin:$PATH"; fi
have uv && ok "uv $(uv --version | awk '{print $2}')"
# copier as an isolated uv tool so it is not pinned to any one project's venv.
have copier || (have uv && uv tool install copier >/dev/null 2>&1) || warn 'install copier: uv tool install copier'
have copier && ok "copier $(copier --version | awk '{print $NF}')"

# ---- 5. sops -----------------------------------------------------------------
step '5. sops'
if ! have sops; then
  # Pinned release path — the `latest/download/` form 404s once a newer sops ships,
  # because the versioned asset name no longer exists in the latest release.
  SOPS_VERSION='3.9.4'
  SOPS_URL="https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.amd64"
  sudo curl -fsSL "$SOPS_URL" -o /usr/local/bin/sops && sudo chmod +x /usr/local/bin/sops \
    || warn 'sops install failed — download from https://github.com/getsops/sops/releases'
fi
have sops && ok "sops $(sops --version | awk '{print $2}')"

# ---- 6. gh CLI + wrangler --------------------------------------------------
step '6. gh CLI + wrangler'
have gh || warn 'gh not installed — https://github.com/cli/cli#installation'
have gh && ok "gh $(gh --version | head -1 | awk '{print $3}')"
have wrangler || (have pnpm && pnpm add -g wrangler >/dev/null 2>&1) || warn 'install wrangler: pnpm add -g wrangler'
have wrangler && ok "wrangler $(wrangler --version 2>/dev/null | tail -1)"

# ---- 7. git identity + SSH commit signing (spec 12) ------------------------
step '7. git configuration'
if [ -z "$(git config --global user.name || true)" ]; then
  if [ -n "${GIT_USER_NAME:-}" ]; then git config --global user.name "$GIT_USER_NAME"; ok 'git user.name set'
  else warn 'git user.name unset — run: git config --global user.name "Your Name" (or set GIT_USER_NAME)'; fi
else ok "git user.name = $(git config --global user.name)"; fi
if [ -z "$(git config --global user.email || true)" ]; then
  if [ -n "${GIT_USER_EMAIL:-}" ]; then git config --global user.email "$GIT_USER_EMAIL"; ok 'git user.email set'
  else warn 'git user.email unset — run: git config --global user.email you@example.com (or set GIT_USER_EMAIL)'; fi
else ok "git user.email = $(git config --global user.email)"; fi
# SSH commit signing is opt-in (spec 12); wire it only if an SSH key is present.
if [ -f "$HOME/.ssh/id_ed25519.pub" ] && [ "$(git config --global gpg.format || true)" != 'ssh' ]; then
  warn 'SSH key found — to enable signing (spec 12): git config --global gpg.format ssh && \'
  warn '  git config --global user.signingkey ~/.ssh/id_ed25519.pub && git config --global commit.gpgsign true'
fi

# ---- 8. age key check (lives in Bitwarden, spec 06) ------------------------
step '8. age key (SOPS decryption)'
if [ -f "$HOME/.config/sops/age/keys.txt" ]; then
  ok 'age key present at ~/.config/sops/age/keys.txt'
else
  warn 'age key MISSING — restore ~/.config/sops/age/keys.txt from the Bitwarden "SOPS age key" note'
  warn '(without it you cannot decrypt any secrets/*.env)'
fi

# ---- 9. gh auth ------------------------------------------------------------
step '9. GitHub authentication'
if have gh && gh auth status >/dev/null 2>&1; then
  ok 'gh authenticated'
  gh auth setup-git >/dev/null 2>&1 && ok 'git credential helper wired to gh'
else
  warn 'not authenticated — run: gh auth login  (then re-run for the credential-helper step)'
fi

# ---- Self-check table ------------------------------------------------------
step 'Self-check'
printf '  %-10s %-12s %s\n' TOOL VERSION STATUS
for tool in git mise node pnpm python uv copier sops age gitleaks gh wrangler; do
  if have "$tool"; then
    ver="$("$tool" --version 2>/dev/null | head -1 | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)"
    printf '  %-10s %-12s \033[32m✔\033[0m\n' "$tool" "${ver:-?}"
  else
    printf '  %-10s %-12s \033[31m✘\033[0m\n' "$tool" '-'
  fi
done
printf '\nRestart your shell (or `source ~/.bashrc`) so mise + PATH changes take effect.\n'

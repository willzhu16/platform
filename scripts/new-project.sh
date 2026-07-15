#!/usr/bin/env bash
# new-project — scaffold an Artemis project that passes every gate on its first PR
# (spec 03 §5). Bash-first per D-20; a thin new-project.ps1 wrapper invokes this under WSL2.
#
# Usage:
#   new-project <name> --template <cf-worker-app|py-tool> --visibility <public|private> \
#     [--description "<text>"] [--bindings kv,d1,r2,queues] [--scheduled-jobs] [--public-forms]
#
# Idempotent: each step prints ✔/✘ and re-running on an existing project is a no-op
# (acceptance test 7). Any failure stops and prints remediation.
#
# Env overrides (for testing): PLATFORM_SRC (copier source, default gh:willzhu16/platform).
set -euo pipefail

OWNER='willzhu16'
PLATFORM_REPO="${OWNER}/platform"
PLATFORM_SRC="${PLATFORM_SRC:-gh:${PLATFORM_REPO}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(dirname "${SCRIPT_DIR}")"

ok()   { printf '  \033[32m✔\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✘\033[0m %s\n' "$1" >&2; [ -n "${2:-}" ] && printf '    → %s\n' "$2" >&2; exit 1; }
step() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# ---- Parse arguments -------------------------------------------------------
NAME='' TEMPLATE='' VISIBILITY='' DESCRIPTION='' BINDINGS='' SCHEDULED='false' PUBLIC_FORMS='false'
while [ $# -gt 0 ]; do
  case "$1" in
    --template)      TEMPLATE="$2"; shift 2 ;;
    --visibility)    VISIBILITY="$2"; shift 2 ;;
    --description)   DESCRIPTION="$2"; shift 2 ;;
    --bindings)      BINDINGS="$2"; shift 2 ;;
    --scheduled-jobs) SCHEDULED='true'; shift ;;
    --public-forms)  PUBLIC_FORMS='true'; shift ;;
    -*)              fail "unknown flag: $1" "see the usage header in $0" ;;
    *)               [ -z "$NAME" ] && NAME="$1" || fail "unexpected argument: $1"; shift ;;
  esac
done

[ -n "$NAME" ]       || fail 'project name is required' 'new-project <name> --template <t> --visibility <v>'
[ -n "$TEMPLATE" ]   || fail '--template is required (cf-worker-app | py-tool)'
[ -n "$VISIBILITY" ] || fail '--visibility is required (public | private)'
case "$VISIBILITY" in public|private) ;; *) fail "--visibility must be public or private, got: $VISIBILITY" ;; esac
case "$TEMPLATE" in cf-worker-app|py-tool) ;; *) fail "unknown template: $TEMPLATE" ;; esac
[[ "$NAME" =~ ^[a-z][a-z0-9-]*$ ]] || fail "name must be a lowercase slug: $NAME"
[ -n "$DESCRIPTION" ] || DESCRIPTION="A ${TEMPLATE} project."

# ---- 1. Preflight ----------------------------------------------------------
step '1. Preflight'
command -v gh >/dev/null      || fail 'gh CLI not found' 'run platform/scripts/setup-machine.sh'
command -v copier >/dev/null  || fail 'copier not found' 'run platform/scripts/setup-machine.sh'
command -v git >/dev/null     || fail 'git not found'
command -v jq >/dev/null      || fail 'jq not found' 'run platform/scripts/setup-machine.sh'
gh auth status >/dev/null 2>&1 || fail 'gh not authenticated' 'run: gh auth login'
if [ "$TEMPLATE" = 'cf-worker-app' ]; then
  command -v pnpm >/dev/null || fail 'pnpm not found (needed to generate the lockfile)' 'run setup-machine.sh'
else
  command -v uv >/dev/null   || fail 'uv not found (needed to generate the lockfile)' 'run setup-machine.sh'
fi
grep -qi microsoft /proc/version 2>/dev/null || printf '  \033[33m!\033[0m not in WSL2 — Linux is the canonical env (D-20); continuing\n'
ok 'toolchain present and gh authenticated'

# ---- 2. Scaffold from the template (copier) --------------------------------
step '2. Scaffold from template'
if [ -d "$NAME" ]; then
  ok "$NAME/ already exists — skipping copier (idempotent)"
else
  DATA_FILE="$(mktemp)"
  trap 'rm -f "$DATA_FILE"' EXIT
  # DESCRIPTION and BINDINGS are free text (unlike NAME/TEMPLATE/VISIBILITY, which are
  # validated above), so they go through jq rather than bare interpolation: a description
  # containing ": " is not a valid YAML plain scalar, and a newline would inject a second
  # answer key. jq emits a JSON string/array, which is valid YAML.
  {
    echo "template: ${TEMPLATE}"
    echo "project_name: ${NAME}"
    echo "description: $(jq -n --arg d "$DESCRIPTION" '$d')"
    echo "visibility: ${VISIBILITY}"
    if [ "$TEMPLATE" = 'cf-worker-app' ]; then
      echo "needs_scheduled_jobs: ${SCHEDULED}"
      echo "public_forms: ${PUBLIC_FORMS}"
      echo "bindings: $(jq -cn --arg b "$BINDINGS" '$b | split(",") | map(select(length > 0))')"
    fi
  } > "$DATA_FILE"
  copier copy --defaults --data-file "$DATA_FILE" "$PLATFORM_SRC" "$NAME" \
    || fail 'copier generation failed' 'check the template answers above'
  ok "generated ./$NAME from $TEMPLATE"
fi

cd "$NAME"

# ---- 3. Generate the lockfile (CI installs are --frozen; no lock = red first PR) --
step '3. Generate lockfile'
if [ "$TEMPLATE" = 'cf-worker-app' ]; then
  if [ -f pnpm-lock.yaml ]; then ok 'pnpm-lock.yaml present'; else
    pnpm install --lockfile-only >/dev/null || fail 'pnpm lockfile generation failed'
    ok 'pnpm-lock.yaml created'
  fi
else
  if [ -f uv.lock ]; then ok 'uv.lock present'; else
    uv lock >/dev/null || fail 'uv lock failed'
    ok 'uv.lock created'
  fi
fi

# ---- 4. git init + initial commit ------------------------------------------
step '4. Initialize git'
if [ -d .git ]; then
  ok 'git already initialized — skipping'
else
  PLATFORM_VERSION="$(gh api "repos/${PLATFORM_REPO}/releases/latest" --jq .tag_name 2>/dev/null || echo v1)"
  git init -q -b main
  git add -A
  git commit -q -m "chore: bootstrap from ${TEMPLATE} (platform ${PLATFORM_VERSION})"
  ok "initial commit (platform ${PLATFORM_VERSION})"
fi

# ---- 5. Create the GitHub repo + push --------------------------------------
step '5. Create GitHub repo'
if gh repo view "${OWNER}/${NAME}" >/dev/null 2>&1; then
  ok "${OWNER}/${NAME} already exists — skipping create"
else
  gh repo create "${OWNER}/${NAME}" "--${VISIBILITY}" --description "$DESCRIPTION" --source . --push \
    || fail 'gh repo create failed'
  ok "created ${OWNER}/${NAME} (${VISIBILITY}) and pushed main"
fi
# Allow workflows to open PRs — off by default on new repos, and athena-sync's weekly
# drift PR needs it (found live by the canary drill). Outside the guard: idempotent.
gh api -X PUT "repos/${OWNER}/${NAME}/actions/permissions/workflow" \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true >/dev/null \
  || fail 'setting Actions workflow permissions failed'
ok 'Actions may create PRs (athena-sync drift PRs)'

# ---- 6. Apply the main ruleset ---------------------------------------------
step '6. Apply main ruleset'
if gh api "repos/${OWNER}/${NAME}/rulesets" --jq '.[].name' 2>/dev/null | grep -qx main; then
  ok 'ruleset "main" already present — skipping'
else
  RULESET="$(cat "${PLATFORM_ROOT}/rulesets/main.json")"
  if [ "$VISIBILITY" = 'public' ]; then
    # CodeQL is free/public-only (D-12); its check is required only on public repos.
    RULESET="$(jq '(.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks)
                   += [{"context": "codeql / analyze"}]' <<<"$RULESET")"
  fi
  echo "$RULESET" | gh api --method POST "repos/${OWNER}/${NAME}/rulesets" --input - >/dev/null \
    || fail 'ruleset creation failed'
  ok "ruleset applied ($([ "$VISIBILITY" = public ] && echo 8 || echo 7) required checks, linear history, no force-push)"
fi

# ---- 7. Environments (deploy targets only) ---------------------------------
step '7. Deployment environments'
DEPLOYS="$(jq '.targets | length' .athena/config.json 2>/dev/null || echo 0)"
if [ "$DEPLOYS" -gt 0 ]; then
  gh api --method PUT "repos/${OWNER}/${NAME}/environments/preview" >/dev/null
  # -F (typed), not -f: the API rejects the strings "true"/"false" for these booleans.
  gh api --method PUT "repos/${OWNER}/${NAME}/environments/production" \
    -F 'deployment_branch_policy[protected_branches]=false' \
    -F 'deployment_branch_policy[custom_branch_policies]=true' >/dev/null
  gh api --method POST "repos/${OWNER}/${NAME}/environments/production/deployment-branch-policies" \
    -f name='v*' -f type='tag' >/dev/null 2>&1 || true
  ok 'preview + production environments (production gated to v* tags, spec 07)'
else
  ok 'non-deployable template — no environments needed'
fi

# ---- 8. Renovate -----------------------------------------------------------
step '8. Renovate'
if [ -f renovate.json ]; then
  ok 'renovate.json present (extends the platform preset); the app auto-onboards the repo'
else
  fail 'renovate.json missing from the generated project' 'template bug — file an issue on platform'
fi

# ---- 9. Compile AI instruction files (athena) ------------------------------
step '9. Compile AI instructions (athena)'
if command -v athena >/dev/null; then
  athena compile || fail 'athena compile failed'
  if [ -n "$(git status --porcelain)" ]; then
    git add -A && git commit -q -m 'chore: compile AI instruction files' && git push -q \
      || fail 'committing compiled files failed'
    ok 'CLAUDE.md / AGENTS.md / .claude/settings.json compiled and pushed'
  else
    ok 'compiled files already up to date — nothing to commit (idempotent)'
  fi
else
  printf '  \033[33m!\033[0m athena CLI not found — run `athena compile` and commit before the first PR\n'
fi

# ---- 10. Human checklist (§7 out-of-band steps) ----------------------------
step 'Done — human checklist (steps that cannot be scripted)'
cat <<EOF
  1. Fill .athena/project.md (10 min: what this is, its non-obvious constraints)
     and the top of THREAT.md.
EOF
if [ "$DEPLOYS" -gt 0 ]; then
  cat <<EOF
  2. Create a project-scoped Cloudflare API token (spec 06 how-to) and add it as the
     GitHub environment secret CLOUDFLARE_API_TOKEN on 'production' (and 'preview').
  3. Once the first deploy exists, add the public URL to the Upptime config (spec 08).
EOF
fi
printf '\n  Repo: https://github.com/%s/%s\n' "$OWNER" "$NAME"

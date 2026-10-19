#!/usr/bin/env bash
# Fail when a file under secrets/ is not SOPS-encrypted.
#
#   bash scripts/sops-check.sh [repo-dir]
#
# secrets/README.md used to promise that `security / gitleaks` was the backstop against
# committing an unencrypted secret. It is not one. gitleaks matches known credential shapes,
# so a database URL, an internal hostname, a customer identifier or a bespoke API key walks
# straight past it. That promise was withdrawn for being misleading and nothing took its place,
# which left the store with a documented convention and no enforcement at all.
#
# This is what takes its place. It asks the one question that has a right answer regardless of
# what the value looks like: is this file SOPS output, or is it not. Every sops-encrypted file
# carries the ciphertext marker below on every value it protects, in every output format, so
# the check needs no list of secret shapes and cannot be fooled by an unusual one.
#
# What passes:
#
#   - a repo with no secrets/ directory at all (most of them)
#   - a freshly generated repo whose secrets/ holds only README.md. The placeholder recipient
#     in .sops.yaml is not a problem until there is something to encrypt.
#   - README.md, .gitignore and .gitkeep inside secrets/, which are structure, not secrets
#
# Read-only, and needs nothing but bash: no sops, no age, no network. That matters because it
# runs inside the reusable security workflow for every repo in the fleet, including repos that
# have never installed either tool.
#
# Sourcing this file defines the functions and runs nothing, so tests call them directly.

set -uo pipefail

# Present on every value sops encrypts, whatever the file format. Matched literally (grep -F),
# never as a pattern: the brackets are regex metacharacters.
SOPS_CIPHERTEXT_MARKER='ENC[AES256_GCM'

# The recipient the cf-worker-app template ships. A real age public key is 62 characters of
# bech32, so this string can never collide with a configured one.
SOPS_PLACEHOLDER='age1PLACEHOLDER'

# The files under secrets/ that are required to be encrypted, one per line. Split out so the
# PASS line can say how many were examined: "every file is encrypted" reads identically whether
# it checked twelve files or none, and a rename that empties the directory should not be able
# to report success in the same words.
sops_encryptable_files() { # $1=repo dir (default .)
  local root="${1:-.}"
  local file base
  while IFS= read -r file; do
    base="${file##*/}"
    case "$base" in
      README.md | .gitignore | .gitkeep) continue ;;
    esac
    printf '%s\n' "$file"
  done < <(find "$root/secrets" -type f 2>/dev/null | sort)
}

# One line per problem on stdout, nothing at all when the store is safe to commit.
sops_findings() { # $1=repo dir (default .)
  local root="${1:-.}"
  [ -d "$root/secrets" ] || return 0

  local -a unprotected=()
  local file
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    if ! grep -qF "$SOPS_CIPHERTEXT_MARKER" "$file" 2>/dev/null; then
      unprotected+=("$file")
    fi
  done < <(sops_encryptable_files "$root")

  local relative
  for file in "${unprotected[@]:-}"; do
    [ -n "$file" ] || continue
    relative="${file#"$root"/}"
    printf 'unencrypted %s — encrypt in place before committing: sops -e -i %s\n' \
      "$relative" "$relative"
  done

  # Reported second, and only when something actually needs encrypting, so the file list leads
  # and a freshly generated repo stays quiet. An unconfigured recipient is the reason the files
  # above are still plaintext, so naming it here turns the finding into an instruction.
  if [ "${#unprotected[@]}" -gt 0 ] && [ -f "$root/.sops.yaml" ] \
    && grep -qF "$SOPS_PLACEHOLDER" "$root/.sops.yaml"; then
    printf 'unconfigured .sops.yaml — recipient is still the template placeholder, so sops -e cannot run; fix with scripts/sops-bootstrap.sh\n'
  fi
}

sops_check_main() {
  local root="${1:-.}"
  if [ ! -d "$root/secrets" ]; then
    echo 'PASS  no secrets/ directory — nothing to encrypt'
    return 0
  fi
  local findings count
  findings="$(sops_findings "$root")"
  if [ -z "$findings" ]; then
    count="$(sops_encryptable_files "$root" | grep -c . || true)"
    if [ "$count" -eq 0 ]; then
      echo 'PASS  secrets/ holds no files to encrypt'
    else
      printf 'PASS  %s file(s) under secrets/ are SOPS-encrypted\n' "$count"
    fi
    return 0
  fi
  printf '%s\n' "$findings" >&2
  return 1
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  sops_check_main "$@"
fi

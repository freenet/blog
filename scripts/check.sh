#!/usr/bin/env bash
# Pre-publish checks, also run in CI. Fails on:
#  - em-dashes in posts or templates (house style: none at all)
#  - any tracked file that looks like a signing key
#  - a hugo build error
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fail=0

if grep -rnF "—" "$ROOT/content" "$ROOT/layouts" "$ROOT/assets" "$ROOT/README.md"; then
  echo "error: em-dash found (lines above). Rewrite the sentence." >&2
  fail=1
fi

# A website key file contains a `signing_key = "<64 hex>"` line.
rc=0
git -C "$ROOT" grep -qE 'signing_key *= *"[0-9a-fA-F]{64}"' -- . ':!scripts/check.sh' || rc=$?
case "$rc" in
  0) echo "error: a tracked file contains a signing key. Remove it and treat the key as leaked." >&2; fail=1 ;;
  1) ;;
  *) echo "error: git grep failed (exit $rc); cannot check for tracked keys" >&2; fail=1 ;;
esac
if git -C "$ROOT" ls-files | grep -E '(^|/)(website-key|.*\.key)(\.toml)?$|\.env$'; then
  echo "error: key-like or .env file tracked (above)." >&2
  fail=1
fi

OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
hugo --minify --source "$ROOT" --destination "$OUT" --quiet || { echo "error: hugo build failed" >&2; fail=1; }
[ "$fail" = 0 ] && echo "check: OK"
exit "$fail"

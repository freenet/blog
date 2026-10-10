#!/usr/bin/env bash
# Build the blog and publish it to Freenet with `fdev website`.
#
#   scripts/publish.sh            publish to the production contract (from main only)
#   scripts/publish.sh --preview  publish under a throwaway key, for checking a
#                                 branch on a real node; prints a one-off URL
#
# The production contract key is derived from two committed files:
#   published-contract/website_contract.wasm  (pinned copy of fdev's built-in website contract)
#   published-contract/website.parameters     (the 32-byte ed25519 verifying key)
# Changing either one changes the key and breaks every link to the blog. This
# script refuses to publish unless both still derive published-contract/contract-id.txt.
#
# The signing key is NEVER in this repo. Its path comes from $BLOG_SIGNING_KEY,
# else BLOG_SIGNING_KEY in .env (gitignored), else the default below. The
# script fails if that path resolves inside the repo's working tree.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DEFAULT_KEY=/home/ian/code/freenet/keys/blog/website-key.toml
WASM="$ROOT/published-contract/website_contract.wasm"
PARAMS="$ROOT/published-contract/website.parameters"
ID_FILE="$ROOT/published-contract/contract-id.txt"
# fdev and the read-back must talk to the same node: the default local node on
# 7509. Clear the variables that would point fdev elsewhere. A node on another
# port is not supported; fdev will fail to connect.
NODE_HTTP=http://127.0.0.1:7509
unset MODE FREENET_NODE_URL WS_API_PORT

die() { echo "error: $*" >&2; exit 1; }

PREVIEW=0
case "${1:-}" in
  --preview) PREVIEW=1 ;;
  "") ;;
  *) die "usage: $0 [--preview]" ;;
esac

for cmd in hugo fdev git curl xxd openssl gh; do
  command -v "$cmd" >/dev/null || die "$cmd not found on PATH"
done

WORK="$(mktemp -d)"
chmod 700 "$WORK"
trap 'rm -rf "$WORK"' EXIT

EXPECTED_ID="$(tr -d '[:space:]' < "$ID_FILE")"
[ -n "$EXPECTED_ID" ] || die "$ID_FILE is empty"

# The committed WASM + parameters must still derive the committed contract key.
DERIVED_ID="$(fdev get-contract-id --code "$WASM" --parameters "$PARAMS" | tr -d '[:space:]')"
[ "$DERIVED_ID" = "$EXPECTED_ID" ] || die "published-contract/ derives $DERIVED_ID, but contract-id.txt says $EXPECTED_ID. Do not change the WASM or parameters: that re-keys the blog."
grep -qF "$EXPECTED_ID" "$ROOT/hugo.toml" || die "hugo.toml params.freenetURL does not contain $EXPECTED_ID"

if [ "$PREVIEW" = 1 ]; then
  # A fresh key gives a fresh contract that nobody else knows about, so a
  # branch can be checked on a real node without touching the production key.
  mkdir -p "$WORK/xdg"
  (umask 077; XDG_CONFIG_HOME="$WORK/xdg" fdev website init blog >/dev/null)
  # Read only the public half.
  VK_HEX="$(sed -n 's/^verifying_key = "\([0-9a-f]*\)"$/\1/p' "$WORK/xdg/freenet/website-keys/blog.toml")"
  [ "${#VK_HEX}" = 64 ] || die "could not read the preview key's verifying key (fdev key format changed?)"
  printf '%s' "$VK_HEX" | xxd -r -p > "$WORK/preview.parameters"
  TARGET_ID="$(fdev get-contract-id --code "$WASM" --parameters "$WORK/preview.parameters" | tr -d '[:space:]')"
  echo "PREVIEW publish under throwaway contract $TARGET_ID"
else
  # Publish only from an up-to-date, clean main (publish-from-main rule).
  BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
  [ "$BRANCH" = main ] || die "on branch '$BRANCH'. Production publishes run from main after merging. Use --preview to check a branch."
  [ -z "$(git -C "$ROOT" status --porcelain)" ] || die "working tree is not clean"
  git -C "$ROOT" fetch -q origin main
  HEAD_SHA="$(git -C "$ROOT" rev-parse HEAD)"
  [ "$HEAD_SHA" = "$(git -C "$ROOT" rev-parse origin/main)" ] || die "HEAD is not origin/main. Pull first."
  # CI must be green on this exact commit.
  # Status and conclusion together: a pending run has a null conclusion,
  # which must not read as "nothing to object to".
  RUNS="$(gh api "repos/freenet/blog/commits/$HEAD_SHA/check-runs?per_page=100" \
    --jq '.check_runs[] | "\(.name)=\(.status)/\(.conclusion)"')"
  grep -qx 'check=completed/success' <<<"$RUNS" || die "CI 'check' is not green on $HEAD_SHA: ${RUNS:-no check runs yet}"
  ! grep -vq '=completed/success$' <<<"$RUNS" || die "CI on $HEAD_SHA is not all green: $RUNS"

  # Resolve the key path: environment, then .env, then the default.
  KEY="${BLOG_SIGNING_KEY:-}"
  if [ -z "$KEY" ] && [ -f "$ROOT/.env" ]; then
    KEY="$(sed -n 's/^BLOG_SIGNING_KEY=//p' "$ROOT/.env" | tail -n1)"
  fi
  KEY="${KEY:-$DEFAULT_KEY}"
  [ -f "$KEY" ] || die "signing key not found at $KEY"
  KEY_REAL="$(readlink -f "$KEY")"
  case "$KEY_REAL/" in
    "$ROOT"/*) die "signing key resolves to $KEY_REAL, inside the repo. Move it out (see README)." ;;
  esac
  if git -C "$(dirname "$KEY_REAL")" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    die "signing key $KEY_REAL is inside a git working tree. Keep it outside every repo."
  fi
  PERMS="$(stat -c '%a' "$KEY_REAL")"
  case "$PERMS" in
    600|400) ;;
    *) die "signing key $KEY_REAL has mode $PERMS; expected 600" ;;
  esac

  # The key must be the one the committed parameters were made from. fdev
  # derives the public key from the signing_key line (it ignores the stored
  # verifying_key), so derive it the same way here: an Ed25519 PKCS#8 DER
  # prefix + the 32-byte seed, through openssl. The seed goes through a pipe
  # only (printf is a builtin, so it never appears in a process list) and is
  # never printed.
  SK_HEX="$(sed -n 's/^signing_key = "\([0-9a-f]\{64\}\)"$/\1/p' "$KEY_REAL")"
  [ "${#SK_HEX}" = 64 ] || die "could not read signing_key from $KEY_REAL"
  VK_HEX="$({ printf '302e020100300506032b657004220420'; printf '%s' "$SK_HEX"; } | xxd -r -p \
    | openssl pkey -inform DER -pubout -outform DER | tail -c 32 | xxd -p -c 64)"
  [ "$VK_HEX" = "$(xxd -p -c 64 "$PARAMS")" ] || die "signing key at $KEY_REAL does not match published-contract/website.parameters"

  # fdev website reads keys from $XDG_CONFIG_HOME/freenet/website-keys/<name>.toml.
  # Point it at a private temp dir holding a symlink, so the key stays where it is.
  mkdir -p "$WORK/xdg/freenet/website-keys"
  ln -s "$KEY_REAL" "$WORK/xdg/freenet/website-keys/blog.toml"
  TARGET_ID="$EXPECTED_ID"
fi

BUILD_ID="$(git -C "$ROOT" rev-parse --short=12 HEAD)$( [ -z "$(git -C "$ROOT" status --porcelain)" ] || echo -dirty)-$(date -u +%Y%m%dT%H%M%SZ)"
echo "building $BUILD_ID"
"$ROOT/scripts/check.sh"
rm -rf "$ROOT/public"
HUGO_PARAMS_BUILDID="$BUILD_ID" hugo --minify --source "$ROOT" --destination "$ROOT/public" >/dev/null
[ -f "$ROOT/public/index.html" ] || die "hugo produced no index.html"
grep -qF "$EXPECTED_ID" "$ROOT/public/index.xml" || die "built RSS does not point at $EXPECTED_ID (check params.freenetURL and HUGO_* env vars)"

# Nothing key-like may reach public/: it becomes part of a signed, permanent
# publish. Gitignored files under content/ or static/ are invisible to git but
# Hugo still copies them, so check the build output itself.
IGNORED="$(git -C "$ROOT" ls-files -o -i --exclude-standard -- content static assets layouts)"
[ -z "$IGNORED" ] || die "gitignored files would be published: $IGNORED"
# This also refuses a post that merely discusses the key file format. That
# is deliberate: reword the post (e.g. "signing key") rather than weaken this.
rc=0; grep -rlE 'signing_key|BEGIN [A-Z ]*PRIVATE KEY' "$ROOT/public" || rc=$?
[ "$rc" = 1 ] || die "public/ contains key-like material (files above), or the scan failed (grep exit $rc)"
# The pattern goes in on stdin: grep is an external program, so an argument
# would put the seed in its process list entry for the whole scan.
if [ -n "${SK_HEX:-}" ]; then
  rc=0; printf '%s\n' "$SK_HEX" | grep -rlFf - "$ROOT/public" >/dev/null || rc=$?
  [ "$rc" = 1 ] || die "public/ contains the signing key (treat it as leaked), or the scan failed (grep exit $rc)"
fi
unset SK_HEX

echo "publishing contract $TARGET_ID"
XDG_CONFIG_HOME="$WORK/xdg" fdev website update "$ROOT/public" --key blog --contract-wasm "$WASM" | tee "$WORK/fdev.out"
grep -qF "$TARGET_ID" "$WORK/fdev.out" || die "fdev reported a different contract key than $TARGET_ID"

# Read back through the node: the served index must carry this build's id.
URL="$NODE_HTTP/v1/contract/web/$TARGET_ID/"
for _ in $(seq 1 30); do
  if curl -fsS "${URL}?__sandbox=1" 2>/dev/null | grep -qF "$BUILD_ID"; then
    echo "read-back OK: node serves build $BUILD_ID"
    echo "blog:  $URL"
    exit 0
  fi
  sleep 2
done
die "published, but $URL did not serve build $BUILD_ID within 60s. Check it in a browser before republishing. If fdev reported success, the contract may have rejected the update: it requires a version (unix seconds) above the one it holds, so a previous publish from a machine with a clock ahead of this one blocks it."

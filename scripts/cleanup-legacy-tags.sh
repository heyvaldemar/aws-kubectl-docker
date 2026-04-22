#!/usr/bin/env bash
# One-shot cleanup for legacy long-SHA (40-char hex) Docker Hub tags from the
# pre-Phase-1 CI era. Never documented as stable pins, carry accumulated CVE
# noise. Safe by default (dry-run); requires explicit "DELETE" typed
# confirmation in --execute mode.
#
# Usage:
#   ./scripts/cleanup-legacy-tags.sh [--dry-run|--execute]
#
# The PAT is read from $DOCKERHUB_PAT if set, otherwise prompted interactively
# (input hidden). PAT must have Read/Write/Delete scopes on the target repo.
#
# Ongoing prevention of sha-* tag accumulation is handled by the separate
# workflow .github/workflows/dockerhub-tag-cleanup.yml.
set -euo pipefail

REPO="heyvaldemar/aws-kubectl"
API="https://hub.docker.com"
UA="aws-kubectl-cleanup-script/1.0"

# Exactly 19 legacy tags from the pre-Phase-1 CI era. Kept inline so this
# script remains self-contained and auditable in version control.
LEGACY_TAGS=(
  bf0dcafe2fcc44b612cf50504b384b6c13b8ea01
  813eb8f079e1decc7362f8911b6c289644a6efa1
  4888f152d7d2189f6e1f24f979361cc6f81bdc4b
  1f3a4f78b48fdadfa11adb4338dd893b4ffc465c
  7e69e1d89059f50905a8e36fec93eaf22a832409
  58dad7caa5986ceacd1bc818010a5e132d80452b
  b8a25fe2c6790a9a844e9554e6d835cc85b1055d
  6a87312f722582ec099f9fa276000dc8ca73590e
  162c552d2a8b978ad83a8ba4d589a01afaa99a43
  dc1fa1c2cb926fbd8174da60e7d1544d09c39234
  f2d1feaed4f1cbc7c6817b27f3dda528e88f2e7a
  a5a8828403df81205ac486c6bd90812800789d2e
  b085b097d41eabaf5397ee1ff9a5b899fcca6b2b
  178d8089585d0162fb0eedb0760a478c8b7c69ae
  0217944ed1747c745015b621388d3ae3d804d010
  fa3e700d8f00b78c5f525aa0d6e7486fb3d7ba78
  23392bea9a5febf1a9218f5085107a996e65c216
  e59d3c6fbf63fbd13994e2522c37ddb99011207d
  c87d7e7851436abf90b220c2e3d76527c6b1a2eb
)

MODE="${1:---dry-run}"
case "$MODE" in
  --dry-run|--execute) ;;
  -h|--help)
    sed -n '2,/^set /p' "$0" | sed 's/^# \{0,1\}//' | head -n 11
    exit 0
    ;;
  *)
    echo "Usage: $0 [--dry-run|--execute]" >&2
    exit 2
    ;;
esac

# Acquire PAT.
if [ -z "${DOCKERHUB_PAT:-}" ]; then
  # Prompt hidden; stderr so it shows even if stdout is redirected.
  read -r -s -p "Docker Hub PAT (input hidden, Enter when done): " DOCKERHUB_PAT
  echo
fi
if [ -z "${DOCKERHUB_PAT}" ]; then
  echo "ERROR: DOCKERHUB_PAT is empty." >&2
  exit 1
fi

# Exchange PAT for short-lived JWT. The REST API for tag deletion requires a
# bearer JWT, not the raw PAT.
echo "Exchanging PAT for Docker Hub JWT..."
LOGIN_BODY=$(python3 -c '
import json, os
print(json.dumps({"username": "heyvaldemar", "password": os.environ["DOCKERHUB_PAT"]}))
')
JWT=$(
  DOCKERHUB_PAT="${DOCKERHUB_PAT}" \
  curl -sS -f \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "User-Agent: ${UA}" \
    -X POST \
    -d "${LOGIN_BODY}" \
    "${API}/v2/users/login/" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("token",""))'
)
if [ -z "${JWT}" ]; then
  echo "ERROR: JWT exchange failed (empty token)." >&2
  exit 1
fi

# --execute requires explicit confirmation. Typed "DELETE", nothing else.
if [ "${MODE}" = "--execute" ]; then
  echo
  echo "ABOUT TO DELETE ${#LEGACY_TAGS[@]} tags from ${REPO} on Docker Hub."
  echo "This is irreversible."
  read -r -p "Type DELETE to proceed (anything else aborts): " confirm
  if [ "${confirm}" != "DELETE" ]; then
    echo "Aborted."
    exit 1
  fi
fi

to_delete=0
already_gone=0
errors=0

for tag in "${LEGACY_TAGS[@]}"; do
  URL="${API}/v2/repositories/${REPO}/tags/${tag}/"
  if [ "${MODE}" = "--dry-run" ]; then
    HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer ${JWT}" \
      -H "Accept: application/json" \
      -H "User-Agent: ${UA}" \
      "${URL}")
    case "${HTTP_CODE}" in
      200) printf 'would delete: %s\n' "${tag}"; to_delete=$((to_delete+1)) ;;
      404) printf 'already gone: %s\n' "${tag}"; already_gone=$((already_gone+1)) ;;
      *)   printf 'WARN (HTTP %s): %s\n' "${HTTP_CODE}" "${tag}" >&2
           errors=$((errors+1)) ;;
    esac
  else
    HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
      -X DELETE \
      -H "Authorization: Bearer ${JWT}" \
      -H "Accept: application/json" \
      -H "User-Agent: ${UA}" \
      "${URL}")
    case "${HTTP_CODE}" in
      204) printf 'deleted: %s\n' "${tag}"; to_delete=$((to_delete+1)) ;;
      404) printf 'already gone: %s\n' "${tag}"; already_gone=$((already_gone+1)) ;;
      *)   printf 'ERROR (HTTP %s): %s\n' "${HTTP_CODE}" "${tag}" >&2
           errors=$((errors+1)) ;;
    esac
  fi
  # Respect Docker Hub API rate limits.
  sleep 1
done

echo
if [ "${MODE}" = "--dry-run" ]; then
  printf 'DRY-RUN SUMMARY: would-delete=%d already-gone=%d errors=%d\n' \
    "${to_delete}" "${already_gone}" "${errors}"
else
  printf 'EXECUTE SUMMARY: deleted=%d already-gone=%d errors=%d\n' \
    "${to_delete}" "${already_gone}" "${errors}"
fi

if [ "${errors}" -gt 0 ]; then
  exit 1
fi

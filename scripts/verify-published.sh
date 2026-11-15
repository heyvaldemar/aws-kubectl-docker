#!/usr/bin/env bash
# LAYER 3: WHAT THE REGISTRY SERVES, READ BACK AFTER SIGNING.
#
# Building and pushing is one layer, signing and attesting another; neither
# says what somebody pulling a tag gets. This reads every tag the run pushed
# back from the registry, resolves the digest it names now, and requires that
# digest's cosign signature (the sha256-<hex>.sig tag, HTTP 200) and a
# `cosign verify` that passes for this repository's publish workflow.
#
#   IMAGE=heyvaldemar/aws-kubectl DIGEST=sha256:<hex> TAGS="<one per line>" \
#   CERT_IDENTITY=https://github.com/<owner>/<repo>/.github/workflows/publish.yml@<ref> \
#     scripts/verify-published.sh
#
# DIGEST       what this run's build pushed; empty when the push did not
#              finish. Every tag is checked even then: a push refused half way
#              has already moved some of them, which is how 2.2.0 went out
#              unsigned.
# TAGS         every tag the run pushed, one full reference per line, as
#              docker/metadata-action prints them.
# CERT_IDENTITY  the Sigstore identity this run signs as. A digest another run
#              signed is accepted from this workflow file on any ref.
# COSIGN_KEY   the signing test only: verify with the public key beside this
#              private key (cosign.pub beside cosign.key) instead.
#
# What fails the job:
# - The digest this run pushed has no signature. It is signed here and now
#   (this run built it, so this run's identity may vouch for it), and the job
#   still fails, so somebody reads why the signing step did not sign it.
# - A tag names a digest this run did not push. Another run moved it: the
#   weekly build, a push to main and a release tag all move kube-<minor>, and
#   two of them can overlap. That run signs its own image, and gets
#   OTHER_RUN_WAIT seconds (300) to do so. A digest this run did not build is
#   never signed here.
# - A tag the build pushed is missing, or the registry cannot be read.
#
# Each result goes to the signing log ($SIGNING_LOG, by default
# $RUNNER_TEMP/signing.log) as "<event>\t<image>@<digest>": verified, missing,
# verified-other, unsigned-other. The signing test reads it.
set -euo pipefail

: "${IMAGE:?IMAGE is the repository the build pushed to}"
: "${TAGS:?TAGS is every tag the build pushed}"
DIGEST="${DIGEST:-}"
OTHER_RUN_WAIT="${OTHER_RUN_WAIT:-300}"
log="${SIGNING_LOG:-${RUNNER_TEMP:-/tmp}/signing.log}"
here="$(cd "$(dirname "$0")" && pwd)"
issuer=https://token.actions.githubusercontent.com

if [ -z "${COSIGN_KEY:-}" ]; then
  : "${CERT_IDENTITY:?CERT_IDENTITY is the identity this run signs as}"
  : "${GITHUB_SHA:?GITHUB_SHA is the commit this run built}"
  # The same workflow file of this repository, on any ref.
  prefix="${CERT_IDENTITY%@*}"
  any_run="^${prefix//./\\.}@refs/"
fi

case "$IMAGE" in
  localhost:[0-9]*/*)
    registry="http://${IMAGE%%/*}"; repo="${IMAGE#*/}"; hub=false ;;
  *.*/* | *:*/* | localhost/*)
    echo "::error::${IMAGE}: Docker Hub is the registry this reads, and a local one for the signing test"; exit 1 ;;
  */*)
    registry=https://registry-1.docker.io; repo="$IMAGE"; hub=true ;;
  *)
    echo "::error::${IMAGE}: name the repository with its namespace"; exit 1 ;;
esac

accept='application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'

# manifest <tag>: CODE is the registry's answer to a HEAD of that manifest,
# NAMED the digest it reports. Docker Hub wants a pull token even for a public
# repository; it reaches curl on stdin as a config line, never in curl's
# arguments, where every process on the machine can read it.
manifest() {
  local headers token=""
  CODE=000
  NAMED=""
  if $hub; then
    token="$(curl -fsS --max-time 30 --retry 3 \
      "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${repo}:pull" | jq -r '.token // empty')" || token=""
    [ -n "$token" ] || return 0
  fi
  headers="$(mktemp)"
  CODE="$( { if [ -n "$token" ]; then printf 'header = "Authorization: Bearer %s"\n' "$token"; fi; } \
    | curl -sS -I -o /dev/null -D "$headers" -w '%{http_code}' --max-time 30 --retry 3 --retry-delay 5 \
        -K - -H "Accept: ${accept}" "${registry}/v2/${repo}/manifests/$1")" || CODE=000
  NAMED="$(tr -d '\r' < "$headers" | awk 'tolower($1) == "docker-content-digest:" { d = $2 } END { print d }')"
  rm -f "$headers"
}

# signature_on <digest> <seconds>: true once sha256-<hex>.sig answers 200,
# asking every 15 seconds for up to <seconds>.
signature_on() {
  local deadline=$((SECONDS + $2))
  while :; do
    manifest "sha256-${1#sha256:}.sig"
    [ "$CODE" = 200 ] && return 0
    [ "$CODE" = 404 ] || echo "::warning::the registry answered ${CODE} for the signature of ${IMAGE}@$1"
    [ "$SECONDS" -lt "$deadline" ] || return 1
    sleep 15
  done
}

# verifies <digest> this|any: cosign verify, as this run or as any run of
# this workflow file.
verifies() {
  local ref="${IMAGE}@$1" err
  if [ -n "${COSIGN_KEY:-}" ]; then
    err="$(cosign verify --key "${COSIGN_KEY%.key}.pub" --insecure-ignore-tlog=true "$ref" 2>&1 >/dev/null)" && return 0
  elif [ "$2" = this ]; then
    err="$(cosign verify "$ref" --certificate-oidc-issuer "$issuer" \
      --certificate-identity "$CERT_IDENTITY" --certificate-github-workflow-sha "$GITHUB_SHA" 2>&1 >/dev/null)" && return 0
  else
    err="$(cosign verify "$ref" --certificate-oidc-issuer "$issuer" \
      --certificate-identity-regexp "$any_run" 2>&1 >/dev/null)" && return 0
  fi
  printf '%s\n' "$err" | tail -n 5
  return 1
}

failed=0
fail() { echo "::error::$*"; failed=1; }
record() { printf '%s\t%s\n' "$1" "${IMAGE}@$2" >> "$log"; }
table=""
row() { table="${table}| \`${1:0:19}…\` | $2 | $3 |"$'\n'; echo "${IMAGE}@$1 ($2): $3"; }

ours=""     # tags that name the digest this run pushed
others=""   # "<digest>\t<tag>" for tags that name anything else
while IFS= read -r ref; do
  ref="${ref//[[:space:]]/}"
  [ -n "$ref" ] || continue
  tag="${ref##*:}"
  if [ "${ref%:*}" != "$IMAGE" ] || ! [[ "$tag" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
    fail "${ref} is not a tag of ${IMAGE}"
    continue
  fi
  manifest "$tag"
  case "$CODE" in
    200) ;;
    404)
      if [ -n "$DIGEST" ]; then
        fail "${ref} is not on the registry, though the build pushed it"
      else
        echo "${ref}: not on the registry; the push did not get that far"
      fi
      continue ;;
    *)
      fail "the registry answered ${CODE} for ${ref}; what it names is unknown"
      continue ;;
  esac
  if ! [[ "$NAMED" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    fail "the registry named no digest for ${ref}"
    continue
  fi
  if [ -n "$DIGEST" ] && [ "$NAMED" = "$DIGEST" ]; then
    ours="${ours} ${tag}"
  else
    others="${others}${NAMED}"$'\t'"${tag}"$'\n'
    if [ -n "$DIGEST" ]; then
      echo "::warning::${ref} names ${NAMED}, not ${DIGEST}, which this run pushed: another run has moved it since"
    fi
  fi
done <<< "$TAGS"
ours="${ours# }"

if [ -n "$DIGEST" ]; then
  [ -n "$ours" ] || echo "::warning::no tag names ${IMAGE}@${DIGEST} any more; its signature is checked all the same"
  if signature_on "$DIGEST" 30; then
    if verifies "$DIGEST" this; then
      record verified "$DIGEST"
      row "$DIGEST" "$ours" "signed by this run, verified"
    else
      fail "${IMAGE}@${DIGEST} has a signature, and it does not verify as this run"
      row "$DIGEST" "$ours" "signature does not verify"
    fi
  else
    record missing "$DIGEST"
    fail "UNSIGNED: ${IMAGE}@${DIGEST} (${ours:-no tag}) has no cosign signature on the registry: sha256-${DIGEST#sha256:}.sig answered ${CODE}. This run built it, so it signs it now; the job fails either way, because the signing step did not."
    if SIGNED_BY=resigned "${here}/sign-digest.sh" && signature_on "$DIGEST" 30 && verifies "$DIGEST" this; then
      record verified "$DIGEST"
      row "$DIGEST" "$ours" "UNSIGNED after the signing step; signed by this check, verified"
    else
      row "$DIGEST" "$ours" "UNSIGNED"
    fi
  fi
fi

if [ -n "$DIGEST" ]; then
  why="This run did not build it, so it does not sign it."
else
  why="This run's push did not finish, so it cannot tell whether it built this image, and signs nothing."
fi
for d in $(printf '%s' "$others" | cut -f1 | sort -u); do
  tags="$(printf '%s' "$others" | awk -F'\t' -v d="$d" '$1 == d { printf "%s%s", sep, $2; sep = " " }')"
  if signature_on "$d" "$OTHER_RUN_WAIT" && verifies "$d" any; then
    record verified-other "$d"
    row "$d" "$tags" "signed by a run of this workflow, verified"
  else
    record unsigned-other "$d"
    fail "UNSIGNED: ${IMAGE}@${d} (${tags}) has no signature from this repository's publish workflow. ${why}"
    row "$d" "$tags" "UNSIGNED, not signed here"
  fi
done

if [ -n "${GITHUB_STEP_SUMMARY:-}" ] && [ -n "$table" ]; then
  {
    echo "### What ${IMAGE} serves, read back from the registry"
    echo
    echo "| Digest | Tags | Signature |"
    echo "|---|---|---|"
    printf '%s' "$table"
  } >> "$GITHUB_STEP_SUMMARY"
fi
exit "$failed"

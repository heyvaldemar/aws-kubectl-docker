#!/usr/bin/env bash
# The signing steps, shown each failure they exist for.
#
#   tests/signing-plants.sh setup   # throwaway keys, and an image per case in a local registry
#   tests/signing-plants.sh check   # after the action has run on each case
#
# publish.yml's signing job runs .github/actions/sign-attest-verify, the very
# steps the build job runs after it pushes to Docker Hub, once per case,
# against images in a registry on the runner:
#
#   untouched     nothing planted: signed, read back, verified, green.
#   attest-fails  the real attestation step runs and fails (the job has no
#                 OIDC token), as Rekor made it fail on 2 November 2026: the
#                 image is signed all the same, before the failure, and the
#                 job still fails.
#   sign-fails    the signing step fails: the read-back still runs, finds no
#                 signature, and signs the digest this run built.
#   sign-skipped  no signature and no error, which is what 2 November looked
#                 like: the read-back alone fails the job, and signs.
#   moved         another run moved a tag to an image signed by a key that is
#                 not this workflow's: the job fails, and does not sign what
#                 this run did not build.
#   unfinished    the push stopped half way (no digest from the build), one
#                 tag already on an unsigned image: the job fails and signs
#                 nothing, since nothing says which digest this run built.
#
# Nothing reaches Docker Hub, GitHub's attestation store or Sigstore's public
# log: the keys are made here and their signatures stay offline, and setup
# refuses to run where the job could get an OIDC token, so the attestation
# step can only fail before it contacts anything.
set -euo pipefail

reg="${REG:-localhost:5000}"
log="${SIGNING_LOG:-${RUNNER_TEMP:?}/signing.log}"
accept='application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'

# code_of, digest_of <repo> <reference>: the local registry's HTTP answer for a manifest, and the digest it names.
code_of() { curl -s -o /dev/null -I --max-time 10 -H "Accept: ${accept}" -w '%{http_code}' "http://${reg}/v2/$1/manifests/$2"; }
digest_of() {
  curl -sS -I --max-time 10 -H "Accept: ${accept}" "http://${reg}/v2/$1/manifests/$2" \
    | tr -d '\r' | awk 'tolower($1) == "docker-content-digest:" { print $2 }'
}

# push <repo> <marker> <tag>...: a one-file image, pushed under each tag; prints its digest.
push() {
  local repo=$1 marker=$2 ctx d t
  shift 2
  ctx="$(mktemp -d)"
  printf '%s\n' "$marker" > "$ctx/plant"
  printf 'FROM scratch\nCOPY plant /plant\n' > "$ctx/Dockerfile"
  docker build -q --provenance=false --sbom=false -t "${reg}/${repo}:$1" "$ctx" >/dev/null
  for t in "$@"; do
    docker tag "${reg}/${repo}:$1" "${reg}/${repo}:${t}"
    docker push -q "${reg}/${repo}:${t}" >/dev/null
  done
  rm -rf "$ctx"
  d="$(digest_of "$repo" "$1")"
  [[ "$d" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "::error::the local registry named no digest for ${repo}:$1" >&2; return 1; }
  echo "$d"
}

setup() {
  : "${GITHUB_OUTPUT:?}"
  if [ -n "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]; then
    echo "::error::this job can get an OIDC token, so the attestation step would reach Sigstore and GitHub with a throwaway image; the signing job must not have id-token: write"
    exit 1
  fi
  (cd "$RUNNER_TEMP" && COSIGN_PASSWORD="" cosign generate-key-pair >/dev/null 2>&1)
  mkdir -p "$RUNNER_TEMP/stranger"
  (cd "$RUNNER_TEMP/stranger" && COSIGN_PASSWORD="" cosign generate-key-pair >/dev/null 2>&1)
  : > "$log"
  local untouched attest_fails sign_fails sign_skipped moved moved_other unfinished
  untouched="$(push untouched untouched latest edge)"
  attest_fails="$(push attest-fails attest-fails latest kube-1.37)"
  sign_fails="$(push sign-fails sign-fails latest)"
  sign_skipped="$(push sign-skipped sign-skipped latest edge)"
  moved="$(push moved moved main kube-1.37)"
  # Then another run puts its own image on kube-1.37, signed by a key that
  # is not this workflow's.
  moved_other="$(push moved moved-by-another-run kube-1.37)"
  COSIGN_PASSWORD="" cosign sign --yes --key "$RUNNER_TEMP/stranger/cosign.key" --tlog-upload=false \
    "${reg}/moved@${moved_other}" >/dev/null 2>&1
  # A push that stopped after its first tag.
  unfinished="$(push unfinished unfinished 2.3.1)"
  {
    echo "key=${RUNNER_TEMP}/cosign.key"
    echo "untouched=${untouched}"
    echo "attest_fails=${attest_fails}"
    echo "sign_fails=${sign_fails}"
    echo "sign_skipped=${sign_skipped}"
    echo "moved=${moved}"
    echo "moved_other=${moved_other}"
    echo "unfinished=${unfinished}"
  } | tee -a "$GITHUB_OUTPUT"
}

check() {
  : "${KEY:?}" "${UNTOUCHED:?}" "${ATTEST_FAILS:?}" "${SIGN_FAILS:?}" "${SIGN_SKIPPED:?}"
  : "${MOVED:?}" "${MOVED_OTHER:?}" "${UNFINISHED:?}"
  local missed=0 stranger u a s k m o f
  stranger="$(dirname "$KEY")/stranger/cosign.pub"
  u="${reg}/untouched@${UNTOUCHED}"
  a="${reg}/attest-fails@${ATTEST_FAILS}"
  s="${reg}/sign-fails@${SIGN_FAILS}"
  k="${reg}/sign-skipped@${SIGN_SKIPPED}"
  m="${reg}/moved@${MOVED}"
  o="${reg}/moved@${MOVED_OTHER}"
  f="${reg}/unfinished@${UNFINISHED}"

  echo "--- the signing log"
  cat "$log"
  echo "---"

  expect() { if "${@:2}"; then echo "  ok      $1"; else echo "  MISSED  $1"; missed=1; fi; }
  logged() { grep -qxF "$1"$'\t'"$2" "$log"; }
  not_logged() { ! logged "$@"; }
  line() { grep -nxF "$1"$'\t'"$2" "$log" | head -n 1 | cut -d: -f1; }
  before() { local x y; x="$(line "$1" "$2")"; y="$(line "$3" "$4")"; [ -n "$x" ] && [ -n "$y" ] && [ "$x" -lt "$y" ]; }
  verifies() { cosign verify --key "${2:-${KEY%.key}.pub}" --insecure-ignore-tlog=true "$1" >/dev/null 2>&1; }
  sig_code() { code_of "$2" "sha256-${1##*@sha256:}.sig"; }
  no_signature() { ! verifies "$1" && [ "$(sig_code "$1" "$2")" = 404 ]; }
  only_stranger() { ! verifies "$1" && verifies "$1" "$stranger" && [ "$(sig_code "$1" "$2")" = 200 ]; }
  nothing_signed() { not_logged signed "$1" && not_logged resigned "$1"; }

  echo "untouched"
  expect "the action succeeds" [ "${UNTOUCHED_OUTCOME:-}" = success ]
  expect "the signing step signed the digest" logged signed "$u"
  expect "the attestation step was not run on a throwaway image" logged attest "skipped"$'\t'"${reg}/untouched"
  expect "the read-back verified it" logged verified "$u"
  expect "nothing was found missing" not_logged missing "$u"
  expect "nothing was signed again" not_logged resigned "$u"
  expect "the signature verifies" verifies "$u"

  echo "attest-fails"
  expect "the real attestation step ran and failed" logged attest "failure"$'\t'"${reg}/attest-fails"
  expect "the job fails" [ "${ATTEST_FAILS_OUTCOME:-}" = failure ]
  expect "the signing step signed the digest" logged signed "$a"
  expect "it signed before the attestation failed" before signed "$a" attest "failure"$'\t'"${reg}/attest-fails"
  expect "the read-back verified it" logged verified "$a"
  expect "it did not need signing again" not_logged resigned "$a"
  expect "the signature verifies" verifies "$a"

  echo "sign-fails"
  expect "the planted signing failure ran" logged planted "sign-fails"$'\t'"${reg}/sign-fails"
  expect "the job fails" [ "${SIGN_FAILS_OUTCOME:-}" = failure ]
  expect "the signing step signed nothing" not_logged signed "$s"
  expect "the read-back still ran, and found the signature missing" logged missing "$s"
  expect "it signed the digest this run built" logged resigned "$s"
  expect "and verified it" logged verified "$s"
  expect "the signature verifies" verifies "$s"

  echo "sign-skipped"
  expect "the planted silent skip ran" logged planted "sign-skipped"$'\t'"${reg}/sign-skipped"
  expect "the read-back alone fails the job" [ "${SIGN_SKIPPED_OUTCOME:-}" = failure ]
  expect "the signing step signed nothing" not_logged signed "$k"
  expect "the read-back found the signature missing" logged missing "$k"
  expect "it signed the digest this run built" logged resigned "$k"
  expect "and verified it" logged verified "$k"
  expect "the signature verifies" verifies "$k"

  echo "moved"
  expect "the job fails" [ "${MOVED_OUTCOME:-}" = failure ]
  expect "this run's digest was signed and verified" logged verified "$m"
  expect "the other run's digest was reported" logged unsigned-other "$o"
  expect "it was not signed by this run" nothing_signed "$o"
  expect "its only signature is the stranger's" only_stranger "$o" moved
  expect "this run's signature verifies" verifies "$m"

  echo "unfinished"
  expect "the job fails" [ "${UNFINISHED_OUTCOME:-}" = failure ]
  expect "the tag already pushed was reported" logged unsigned-other "$f"
  expect "nothing was signed" nothing_signed "$f"
  expect "it is still unsigned" no_signature "$f" unfinished

  if [ "$missed" != 0 ]; then
    echo "::error::the signing steps missed a failure they exist for (MISSED above)"
    exit 1
  fi
  echo "every failure was noticed, and every image this run built is signed"
}

case "${1:-}" in
  setup) setup ;;
  check) check ;;
  *) sed -n '2,5p' "$0"; exit 2 ;;
esac

#!/usr/bin/env bash
# The signing steps, shown each failure they exist for.
#
#   tests/signing-plants.sh setup   # a throwaway key, and an image per case in a local registry
#   tests/signing-plants.sh check   # after the action has run on each case
#
# publish.yml's signing job runs .github/actions/sign-attest-verify, the very
# steps the build job runs after it pushes to Docker Hub, four times, against
# images in a registry on the runner:
#
#   untouched     nothing planted: signed, read back, verified, green.
#   attest-fails  the attestation fails, as Rekor made it fail on 2 November
#                 2026: the image is signed all the same, before the failure,
#                 and the job still fails.
#   sign-fails    signing fails: the read-back finds no signature, fails, and
#                 signs the digest this run built.
#   moved         another run moved one of the tags to an image nobody signed:
#                 the read-back waits, fails, and does not sign what this run
#                 did not build.
#
# Nothing reaches Docker Hub, GitHub's attestation store or Sigstore's public
# log: the key is made here, and its signatures stay offline.
set -euo pipefail

reg="${REG:-localhost:5000}"
log="${SIGNING_LOG:-${RUNNER_TEMP:?}/signing.log}"

# digest_of <repo> <tag>: the digest the local registry names for it.
digest_of() {
  curl -sS -I --max-time 10 \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
    "http://${reg}/v2/$1/manifests/$2" | tr -d '\r' | awk 'tolower($1) == "docker-content-digest:" { print $2 }'
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
  (cd "$RUNNER_TEMP" && COSIGN_PASSWORD="" cosign generate-key-pair >/dev/null)
  : > "$log"
  local untouched attest_fails sign_fails moved moved_other
  untouched="$(push untouched untouched latest edge)"
  attest_fails="$(push attest-fails attest-fails latest kube-1.37)"
  sign_fails="$(push sign-fails sign-fails latest)"
  moved="$(push moved moved main kube-1.37)"
  # Then another run puts its own image, which nobody signs, on kube-1.37.
  moved_other="$(push moved moved-by-another-run kube-1.37)"
  {
    echo "key=${RUNNER_TEMP}/cosign.key"
    echo "untouched=${untouched}"
    echo "attest_fails=${attest_fails}"
    echo "sign_fails=${sign_fails}"
    echo "moved=${moved}"
    echo "moved_other=${moved_other}"
  } | tee -a "$GITHUB_OUTPUT"
}

check() {
  : "${KEY:?}" "${UNTOUCHED:?}" "${ATTEST_FAILS:?}" "${SIGN_FAILS:?}" "${MOVED:?}" "${MOVED_OTHER:?}"
  local missed=0 u a s m o
  u="${reg}/untouched@${UNTOUCHED}"
  a="${reg}/attest-fails@${ATTEST_FAILS}"
  s="${reg}/sign-fails@${SIGN_FAILS}"
  m="${reg}/moved@${MOVED}"
  o="${reg}/moved@${MOVED_OTHER}"

  echo "--- the signing log"
  cat "$log"
  echo "---"

  expect() { if "${@:2}"; then echo "  ok      $1"; else echo "  MISSED  $1"; missed=1; fi; }
  logged() { grep -qxF "$1"$'\t'"$2" "$log"; }
  not_logged() { ! logged "$@"; }
  line() { grep -nxF "$1"$'\t'"$2" "$log" | head -n 1 | cut -d: -f1; }
  before() { local x y; x="$(line "$1" "$2")"; y="$(line "$3" "$4")"; [ -n "$x" ] && [ -n "$y" ] && [ "$x" -lt "$y" ]; }
  verifies() { cosign verify --key "${KEY%.key}.pub" --insecure-ignore-tlog=true "$1" >/dev/null 2>&1; }
  unsigned() {
    ! verifies "$1" && [ "$(curl -s -o /dev/null -I -w '%{http_code}' "http://${reg}/v2/${2}/manifests/sha256-${1##*@sha256:}.sig")" = 404 ]
  }

  echo "untouched"
  expect "the action succeeds" [ "${UNTOUCHED_OUTCOME:-}" = success ]
  expect "the signing step signed the digest" logged signed "$u"
  expect "the read-back verified it" logged verified "$u"
  expect "nothing was found missing" not_logged missing "$u"
  expect "nothing was signed again" not_logged resigned "$u"
  expect "the signature verifies" verifies "$u"

  echo "attest-fails"
  expect "the planted attestation failure ran" logged planted "attest-fails"$'\t'"${reg}/attest-fails"
  expect "the job still fails" [ "${ATTEST_FAILS_OUTCOME:-}" = failure ]
  expect "the signing step signed the digest" logged signed "$a"
  expect "it signed before the attestation failed" before signed "$a" planted "attest-fails"$'\t'"${reg}/attest-fails"
  expect "the read-back verified it" logged verified "$a"
  expect "it did not need signing again" not_logged resigned "$a"
  expect "the signature verifies" verifies "$a"

  echo "sign-fails"
  expect "the planted signing failure ran" logged planted "sign-fails"$'\t'"${reg}/sign-fails"
  expect "the job fails" [ "${SIGN_FAILS_OUTCOME:-}" = failure ]
  expect "the signing step signed nothing" not_logged signed "$s"
  expect "the read-back found the signature missing" logged missing "$s"
  expect "it signed the digest this run built" logged resigned "$s"
  expect "and verified it" logged verified "$s"
  expect "the signature verifies" verifies "$s"

  echo "moved"
  expect "the job fails" [ "${MOVED_OUTCOME:-}" = failure ]
  expect "this run's digest was signed and verified" logged verified "$m"
  expect "the other run's unsigned digest was reported" logged unsigned-other "$o"
  expect "it was not signed by this run" not_logged resigned "$o"
  expect "it is still unsigned" unsigned "$o" moved
  expect "this run's signature verifies" verifies "$m"

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

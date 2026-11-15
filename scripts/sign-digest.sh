#!/usr/bin/env bash
# Signs one pushed image digest with cosign. Once per digest, whatever tags
# name it: the signature is stored under the digest (sha256-<hex>.sig), and
# signing it again per tag added nothing but another trip to Rekor.
#
#   IMAGE=heyvaldemar/aws-kubectl DIGEST=sha256:<hex> scripts/sign-digest.sh
#
# Keyless: Sigstore issues a certificate for this run's GitHub Actions identity
# and records the signature in its public transparency log, Rekor. With
# COSIGN_KEY set to a private key file it signs with that key instead and
# writes nothing to Rekor; only the signing test does that, on throwaway images
# in a local registry.
#
# A signature is a call to Fulcio, an entry in Rekor and a push to the
# registry, and any of them can answer 5xx for a minute: Rekor answered 502 to
# this repository's attestation on 2 November 2026. A failed attempt is tried
# again 30 and then 90 seconds later.
#
# Each signature made is recorded in the signing log ($SIGNING_LOG, by default
# $RUNNER_TEMP/signing.log) as "<SIGNED_BY>\t<image>@<digest>", which is how
# the signing test tells the signing step from the registry check's re-sign.
set -euo pipefail

: "${IMAGE:?IMAGE is the repository the digest was pushed to}"
: "${DIGEST:?DIGEST is the digest to sign}"
if ! [[ "$DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "::error::not an image digest: ${DIGEST}"
  exit 1
fi

ref="${IMAGE}@${DIGEST}"
log="${SIGNING_LOG:-${RUNNER_TEMP:-/tmp}/signing.log}"
args=(--yes)
if [ -n "${COSIGN_KEY:-}" ]; then
  export COSIGN_PASSWORD="${COSIGN_PASSWORD-}"
  args+=(--key "$COSIGN_KEY" --tlog-upload=false)
fi

for pause in 30 90 last; do
  if cosign sign "${args[@]}" "$ref"; then
    printf '%s\t%s\n' "${SIGNED_BY:-signed}" "$ref" >> "$log"
    echo "signed ${ref}"
    exit 0
  fi
  [ "$pause" = last ] && break
  echo "::warning::cosign could not sign ${ref}; trying again in ${pause} seconds"
  sleep "$pause"
done
echo "::error::cosign could not sign ${ref} in three attempts"
exit 1

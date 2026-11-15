#!/usr/bin/env bash
# Names a signed image: points every tag the run computed at the digest it
# pushed, in one `docker buildx imagetools create --prefer-index=false`, which
# copies the source as it is, so each tag names the very digest that was
# signed. Without the flag, a single-platform manifest is wrapped in a new
# index with a digest nobody signed (both checked on 2026-11-15 against
# registry:3: a multi-platform index with attestation manifests, and a
# single manifest).
#
#   IMAGE=heyvaldemar/aws-kubectl DIGEST=sha256:<hex> TAGS="<one per line>" scripts/tag-digest.sh
#
# The publish job runs it only after verify-published.sh in before-tags mode
# has seen this digest's signature, so a tag never names an unsigned image. A
# failed push is tried again 30 and then 90 seconds later; a tag the registry
# refuses (an immutable one already taken) fails the job, and the read-back
# after it reports what each tag names.
set -euo pipefail

: "${IMAGE:?IMAGE is the repository the build pushed to}"
: "${DIGEST:?DIGEST is the signed digest to name}"
: "${TAGS:?TAGS is every tag to point at it}"
if ! [[ "$DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "::error::not an image digest: ${DIGEST}"
  exit 1
fi
log="${SIGNING_LOG:-${RUNNER_TEMP:-/tmp}/signing.log}"

args=()
while IFS= read -r ref; do
  ref="${ref//[[:space:]]/}"
  [ -n "$ref" ] || continue
  if [ "${ref%:*}" != "$IMAGE" ] || ! [[ "${ref##*:}" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
    echo "::error::${ref} is not a tag of ${IMAGE}"
    exit 1
  fi
  args+=(-t "$ref")
done <<< "$TAGS"
if [ "${#args[@]}" = 0 ]; then
  echo "::error::no tag to name ${IMAGE}@${DIGEST} with"
  exit 1
fi

for pause in 30 90 last; do
  if docker buildx imagetools create --prefer-index=false "${args[@]}" "${IMAGE}@${DIGEST}"; then
    printf 'tagged\t%s\n' "${IMAGE}@${DIGEST}" >> "$log"
    echo "named ${IMAGE}@${DIGEST}: $((${#args[@]} / 2)) tags"
    exit 0
  fi
  [ "$pause" = last ] && break
  echo "::warning::could not name ${IMAGE}@${DIGEST}; trying again in ${pause} seconds"
  sleep "$pause"
done
echo "::error::could not name ${IMAGE}@${DIGEST} in three attempts"
exit 1

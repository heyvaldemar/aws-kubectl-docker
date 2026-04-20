#!/usr/bin/env bash
# Smoke test for heyvaldemar/aws-kubectl images.
# Verifies the advertised toolchain is present, working, and consistent with
# the /etc/kube-version marker baked in at build time.
set -euo pipefail

IMAGE="${1:-aws-kubectl:local}"

say() { printf '\n>>> %s\n\n' "$*"; }
run() {
  echo "+ $*"
  sh -c "$*"
  echo
}

say "Image: $IMAGE"

run "docker run --rm '$IMAGE' sh -c 'uname -a; echo -n \"Arch: \"; uname -m'"

# Core toolchain: every binary must respond. No `|| true` fallbacks.
run "docker run --rm '$IMAGE' aws --version"
run "docker run --rm '$IMAGE' kubectl version --client --output=yaml"
run "docker run --rm '$IMAGE' jq --version"
run "docker run --rm '$IMAGE' envsubst --version"
run "docker run --rm '$IMAGE' sh -c 'curl --version | head -n1'"
run "docker run --rm '$IMAGE' sh -c 'unzip -v | head -n2'"

# Binary presence + CA bundle.
run "docker run --rm '$IMAGE' sh -c 'ls -l /usr/local/bin/kubectl; for b in aws jq envsubst curl unzip; do command -v \"\$b\"; done'"
run "docker run --rm '$IMAGE' sh -c 'ls -lh /etc/ssl/certs/ca-certificates.crt'"
run "docker run --rm '$IMAGE' sh -c 'curl -fsSI -o /dev/null -w \"HTTPS OK (%{http_code})\\n\" https://kubernetes.io'"

# /etc/kube-version must match the kubectl client version reported at runtime.
say "Verifying /etc/kube-version matches kubectl --client"
FILE_VERSION="$(docker run --rm "$IMAGE" cat /etc/kube-version | tr -d '[:space:]')"
CLIENT_VERSION="$(docker run --rm "$IMAGE" kubectl version --client --output=json \
  | jq -r '.clientVersion.gitVersion')"

echo "/etc/kube-version    = $FILE_VERSION"
echo "kubectl client git   = $CLIENT_VERSION"

if [ -z "$FILE_VERSION" ] || [ -z "$CLIENT_VERSION" ]; then
  echo "FAIL: could not read one of the version strings." >&2
  exit 1
fi

if [ "$FILE_VERSION" != "$CLIENT_VERSION" ]; then
  echo "FAIL: /etc/kube-version ($FILE_VERSION) does not match kubectl client ($CLIENT_VERSION)." >&2
  exit 1
fi
echo "OK: /etc/kube-version matches kubectl client version"

# Optional real-world checks — these require local credentials and are
# expected to be best-effort, so we still guard them with `|| true`.
if [ -d "${HOME}/.aws" ]; then
  run "docker run --rm -v '${HOME}/.aws:/root/.aws' '$IMAGE' aws sts get-caller-identity || true"
fi
if [ -d "${HOME}/.kube" ]; then
  run "docker run --rm -v '${HOME}/.kube:/root/.kube' '$IMAGE' kubectl config current-context || true"
  run "docker run --rm -v '${HOME}/.kube:/root/.kube' '$IMAGE' kubectl get nodes --request-timeout=5s -o name || true"
fi

say "All checks passed."

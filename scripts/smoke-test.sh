#!/usr/bin/env bash
set -euo pipefail
IMAGE="${1:-aws-kubectl:local}"

say(){ printf "\n>>> %s\n\n" "$*"; }
run(){ echo "+ $*"; bash -lc "$*"; echo; }

say "Image: $IMAGE"

run "docker run --rm $IMAGE sh -lc 'uname -a; echo -n \"Arch: \"; uname -m'"

run "docker run --rm $IMAGE aws --version"
run "docker run --rm $IMAGE kubectl version --client --output=yaml"
run "docker run --rm $IMAGE jq --version"
run "docker run --rm $IMAGE envsubst --version || true"
run "docker run --rm $IMAGE sh -lc 'curl --version | head -n1'"
run "docker run --rm $IMAGE sh -lc 'unzip -v | head -n2'"

run "docker run --rm $IMAGE sh -lc 'ls -l /usr/local/bin/kubectl; which aws jq envsubst curl unzip'"
run "docker run --rm $IMAGE sh -lc 'ls -lh /etc/ssl/certs/ca-certificates.crt || true'"
run "docker run --rm $IMAGE sh -lc 'curl -fsS -o /dev/null -w \"HTTPS OK (%{http_code})\\n\" https://kubernetes.io'"

if [[ -d ~/.aws ]]; then
  run "docker run --rm -v ~/.aws:/root/.aws $IMAGE aws sts get-caller-identity || true"
fi
if [[ -d ~/.kube ]]; then
  run "docker run --rm -v ~/.kube:/root/.kube $IMAGE kubectl config current-context || true"
  run "docker run --rm -v ~/.kube:/root/.kube $IMAGE kubectl get nodes --request-timeout=5s -o name || true"
fi

say "All checks completed."
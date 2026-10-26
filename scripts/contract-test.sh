#!/usr/bin/env bash
# Contract test: does a new build keep every promise the published image made?
#
#   scripts/contract-test.sh <new-image> [<published-image>] [<kube-minor>]
#
# The smoke test asks whether the advertised tools work. This asks the other
# question a production pipeline cares about: is anything it used yesterday
# gone today? The image is pulled more than 1.6 million times, by CI jobs that
# call whatever happens to be on PATH, run as whatever user the image sets, and
# rely on where HOME is. A base image update that drops a binary nobody
# advertised, or a Dockerfile edit that moves the working directory, passes
# every smoke check and breaks those jobs on Monday morning. So the published
# image is the baseline, and the new build must keep:
#
#   - every executable on PATH (a removal must be listed, with its reason, in
#     tests/contract-removed.tsv, which the changelog then has to explain);
#   - the user, HOME, working directory, entrypoint, command and PATH;
#   - the AWS CLI major version;
#   - the kubectl minor, when a line is pinned to one (kube-1.37), or a kubectl
#     no older than the published one on latest.
#
# With no published image to compare with (a new kube-<minor> line), the
# config and executables are compared with :latest and the kubectl check is
# skipped. tests/plant-violations.py shows this test each break it exists for.
set -euo pipefail

NEW="${1:?usage: contract-test.sh <new-image> [<published-image>] [<kube-minor>]}"
BASE="${2:-heyvaldemar/aws-kubectl:latest}"
MINOR="${3:-}"
REMOVED_FILE="$(dirname "$0")/../tests/contract-removed.tsv"
fail=0
bad() { echo "FAIL: $*" >&2; fail=1; }
ok() { echo "OK: $*"; }

if ! docker image inspect "$BASE" >/dev/null 2>&1; then
  docker pull -q "$BASE" >/dev/null 2>&1 || {
    echo "no published image $BASE to compare with; comparing with heyvaldemar/aws-kubectl:latest and skipping the kubectl check"
    BASE=heyvaldemar/aws-kubectl:latest
    docker pull -q "$BASE" >/dev/null
    MINOR="skip"
  }
fi
echo "new:       $NEW"
echo "published: $BASE ($(docker image inspect -f '{{index .RepoDigests 0}}' "$BASE" 2>/dev/null || echo local))"

# Every executable on PATH, by name. The image's own shell lists it, so PATH
# is the image's, not this host's.
executables() {
  docker run --rm --entrypoint sh "$1" -c '
    IFS=:
    for d in $PATH; do
      [ -d "$d" ] || continue
      for f in "$d"/*; do
        [ -f "$f" ] && [ -x "$f" ] && echo "${f##*/}"
      done
    done' | sort -u
}
allowed="$(grep -vE '^\s*(#|$)' "$REMOVED_FILE" 2>/dev/null | awk '{print $1}' | sort -u || true)"
missing="$(comm -23 <(executables "$BASE") <(executables "$NEW"))"
unexplained="$(comm -23 <(printf '%s\n' "$missing" | sed '/^$/d') <(printf '%s\n' "$allowed" | sed '/^$/d'))"
if [ -n "$unexplained" ]; then
  bad "executables the published image has and this build does not: $(echo "$unexplained" | tr '\n' ' ')(list each in tests/contract-removed.tsv with its reason if the removal is meant)"
else
  ok "every executable on the published image's PATH is still there ($(executables "$NEW" | grep -c .) on PATH)"
fi

for field in User WorkingDir Entrypoint Cmd; do
  a="$(docker image inspect -f "{{json .Config.$field}}" "$BASE")"
  b="$(docker image inspect -f "{{json .Config.$field}}" "$NEW")"
  if [ "$a" = "$b" ]; then ok "$field unchanged ($b)"; else bad "$field changed: published $a, this build $b"; fi
done
for var in PATH HOME; do
  a="$(docker image inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$BASE" | sed -n "s/^$var=//p")"
  b="$(docker image inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$NEW" | sed -n "s/^$var=//p")"
  if [ "$a" = "$b" ]; then ok "$var unchanged (${b:-unset})"; else bad "$var changed: published '${a}', this build '${b}'"; fi
done

aws_major() { docker run --rm "$1" aws --version 2>&1 | sed -nE 's#^aws-cli/([0-9]+)\..*#\1#p'; }
a="$(aws_major "$BASE")"; b="$(aws_major "$NEW")"
if [ -n "$b" ] && [ "$a" = "$b" ]; then ok "AWS CLI major unchanged (v$b)"; else bad "AWS CLI major: published v${a:-?}, this build v${b:-?}"; fi

kube() { docker run --rm --entrypoint cat "$1" /etc/kube-version | tr -d '[:space:]v'; }
if [ "$MINOR" != "skip" ]; then
  a="$(kube "$BASE")"; b="$(kube "$NEW")"
  if [ -n "$MINOR" ]; then
    case "$b" in
      "$MINOR".*) ok "kubectl stays on the $MINOR line ($b)" ;;
      *) bad "kubectl $b is not on the $MINOR line this tag promises" ;;
    esac
  fi
  if [ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -1)" = "$a" ]; then
    ok "kubectl $b is not older than the published $a"
  else
    bad "kubectl went backwards: published $a, this build $b"
  fi
fi

if [ "$fail" -ne 0 ]; then echo "The contract is broken; nothing is published." >&2; exit 1; fi
echo "The contract holds."

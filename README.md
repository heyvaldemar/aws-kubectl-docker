# aws-kubectl Docker Image

[![Docker Pulls](https://img.shields.io/docker/pulls/heyvaldemar/aws-kubectl.svg)](https://hub.docker.com/r/heyvaldemar/aws-kubectl)
[![Docker Image Size](https://img.shields.io/docker/image-size/heyvaldemar/aws-kubectl/latest.svg)](https://hub.docker.com/r/heyvaldemar/aws-kubectl/tags)
[![Build Status](https://github.com/heyvaldemar/aws-kubectl-docker/actions/workflows/publish.yml/badge.svg?branch=main)](https://github.com/heyvaldemar/aws-kubectl-docker/actions/workflows/publish.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/heyvaldemar/aws-kubectl-docker/badge)](https://scorecard.dev/viewer/?uri=github.com/heyvaldemar/aws-kubectl-docker)
[![Cosign Verified](https://img.shields.io/badge/cosign-verified-brightgreen?logo=sigstore)](https://github.com/heyvaldemar/aws-kubectl-docker/attestations)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Contents

- [aws-kubectl Docker Image](#aws-kubectl-docker-image)
  - [Contents](#contents)
  - [Why this image?](#why-this-image)
  - [Getting started](#getting-started)
  - [Pinning guidance](#pinning-guidance)
  - [Features](#features)
    - [Typical use cases](#typical-use-cases)
  - [Supply chain](#supply-chain)
    - [Verifying signatures](#verifying-signatures)
  - [Tag management](#tag-management)
  - [Breaking Changes in v2.0](#breaking-changes-in-v20)
    - [For most users: no changes needed](#for-most-users-no-changes-needed)
    - [For users mounting volumes](#for-users-mounting-volumes)
    - [Staying on v1.x](#staying-on-v1x)
  - [Mounting credentials](#mounting-credentials)
  - [Running the Container](#running-the-container)
    - [Execute commands directly (no shell)](#execute-commands-directly-no-shell)
  - [Build Instructions](#build-instructions)
    - [Local single-arch (dev)](#local-single-arch-dev)
    - [Pin a specific kubectl](#pin-a-specific-kubectl)
    - [Stamp revision and build date (recommended for release builds)](#stamp-revision-and-build-date-recommended-for-release-builds)
    - [Multi-arch build \& push (amd64 + arm64)](#multi-arch-build--push-amd64--arm64)
  - [Local Build \& Test (using the repo script)](#local-build--test-using-the-repo-script)
    - [Optional “real” checks (with mounted config)](#optional-real-checks-with-mounted-config)
  - [Security Notes](#security-notes)
  - [Run as root (override)](#run-as-root-override)
  - [About the maintainer](#about-the-maintainer)

This image streamlines work with Amazon Web Services (AWS) and Kubernetes by bundling **AWS CLI v2** (`aws`) and **kubectl** on **Ubuntu 24.04**. It also includes `jq`, `curl`, `unzip`, and `envsubst` (from `gettext-base`). Perfect for CI/CD steps, automation, and reproducible local scripting.

🐳 Docker Hub: [heyvaldemar/aws-kubectl](https://hub.docker.com/r/heyvaldemar/aws-kubectl)

## Why this image?

| Need | This image | `amazon/aws-cli` | `bitnami/kubectl` | Alpine + scripts |
|------|-----------|------------------|-------------------|------------------|
| AWS CLI v2 | ✅ | ✅ | ❌ | manual |
| kubectl | ✅ | ❌ | ✅ | manual |
| jq, envsubst, curl, unzip | ✅ | ❌ | ❌ | manual |
| Multi-arch (amd64/arm64) | ✅ | ✅ | ✅ | depends |
| Cosign signatures | ✅ | ✅ | ❌ | ❌ |
| SBOM (SPDX) | ✅ | ❌ | ❌ | ❌ |
| SLSA build provenance | ✅ | ❌ | ❌ | ❌ |
| OpenSSF Scorecard | 7.8/10 | N/A | N/A | N/A |
| Non-root default (UID 10001) | ✅ (v2.0+) | ❌ | ❌ | depends |
| Weekly base rebuild | ✅ | ✅ | ✅ | manual |

One image instead of three. Full supply-chain attestations. OpenShift-compatible out of the box.

## Getting started

```bash
# List S3 buckets (requires ~/.aws)
docker run --rm --user "$(id -u):0" \
  -v ~/.aws:/home/app/.aws \
  heyvaldemar/aws-kubectl aws s3 ls

# Get Kubernetes nodes (requires ~/.kube)
docker run --rm --user "$(id -u):0" \
  -v ~/.kube:/home/app/.kube \
  heyvaldemar/aws-kubectl kubectl get nodes

# Interactive shell with both
docker run -it --user "$(id -u):0" \
  -v ~/.aws:/home/app/.aws \
  -v ~/.kube:/home/app/.kube \
  heyvaldemar/aws-kubectl bash
```

Runs as non-root by default (UID 10001). See [Mounting credentials](#mounting-credentials) for permission details.

> 🚨 **Existing v1.x user and v2.0 broke your workflow?** Pin `heyvaldemar/aws-kubectl:v1-maintenance` for security updates through July 2026. [Migration details →](#breaking-changes-in-v20)

## Pinning guidance

For production use, pin to **immutable semver tags**:

- ✅ **Stable:** `heyvaldemar/aws-kubectl:2.0.0` — immutable on Docker Hub, never purged
- ⚠️ **Fragile:** `heyvaldemar/aws-kubectl:sha-1dfda81` — short-SHA tags are deleted after 90 days

If you pin by manifest digest (recommended for maximum supply chain integrity), make sure the digest is also referenced by a semver tag. Otherwise the digest may become unpullable once short-SHA cleanup runs. To resolve a tag to its current digest:

```bash
docker buildx imagetools inspect heyvaldemar/aws-kubectl:2.0.0 \
  --format '{{.Manifest.Digest}}'
```

## Features

- **Ubuntu 24.04** base for stability.
- **AWS CLI v2** for full AWS management.
- **kubectl** (pin a specific version or use the latest stable at build time).
- `jq`, `curl`, `unzip`, `envsubst`, and `ca-certificates` preinstalled.
- **Multi-stage build**: build-only intermediates (AWS CLI zip, extracted tree, kubectl archive) never enter the final image.
- **Checksum verification** for `kubectl` during build.
- **Multi-arch ready** (amd64/arm64) when built/pushed with `buildx`.
- **OCI labels** (`org.opencontainers.image.*`) on every published image.
- **Resolved kubectl version** written to `/etc/kube-version` inside the image.

> Default user is **non-root (UID 10001, GID 0)** as of v2.0. If you need root — e.g. to install additional `apt` packages at runtime — override with `--user 0:0`. See [Breaking Changes in v2.0](#breaking-changes-in-v20) for migration details.

### Typical use cases

- **GitHub Actions / GitLab CI pipelines** — one image instead of installing aws-cli + kubectl + jq separately in every job
- **EKS cluster operations** — AWS auth via aws-cli, then kubectl against the cluster, in a single container
- **OpenShift / restricted PodSecurityPolicy environments** — non-root default (UID 10001, GID 0) works out of the box
- **Multi-cluster scripting** — consistent tooling across dev/staging/prod kubeconfigs
- **Air-gapped or restricted networks** — pre-built image with checksum-verified binaries, no runtime `curl | bash`

## Supply chain

- Base image pinned by `sha256` digest (`ubuntu:24.04@sha256:…`). Dependabot's `docker` ecosystem bumps the digest weekly.
- Multi-stage `Dockerfile` keeps build-only intermediate artefacts (the downloaded AWS CLI archive, extracted tree, kubectl tarball, and checksum file) out of the published image.
- `kubectl` binaries are verified against the upstream `sha256` checksum published at `dl.k8s.io` during build.
- Weekly scheduled rebuilds pick up Ubuntu base-image security updates (`cron: "0 6 * * 1"`).
- CI lints the Dockerfile with `hadolint` and shell scripts with `shellcheck` before any build runs.
- All third-party GitHub Actions are pinned to a commit SHA with a version comment.
- Build arguments `VCS_REF` and `BUILD_DATE` are stamped into `org.opencontainers.image.revision` and `org.opencontainers.image.created`, and the resolved kubectl release is exposed via `io.heyvaldemar.kubectl.version` and `/etc/kube-version`.
- Every published digest is **cosign-signed** via Sigstore keyless OIDC using the GitHub Actions identity for this repository.
- **SBOM** (SPDX, generated by BuildKit) and **SLSA build provenance** (`provenance: mode=max`) are attached to every published image.
- **GitHub native build provenance** is attested via `actions/attest-build-provenance` and pushed to the registry alongside the image.
- **Trivy** scans the published image on every push; CRITICAL and HIGH fixable findings are uploaded as SARIF to the repository's GitHub Security tab.

### Verifying signatures

```bash
cosign verify heyvaldemar/aws-kubectl:latest \
  --certificate-identity-regexp "https://github.com/heyvaldemar/aws-kubectl-docker/.*" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```

## Tag management

Tags fall into four categories:

- **Semver releases** (`:2.0.0`, `:2.0`, `:2`, `:v2.0.0`) — immutable, kept forever. Recommended for production pins.
- **Floating channels** (`:latest`, `:edge`, `:v1-maintenance`) — updated on every main build; kept forever.
- **Kubernetes-version pin** (`:kube-v1.35.4`) — tracks the kubectl release packaged into the image. Kept forever.
- **Short-SHA builds** (`:sha-<7char>`) — produced by CI for every commit to main. Retained for 90 days, then automatically deleted by the `Docker Hub Tag Cleanup` workflow.

Cosign signatures (`:sha256-<digest>.sig`) are managed by Sigstore and are not deleted.

## Breaking Changes in v2.0

Starting with **v2.0.0**, this image runs as a **non-root user (UID 10001, GID 0)**
by default. This aligns with modern container security best practices and is
required for compatibility with OpenShift, restricted Kubernetes PodSecurityPolicy
profiles, and enterprise security scanners.

### For most users: no changes needed

If you use this image for one-off CI commands (`aws s3 sync`, `kubectl apply`),
v2.0 works identically to v1.x.

### For users mounting volumes

If you mount a host directory or Kubernetes PVC, you may need to adjust file
ownership or run the container with a matching UID:

**Docker:**

```bash
docker run --rm -v "$PWD:/home/app" --user "$(id -u):0" \
  heyvaldemar/aws-kubectl:latest aws s3 ls
```

**Kubernetes:**

```yaml
spec:
  securityContext:
    runAsUser: 10001
    runAsGroup: 0
    fsGroup: 0
```

### Staying on v1.x

If v2.0 breaks your workflow and you need time to migrate, pin to the v1
maintenance track:

```bash
docker pull heyvaldemar/aws-kubectl:v1-maintenance
```

The `v1-maintenance` tag will receive security updates through **July 20, 2026**,
after which it will be frozen.

## Mounting credentials

- `~/.aws` – AWS credentials/config (`credentials`, `config`). Mount to `/home/app/.aws` inside the container.
- `~/.kube` – kubeconfig(s). Mount to `/home/app/.kube` inside the container.

> The container's default user is UID 10001 with `HOME=/home/app`. Pass `--user "$(id -u):0"` when mounting host files so the container can read them.

## Running the Container

Interactive shell with both configs (mount under `/home/app` — the non-root user's `HOME` — and match your host UID so the container can read the mounted files):

```bash
docker run -it \
  --user "$(id -u):0" \
  -v ~/.aws:/home/app/.aws \
  -v ~/.kube:/home/app/.kube \
  heyvaldemar/aws-kubectl bash
```

If you pulled an **amd64-only** tag on an ARM/M-series Mac:

```bash
docker run --platform linux/amd64 -it \
  --user "$(id -u):0" \
  -v ~/.aws:/home/app/.aws \
  -v ~/.kube:/home/app/.kube \
  heyvaldemar/aws-kubectl bash
```

### Execute commands directly (no shell)

```bash
# List S3 buckets
docker run --rm \
  --user "$(id -u):0" \
  -v ~/.aws:/home/app/.aws \
  heyvaldemar/aws-kubectl aws s3 ls

# Get Kubernetes nodes
docker run --rm \
  --user "$(id -u):0" \
  -v ~/.kube:/home/app/.kube \
  heyvaldemar/aws-kubectl kubectl get nodes
```

## Build Instructions

The `Dockerfile` accepts the following build arguments:

| ARG          | Default    | Purpose                                                                  |
|--------------|------------|--------------------------------------------------------------------------|
| `KUBE_VERSION` | `latest` | Pin a specific `kubectl` release (e.g. `v1.30.6`). `latest` fetches the current stable from `dl.k8s.io`. |
| `VCS_REF`      | `unknown`| Commit SHA, stamped into `org.opencontainers.image.revision`.             |
| `BUILD_DATE`   | `unknown`| ISO-8601 build timestamp, stamped into `org.opencontainers.image.created`.|
| `TARGETARCH`   | auto     | Target architecture (`amd64`/`arm64`). Supplied automatically by `buildx`.|

### Local single-arch (dev)

```bash
# From the folder with the Dockerfile
docker build -t aws-kubectl:local .
```

### Pin a specific kubectl

```bash
docker build --build-arg KUBE_VERSION=v1.30.6 \
  -t aws-kubectl:local .
```

If `KUBE_VERSION` is omitted, the build fetches the **latest stable** from `dl.k8s.io`.

### Stamp revision and build date (recommended for release builds)

```bash
docker build \
  --build-arg KUBE_VERSION=v1.30.6 \
  --build-arg VCS_REF="$(git rev-parse HEAD)" \
  --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  -t aws-kubectl:local .
```

### Multi-arch build & push (amd64 + arm64)

```bash
docker buildx create --name x --use || docker buildx use x

# Generic tag (no OS name in the tag)
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg VCS_REF="$(git rev-parse HEAD)" \
  --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  -t heyvaldemar/aws-kubectl:latest \
  --push .

# Or pin kubectl in a tag users can reason about
KUBE_VERSION=v1.30.6
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg KUBE_VERSION=$KUBE_VERSION \
  --build-arg VCS_REF="$(git rev-parse HEAD)" \
  --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  -t heyvaldemar/aws-kubectl:kube-$KUBE_VERSION \
  --push .
```

Verify:

```bash
docker buildx imagetools inspect heyvaldemar/aws-kubectl:latest
```

> Optional supply-chain flags (if you want SBOM/provenance):
> `--sbom=true --provenance=true`

## Local Build & Test (using the repo script)

This repo includes `scripts/smoke-test.sh` to validate the tools in the image.

1. **Build locally**

```bash
docker build -t aws-kubectl:local .
```

2. **Run the smoke test**

```bash
chmod +x scripts/smoke-test.sh
./scripts/smoke-test.sh                # defaults to aws-kubectl:local
./scripts/smoke-test.sh your/tag:dev   # test any tag you pass
```

The script checks:

- OS/arch
- Versions: AWS CLI, kubectl (client), jq, envsubst, curl, unzip
- That `/etc/kube-version` matches `kubectl version --client`
- Binary locations & CA bundle
- HTTPS reachability (header-only)
- (Optional) AWS STS + `kubectl` cluster calls if you mount `~/.aws` / `~/.kube`

<details>
<summary>Quick verification one-liners (click to expand)</summary>

```bash
IMG=aws-kubectl:local

# OS/arch
docker run --rm $IMG sh -lc 'uname -a; echo -n "Arch: "; uname -m'

# Core tools & versions
docker run --rm $IMG aws --version
docker run --rm $IMG kubectl version --client --output=yaml
docker run --rm $IMG jq --version
docker run --rm $IMG envsubst --version
docker run --rm $IMG sh -c 'curl --version | head -n1'
docker run --rm $IMG sh -c 'unzip -v | head -n2'

# Resolved kubectl release stamped at build time
docker run --rm $IMG cat /etc/kube-version

# Binaries present where expected
docker run --rm $IMG sh -c 'ls -l /usr/local/bin/kubectl; for b in aws jq envsubst curl unzip; do command -v "$b"; done'

# CA bundle present + HTTPS sanity
docker run --rm $IMG sh -c 'ls -lh /etc/ssl/certs/ca-certificates.crt'
docker run --rm $IMG sh -c 'curl -fsSI -o /dev/null -w "HTTPS OK (%{http_code})\n" https://kubernetes.io'
```

### Optional “real” checks (with mounted config)

```bash
# AWS identity (requires valid creds)
docker run --rm --user "$(id -u):0" \
  -v ~/.aws:/home/app/.aws \
  aws-kubectl:local aws sts get-caller-identity

# Current k8s context & nodes (requires valid kubeconfig)
docker run --rm --user "$(id -u):0" \
  -v ~/.kube:/home/app/.kube \
  aws-kubectl:local kubectl config current-context

docker run --rm --user "$(id -u):0" \
  -v ~/.kube:/home/app/.kube \
  aws-kubectl:local kubectl get nodes -o wide
```

</details>

## Security Notes

- Runs as **non-root** by default (UID 10001, GID 0) as of v2.0.
- `kubectl` binaries are **checksum-verified** during build.
- APT is minimal (`--no-install-recommends`) and lists are cleaned.
- Pin `KUBE_VERSION` in CI for reproducibility.

## Run as root (override)

If a specific workflow requires root inside the container (e.g. installing additional `apt` packages at runtime, or restoring pre-v2.0 behaviour), override the user:

```bash
docker run --rm --user 0:0 heyvaldemar/aws-kubectl bash
```

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** — Docker Captain · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
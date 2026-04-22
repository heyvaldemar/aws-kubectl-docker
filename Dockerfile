# syntax=docker/dockerfile:1.7

# ──────────────────────────────────────────────────────────────────────────────
# Stage 1: builder
#   Downloads, verifies, and unpacks AWS CLI v2 and kubectl.
#   Build-only tooling (unzip) lives here and never enters the final image.
# ──────────────────────────────────────────────────────────────────────────────
# Digest pinned; Dependabot docker ecosystem will bump this weekly.
FROM ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b AS builder

ARG TARGETARCH
ARG KUBE_VERSION=latest
ARG DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      unzip \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Resolve architecture (fallback if TARGETARCH not provided).
# KARCH is for kubectl (amd64|arm64); AWS_ARCH is for AWS CLI (x86_64|aarch64).
# Resolved kubectl version is written to /build/kube-version for the final stage.
RUN KARCH="${TARGETARCH:-$(dpkg --print-architecture)}" \
 && case "$KARCH" in \
      amd64) AWS_ARCH="x86_64" ;; \
      arm64) AWS_ARCH="aarch64" ;; \
      *) echo "Unsupported architecture: $KARCH" >&2; exit 1 ;; \
    esac \
 # ----- AWS CLI v2 -----
 && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o awscliv2.zip \
 && unzip -q awscliv2.zip \
 && ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli \
 && rm -rf awscliv2.zip aws \
 # ----- kubectl (versioned + checksum verification) -----
 && if [[ "${KUBE_VERSION}" == "latest" ]]; then \
        KUBE_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"; \
    fi \
 && curl -fsSLo kubectl "https://dl.k8s.io/release/${KUBE_VERSION}/bin/linux/${KARCH}/kubectl" \
 && curl -fsSLo kubectl.sha256 "https://dl.k8s.io/release/${KUBE_VERSION}/bin/linux/${KARCH}/kubectl.sha256" \
 && echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c - \
 && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl \
 && rm -f kubectl kubectl.sha256 \
 && printf '%s\n' "$KUBE_VERSION" > /build/kube-version

# ──────────────────────────────────────────────────────────────────────────────
# Stage 2: final
#   Runtime toolchain: aws, kubectl, jq, envsubst, curl, unzip, ca-certificates.
#   `unzip` is retained in the final image for backwards compatibility with
#   users of heyvaldemar/aws-kubectl:latest (500K+ pulls) who rely on it for
#   ad-hoc zip extraction in CI/CD pipelines.
#   As of v2.0 the image runs as non-root (UID 10001, GID 0). Users who need
#   root can override with `--user 0:0`. See README "Breaking Changes in v2.0".
# ──────────────────────────────────────────────────────────────────────────────
FROM ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b AS final

ARG KUBE_VERSION=latest
ARG VCS_REF=unknown
ARG BUILD_DATE=unknown
ARG TARGETARCH
ARG DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      jq \
      gettext-base \
      unzip \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/aws-cli /usr/local/aws-cli
COPY --from=builder /usr/local/bin/kubectl /usr/local/bin/kubectl
COPY --from=builder /build/kube-version /etc/kube-version

# Recreate the `aws` and `aws_completer` entry-point symlinks. The aws-cli v2
# binary uses a relative RPATH to find its bundled libpython, so it must run
# from inside /usr/local/aws-cli/v2/current/ — COPY would dereference the
# original /usr/local/bin/aws symlink and break the binary.
RUN ln -s /usr/local/aws-cli/v2/current/bin/aws /usr/local/bin/aws \
 && ln -s /usr/local/aws-cli/v2/current/bin/aws_completer /usr/local/bin/aws_completer

LABEL org.opencontainers.image.title="aws-kubectl" \
      org.opencontainers.image.description="Ubuntu 24.04 image bundling AWS CLI v2, kubectl, jq, envsubst, curl and ca-certificates for CI/CD and local tooling." \
      org.opencontainers.image.authors="Vladimir Mikhalev <v@valdemar.ai>" \
      org.opencontainers.image.vendor="heyvaldemar" \
      org.opencontainers.image.source="https://github.com/heyvaldemar/aws-kubectl-docker" \
      org.opencontainers.image.documentation="https://github.com/heyvaldemar/aws-kubectl-docker#readme" \
      org.opencontainers.image.url="https://hub.docker.com/r/heyvaldemar/aws-kubectl" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      io.heyvaldemar.kubectl.version="${KUBE_VERSION}"

# Create non-root user with UID 10001 and primary GID 0 (root group).
# GID 0 is OpenShift SCC compatible: OpenShift assigns random UIDs at runtime
# but always uses GID 0 for file ownership. Files owned by root group remain
# readable/writable. Also works on vanilla Kubernetes, Docker Desktop, and CI.
# UID 10001 is outside the standard user range (1000-9999) to avoid host UID
# collisions on developer machines running Ubuntu.
RUN useradd --system --uid 10001 --gid 0 \
      --home-dir /home/app --shell /sbin/nologin \
      --comment "aws-kubectl runtime user" app \
 && mkdir -p /home/app \
 && chown -R 10001:0 /home/app \
 && chmod -R g=u /home/app

# HOME must be set explicitly for kubectl/aws CLI cache paths to work
# (~/.kube/cache, ~/.aws/cli/cache, ~/.aws/sso/cache).
ENV HOME=/home/app

WORKDIR /home/app

USER 10001:0

CMD ["bash"]

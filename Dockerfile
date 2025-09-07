# Use Ubuntu 24.04 as the base image
FROM ubuntu:24.04

# Build-time settings
ARG TARGETARCH
ARG KUBE_VERSION=latest
ARG DEBIAN_FRONTEND=noninteractive

# (Optional) helpful shell defaults
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install minimal dependencies in a single layer
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      unzip \
      jq \
      gettext-base \
 && rm -rf /var/lib/apt/lists/*

# Resolve architecture (fallback if TARGETARCH not provided)
# KARCH is for kubectl (amd64|arm64); AWS_ARCH is for AWS CLI (x86_64|aarch64)
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
 && rm -f kubectl kubectl.sha256

# Default command
CMD ["bash"]

# Use Ubuntu 24.04 as the base image
FROM ubuntu:24.04

# Set build-time architecture variable
ARG TARGETARCH

# Set environment variables to non-interactive (this prevents some prompts)
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Download AWS CLI v2 for the correct architecture
RUN case "${TARGETARCH}" in \
        "amd64") ARCH="x86_64" ;; \
        "arm64") ARCH="aarch64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o "awscliv2.zip"

# Unzip AWS CLI v2
RUN unzip awscliv2.zip

# Install kubectl for the correct architecture
ARG KUBE_VERSION=latest
RUN if [ "${KUBE_VERSION}" = "latest" ]; then \
        KUBE_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt); \
    fi && \
    curl -LO "https://dl.k8s.io/release/${KUBE_VERSION}/bin/linux/${TARGETARCH}/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Cleanup
RUN apt-get update && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set default command
CMD ["bash"]

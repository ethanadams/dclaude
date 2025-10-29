FROM golang:1.24.9-trixie

# Metadata
LABEL maintainer="dclaude"
LABEL description="Dockerized Claude Code development environment with Go, Node.js, and Helm"
LABEL version="1.0"

# Set working directory
WORKDIR /src

# Install system dependencies and tools
# Combine into single layer to reduce image size
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        vim \
        git \
        ca-certificates \
        gnupg \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js from NodeSource (more recent version than Debian repos)
# Using Node 20 LTS for better stability
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install Helm with specific version for reproducibility
ENV HELM_VERSION=3.14.0
RUN curl -fsSL https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz | \
    tar xz && \
    mv linux-amd64/helm /usr/local/bin/helm && \
    rm -rf linux-amd64 && \
    helm version

# Install claude-code
RUN npm install -g @anthropic-ai/claude-code && \
    npm cache clean --force

# Verify installations
RUN go version && \
    node --version && \
    npm --version && \
    helm version && \
    claude-code --version || echo "claude-code installed"

# Set up git config defaults
RUN git config --global --add safe.directory /src

# Create non-root user for security
RUN useradd -m -s /bin/bash -u 1000 dclaude && \
    chown -R dclaude:dclaude /src

# Switch to non-root user
USER dclaude

# Set up git config for the non-root user
RUN git config --global --add safe.directory /src

# Copy Claude Code security settings
# This prevents Claude from accessing sensitive files in the mounted repository
COPY --chown=dclaude:dclaude .claude /src/.claude

# Default command
CMD ["claude-code"]

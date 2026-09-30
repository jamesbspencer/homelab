# Hermes Terminal Sandbox Image
# Base image: Ubuntu 26.04 LTS
FROM ubuntu:26.04

LABEL maintainer="Spencer Homelab" \
      description="Custom sandbox execution image for Hermes Agent terminal and code execution tools" \
      version="1.0.0"

ENV DEBIAN_FRONTEND=noninteractive \
    TERM=xterm-256color \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    PNPM_HOME="/root/.local/share/pnpm" \
    PATH="/root/.local/bin:/root/.local/share/pnpm:$PATH"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 1. Install base utilities, compilers, networking tools, database clients, Python, and Node.js
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core utilities & text processing
    ca-certificates \
    curl \
    wget \
    gnupg \
    git \
    jq \
    ripgrep \
    fd-find \
    tree \
    tar \
    unzip \
    zip \
    bzip2 \
    xz-utils \
    file \
    less \
    nano \
    vim-tiny \
    # Build & compile essentials
    build-essential \
    make \
    pkg-config \
    # Networking, SSH & remote execution
    iputils-ping \
    dnsutils \
    netcat-openbsd \
    iproute2 \
    traceroute \
    whois \
    socat \
    openssh-client \
    sshpass \
    # Process & system inspection
    procps \
    htop \
    lsof \
    # Homelab database & cache clients
    postgresql-client \
    redis-tools \
    # Python 3 runtime and development libraries
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    # Node.js and npm runtimes
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# 2. Symlink fd-find as fd for convenience
RUN ln -s "$(which fdfind)" /usr/local/bin/fd || true

# 3. Install yq (portable YAML processor)
RUN ARCH="$(dpkg --print-architecture)" && \
    case "${ARCH}" in \
      amd64) YQ_ARCH="amd64" ;; \
      arm64) YQ_ARCH="arm64" ;; \
      *) YQ_ARCH="amd64" ;; \
    esac && \
    wget -qO /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${YQ_ARCH}" && \
    chmod +x /usr/local/bin/yq

# 4. Install uv (lightning-fast Python package manager)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# 5. Install Bitwarden Secrets Manager CLI (bws)
RUN curl -fsSL https://bws.bitwarden.com/install | sh && \
    if [ -f /root/.local/bin/bws ] && [ ! -f /usr/local/bin/bws ]; then \
      cp /root/.local/bin/bws /usr/local/bin/bws; \
    fi

# 6. Global Node.js package managers and developer toolchain
RUN npm install -g --no-fund --no-audit \
    pnpm \
    yarn \
    typescript \
    tsx \
    prettier \
    eslint

# 7. Common Python libraries for scripts, scraping, and data processing (via uv system install)
RUN rm -f /usr/lib/python*/EXTERNALLY-MANAGED && \
    /root/.local/bin/uv pip install --system --break-system-packages \
    requests \
    httpx \
    aiohttp \
    beautifulsoup4 \
    lxml \
    pydantic \
    pyyaml \
    jinja2 \
    python-dotenv \
    rich \
    click \
    typer \
    numpy \
    pandas

# Set default workspace directory matching Hermes sandbox tmpfs mount
WORKDIR /workspace

CMD ["/bin/bash"]

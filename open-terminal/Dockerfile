ARG OPEN_TERMINAL_VERSION=latest
ARG OPENBAO_VERSION=latest
ARG GITEA_CLI_VERSION=0.1.0
ARG TEA_VERSION=0.16.0
ARG GH_CLI_VERSION=2.103.3

FROM openbao/openbao:${OPENBAO_VERSION} AS openbao-bin

FROM ghcr.io/open-webui/open-terminal:${OPEN_TERMINAL_VERSION}

USER root

# 1. Install OpenBao CLI binary and compatibility aliases
COPY --from=openbao-bin /usr/bin/bao /usr/local/bin/bao
RUN chmod 755 /usr/local/bin/bao && \
    ln -sf /usr/local/bin/bao /usr/local/bin/openbao && \
    ln -sf /usr/local/bin/bao /usr/local/bin/vault

# 2. Install GitHub CLI (official upstream release)
ARG GH_CLI_VERSION
RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_CLI_VERSION}/gh_${GH_CLI_VERSION}_linux_amd64.deb" -o /tmp/gh.deb && \
    dpkg -i /tmp/gh.deb && \
    rm -f /tmp/gh.deb

# 3. Install Gitea CLI (modern 'gt' and classic 'tea')
ARG GITEA_CLI_VERSION
ARG TEA_VERSION
RUN curl -fsSL "https://gitea.com/gitea/cli/releases/download/v${GITEA_CLI_VERSION}/gitea-cli-${GITEA_CLI_VERSION}-linux-amd64" -o /usr/local/bin/gt && \
    chmod 755 /usr/local/bin/gt && \
    ln -sf /usr/local/bin/gt /usr/local/bin/gitea-cli && \
    curl -fsSL "https://gitea.com/gitea/tea/releases/download/v${TEA_VERSION}/tea-${TEA_VERSION}-linux-amd64" -o /usr/local/bin/tea && \
    chmod 755 /usr/local/bin/tea

# 4. Generate & configure bash completions
RUN mkdir -p /usr/share/bash-completion/completions && \
    /usr/local/bin/gt completion bash > /usr/share/bash-completion/completions/gt && \
    /usr/local/bin/tea completion bash > /usr/share/bash-completion/completions/tea && \
    echo 'complete -C /usr/local/bin/bao bao openbao vault' >> /etc/bash.bashrc && \
    echo 'complete -C /usr/local/bin/bao bao openbao vault' >> /etc/skel/.bashrc

# 5. Default environment variables for homelab services
RUN echo 'export BAO_ADDR="${BAO_ADDR:-http://openbao:8200}"' > /etc/profile.d/homelab.sh && \
    echo 'export VAULT_ADDR="${VAULT_ADDR:-http://openbao:8200}"' >> /etc/profile.d/homelab.sh && \
    echo 'export GITEA_INSTANCE_URL="${GITEA_INSTANCE_URL:-http://gitea:3000}"' >> /etc/profile.d/homelab.sh && \
    echo 'export GITEA_SERVER_URL="${GITEA_SERVER_URL:-http://gitea:3000}"' >> /etc/profile.d/homelab.sh && \
    chmod 644 /etc/profile.d/homelab.sh

USER user

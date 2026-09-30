# Hermes Custom Terminal Sandbox Image

This directory contains the [`Dockerfile`](file:///data/homelab/hermes-terminal-image/Dockerfile) and instructions for building a custom Docker execution sandbox image used by **Nous Research Hermes Agent** (`terminal`, `execute_code`, and `process` tools).

---

## 🎯 Purpose

By default, Hermes Agent uses `nikolaik/python-nodejs:python3.11-nodejs20` for sandbox container execution. While functional, it lacks many common homelab CLI utilities, database clients, and developer tools, requiring the agent to repeatedly `apt-get install` or `pip install` dependencies during runs.

This custom image builds on **Ubuntu 26.04 LTS** and pre-bakes the most frequently needed tools into a ready-to-run container:

* **Base OS**: Ubuntu 26.04 LTS (`ubuntu:26.04`).
* **Dual Runtimes**: Modern Python 3 and Node.js runtimes.
* **Bitwarden Secrets Manager CLI**: Bitwarden Secrets Manager CLI (`bws`) for machine account access token injection and project secret automation.
* **Modern Package Managers**: `uv` (fast Python toolchain), `pnpm`, `yarn`, and `pip`.
* **TypeScript Tooling**: Global `typescript`, `tsx`, `prettier`, and `eslint`.
* **Homelab Database Clients**: `postgresql-client` (`psql`) and `redis-tools` (`redis-cli`).
* **CLI & Text Processing**: `git`, `jq`, `yq`, `ripgrep` (`rg`), `fd-find` (`fd`), `tree`, `tar`, `unzip`, `file`.
* **Networking & Remote Access**: `curl`, `wget`, `iputils-ping`, `dnsutils` (`dig`, `nslookup`), `netcat-openbsd`, `socat`, `traceroute`, `ssh` (`openssh-client`), and `sshpass` (non-interactive SSH password automation).
* **Data & Scripting Libraries**: `requests`, `httpx`, `aiohttp`, `beautifulsoup4`, `pydantic`, `pyyaml`, `jinja2`, `rich`, `click`, `numpy`, `pandas`.

---

## 🔨 Building the Image

From this directory (`/data/homelab/hermes-terminal-image`), build the image with a local tag:

```bash
docker build -t hermes-terminal:latest .
```

To include versioning:

```bash
docker build -t hermes-terminal:1.0.0 -t hermes-terminal:latest .
```

---

## ⚙️ Configuration in Hermes

Once built, you can configure Hermes Agent to use `hermes-terminal:latest` using either of the following methods:

### Option A: Via `.env` (Recommended)

Add or update the following variable in [`/data/homelab/.env`](file:///data/homelab/.env):

```bash
HERMES_TERMINAL_DOCKER_IMAGE=hermes-terminal:latest
```

Then recreate the Hermes container to load the environment change:

```bash
docker compose up -d hermes
```

### Option B: Via `hermes/config.yaml`

Update the `terminal.docker_image` setting in [`/data/homelab/hermes/config.yaml`](file:///data/homelab/hermes/config.yaml):

```yaml
terminal:
  backend: docker
  timeout: 180
  docker_image: hermes-terminal:latest
  lifetime_seconds: 300
```

---

## 🧪 Testing & Verification

### 1. Test the Image Directly

Verify that the image builds cleanly and has all tools installed:

```bash
docker run --rm -it hermes-terminal:latest bash -c "python3 --version && node -v && uv --version && bws --version && psql --version && redis-cli --version && jq --version && yq --version && rg --version && fd --version"
```

Expected output:
```text
Python 3.14.x
v22.x.x
uv 0.12.x
bws 2.1.x
psql (PostgreSQL) 18.x
redis-cli 8.x
jq-1.8.x
yq version v4.x.x
ripgrep 15.x.x
fdfind 10.x.x
```

### 2. Verify in Hermes

In the Hermes Web Dashboard or via the MCP server, run a terminal command such as:

```bash
which bws uv psql redis-cli jq yq rg
```

All binaries should resolve directly without installation delays.

---

## 🔐 Bitwarden Secrets Manager CLI (`bws`) Usage in Sandbox

The Bitwarden Secrets Manager CLI allows Hermes Agent to retrieve secrets directly via machine account access tokens or inject secrets into commands:

```bash
# 1. Authenticate using Machine Account Access Token
export BWS_ACCESS_TOKEN="0.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.xxxxxxxxxxxxxxxxxxxxxxxxxxxx:xxxxxxxxxxxxxxxxxxxx=="

# 2. List projects and secrets
bws project list
bws secret list

# 3. Retrieve a specific secret by ID
bws secret get <SECRET_UUID>

# 4. Inject secrets dynamically into commands without persisting on disk
bws run -- 'env | grep DATABASE_URL'
bws run -- 'python3 script.py'
```

---

## 🛠️ Customization

To add additional packages or libraries:

1. **Apt Packages**: Add system packages to the `apt-get install` list in [`Dockerfile`](file:///data/homelab/hermes-terminal-image/Dockerfile).
2. **Python Packages**: Add packages to the `pip install` block or install them with `uv pip install --system`.
3. **Node Packages**: Add global npm packages to the `npm install -g` block.
4. Rebuild the image: `docker build -t hermes-terminal:latest .`.

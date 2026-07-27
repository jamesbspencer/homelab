# AGENTS.md

Instructions and guidelines for AI Coding Agents interacting with the `homelab` repository.

## Repository Overview

This repository (`homelab`) contains GitOps configurations, shell scripts, and infrastructure-as-code automation for managing homelab services on Ubuntu servers.

## Guidelines for AI Agents

### 1. Shell Scripting Standards (`*.sh`)

When creating or modifying bash scripts:

- **Header & Flags**: Always start with `#!/usr/bin/env bash` and set strict error handling flags: `set -euo pipefail`.
- **Privilege Checks**: Scripts modifying system configuration must verify `root` or `sudo` execution (`$EUID -eq 0`) and provide informative error messages.
- **Idempotency**: All operations (package installation, directory creation, config file edits) should be safe to run multiple times without unintended side effects.
- **Error & Status Output**: Use consistent, color-coded logging functions (`log_info`, `log_success`, `log_warn`, `log_error`).
- **Ubuntu Compatibility**: Target Ubuntu Server LTS distributions. Use non-interactive flags for package managers (e.g., `apt-get update -qq`, `apt-get install -y -qq`).
- **Help Options**: Every script should support `-h` / `--help` flags displaying usage syntax and examples.

### 2. File Organization

```text
.
├── AGENTS.md            # Guidelines for AI coding agents
├── README.md            # General documentation and script usage guide
├── homepage/
│   ├── config/          # Homepage configuration files
│   └── docker-compose.yml # Homepage dashboard compose file
├── install-docker.sh    # Docker Engine installer script for Ubuntu
├── portainer/
│   └── docker-compose.yml # Portainer CE compose file
└── traefik/
    └── docker-compose.yml # Traefik v3 reverse proxy compose file
```


- Keep root scripts well documented and executable (`chmod +x`).
- Put modular automation scripts or manifests into clear subdirectories (e.g., `scripts/`, `manifests/`, `ansible/`) as the repository grows.

### 3. Documentation Requirements

- **Sync README.md**: Whenever a script is created, modified, or given new CLI arguments, update `README.md` immediately with the updated parameters and usage examples.
- **Inline Comments**: Provide concise inline comments for non-obvious logic, complex awk/sed commands, or systemd manipulations.

### 4. Verification & Testing

- Before completing a task involving bash scripts, test syntax validity using:

  ```bash
  bash -n <script_name>.sh
  ```

- Verify scripts are executable (`chmod +x`).

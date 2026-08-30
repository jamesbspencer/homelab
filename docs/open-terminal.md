# Open Terminal

Open Terminal provides a secure, sandboxed shell execution environment for Open WebUI, allowing AI models and users to execute code and terminal commands safely.

---

## 🎯 Overview & Architecture

* **Role**: Sandboxed workspace execution environment for Open WebUI code interpreter tasks.
* **Container Name**: `open-terminal`
* **Image**: `ghcr.io/open-webui/open-terminal:${TERMINAL_DOCKER_TAG-main}`
* **Network**: `ai` (Internal AI network)
* **Internal Port**: `8000`

---

## 🛡️ Resource Constraints & Sandboxing

To prevent resource exhaustion from automated scripts or model commands, Open Terminal is hard-limited in Docker Compose:

```yaml
deploy:
  resources:
    limits:
      cpus: '2'
      memory: 2048M
    reservations:
      cpus: '0.25'
      memory: 512M
```

---

## ⚙️ Configuration & Environment

| Variable | Source | Purpose |
|---|---|---|
| `OPEN_TERMINAL_API_KEY` | `${OPEN_TERMINAL_API_KEY}` in `.env` | Authentication key between Open WebUI and Open Terminal |

---

## 📁 Mounted Volumes

| Host Path | Container Path | Purpose |
|---|---|---|
| `./open-terminal` | `/home/user` | User home directory and scratch workspace for command execution |

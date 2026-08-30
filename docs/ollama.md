# Ollama LLM Runtime

Ollama provides local large language model inference with NVIDIA GPU acceleration, exposing OpenAI-compatible and native Ollama API endpoints.

---

## 🎯 Overview & Architecture

* **Role**: Local LLM execution engine serving Open WebUI, Hermes Agent, and terminal tools.
* **Container Name**: `ollama`
* **Image**: `ollama/ollama`
* **Network**: `ai` (Internal AI communication network)
* **Bound Host Ports**: `11434:11434`
* **API Endpoints**:
  * Native API: `http://ollama:11434/api`
  * OpenAI-Compatible API: `http://ollama:11434/v1`

---

## 🚀 GPU Hardware Acceleration

The service passes through host NVIDIA GPUs using Docker Compose reservations:

```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: all
          capabilities: [gpu]
```

> [!IMPORTANT]
> Requires the **NVIDIA Container Toolkit** installed and configured on the host machine (`nvidia-ctk runtime configure --runtime=docker`).

---

## 📁 Mounted Volumes

| Host Path | Container Path | Purpose |
|---|---|---|
| `./ollama` | `/root/.ollama` | Persists downloaded model weights and manifests |

---

## 🛠️ Management & Useful Commands

### Pulling a Model
```bash
docker compose exec ollama ollama pull qwen2.5:14b
docker compose exec ollama ollama pull nomic-embed-text

```

### Listing Installed Models
```bash
docker compose exec ollama ollama list
```

### Checking GPU Utilization
```bash
nvidia-smi
docker compose exec ollama ollama ps
```

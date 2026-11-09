# llama.cpp (llama-server) - Hybrid Mixture-of-Experts (MoE) Inference Engine

High-performance local Mixture-of-Experts (MoE) and dense LLM inference using **`llama.cpp` (`llama-server`)** with GPU hardware acceleration, expert offloading (`--n-cpu-moe`), and dedicated zero-VRAM text embeddings (`llama-embed`).

---

## 🎯 Overview & Architecture

* **Role**: Primary local LLM inference engine executing 30B–35B MoE models directly behind Open WebUI and local tooling.
* **Services**:
  * **`llama-server`**: Multi-model MoE router engine with NVIDIA GPU acceleration, CPU expert offloading (`--n-cpu-moe`), and dynamic LRU model switching via `--models-preset` (`:8080`).
  * **`llama-embed`**: Companion zero-VRAM CPU embedding service (`:8081`) running `nomic-embed-text`.
* **Container Image**: `ghcr.io/ggml-org/llama.cpp:server-cuda`
* **Network**: `ai` (Internal AI communication network; no host ports exposed).
* **Decoupled Architecture**: Open WebUI communicates directly with `llama-server` and `llama-embed`, completely bypassing proxy and gateway layers for minimal inference latency.

```mermaid
graph TD
    Traefik[Traefik Proxy :443] -->|https://chat.spencer.lan| OpenWebUI[Open WebUI :8080]
    Traefik -.->|https://llm.spencer.lan| OmniRoute[OmniRoute Standalone :20128]

    subgraph Direct Inference Plane
        OpenWebUI -->|Direct Chat :8080/v1| LlamaServer["llama-server (:8080 Router Mode)"]
        OpenWebUI -->|Direct Embeddings :8081/v1| LlamaEmbed["llama-embed (:8081)"]
    end

    subgraph Llama.cpp Router Presets
        LlamaServer -.->|Preset: qwen3.6-35b-a3b| M1["Qwen3.6-35B-A3B-IQ4_XS (--n-cpu-moe 20)"]
        LlamaServer -.->|Preset: qwen3-coder-30b-a3b| M2["Qwen3-Coder-30B-A3B-Instruct-IQ4_XS (--n-cpu-moe 32)"]
    end

    subgraph Hardware Memory Hierarchy
        LlamaServer -->|Attention, Shared Experts, Norms, KV Cache| GPU["RTX 3060 (12 GB VRAM)"]
        LlamaServer -->|Routed Inactive Experts| RAM["Intel Xeon W-2145 + 61 GiB RAM (AVX-512)"]
        LlamaEmbed -->|nomic-embed-text (~250 MB)| RAM
    end
```

---

## 🚀 GPU & Memory Hierarchy Math (RTX 3060 + Xeon W-2145)

Spencer's homelab executes MoE models across a single **NVIDIA GeForce RTX 3060 (12 GB VRAM)** and **61 GiB DDR4 RAM** with dynamic LRU memory eviction (`--models-max 1`):

### Model 1: Qwen 3.6 35B A3B (`qwen3.6-35b-a3b`)

| Component | Parameter Count | Quantization | Resident Placement | Memory Footprint |
|---|---|---|---|---|
| **Embeddings & Shared Tensors** | ~1.5B dense | Q8_0 / Q4_K_M | **GPU VRAM** | ~1.8 GiB |
| **Attention Layers & Norms** | 40 layers | Q4_K / Q8_0 | **GPU VRAM** | ~2.5 GiB |
| **Shared Experts** | 1 shared | Q4_K_M | **GPU VRAM** | ~1.2 GiB |
| **GPU Routed Experts** | 20 layers | IQ4_XS | **GPU VRAM** | ~3.8 GiB |
| **KV Cache (64k context)** | Unified slots | Q8_0 (`--cache-type-k/v q8_0`, `--kv-unified-per-slot 65536`) | **GPU VRAM** | ~2.3 GiB |
| **Total VRAM Consumption** | — | — | **RTX 3060** | **~11.6 GiB / 12 GiB** |
| **Offloaded CPU Experts (`--n-cpu-moe 20`)** | 20 layers | IQ4_XS | **System RAM** | **~8.9 GiB / 61 GiB** |
| **Embedding Engine (`llama-embed`)** | 137M | F16 / Q4_K | **System RAM** | **~0.27 GiB (0 MB VRAM)** |

### Model 2: Qwen 3 Coder 30B A3B (`qwen3-coder-30b-a3b`)

| Component | Parameter Count | Quantization | Resident Placement | Memory Footprint |
|---|---|---|---|---|
| **Embeddings & Shared Tensors** | ~1.2B dense | Q8_0 / Q4_K_M | **GPU VRAM** | ~1.5 GiB |
| **Attention Layers & Norms** | 48 layers | Q4_K / Q8_0 | **GPU VRAM** | ~2.6 GiB |
| **Shared Experts** | 1 shared | Q4_K_M | **GPU VRAM** | ~1.0 GiB |
| **GPU Routed Experts** | 16 layers | IQ4_XS | **GPU VRAM** | ~2.2 GiB |
| **KV Cache (64k context)** | Unified slots | Q4_0 (`--cache-type-k/v q4_0`, `--kv-unified-per-slot 65536`) | **GPU VRAM** | ~1.6 GiB |
| **Total VRAM Consumption** | — | — | **RTX 3060** | **~7.8 GiB / 12 GiB** |
| **Offloaded CPU Experts (`--n-cpu-moe 32`)** | 32 layers | IQ4_XS | **System RAM** | **~8.6 GiB / 61 GiB** |
| **Embedding Engine (`llama-embed`)** | 137M | F16 / Q4_K | **System RAM** | **~0.27 GiB (0 MB VRAM)** |

---

## ⚙️ How `--n-cpu-moe` Works

* **Mechanism**: `--n-cpu-moe 20` instructs `llama-server` to keep the routed expert weights of the first 20 layers resident in system DDR4 RAM while placing all attention mechanisms, shared experts, and remaining layer experts onto the GPU.
* **PCIe Efficiency**: Because only 3 billion parameters activate per token in a 35B-A3B MoE architecture, only tiny activation vectors pass across the PCIe bus.
* **AVX-512 Computation**: The Intel Xeon W-2145 CPU processes CPU-side expert activations with 8 worker threads (`--threads 8`) using 512-bit vector registers.
* **Throughput**: Achieves **~47–55 tokens/sec** predicted generation and **~60 tokens/sec** prompt processing on real-world queries.

---

## 📁 Mounted Volumes & Models

| Host Path | Container Path | Purpose |
|---|---|---|
| `./llama/models` | `/models:ro` | Stores GGUF model weights (`Qwen3.6-35B-A3B-IQ4_XS.gguf`, `Qwen3-Coder-30B-A3B-Instruct-IQ4_XS.gguf`, `nomic-embed-text.gguf`) |
| `./llama/presets.ini` | `/presets.ini:ro` | Router configuration defining model presets, GPU offload layers, and `--n-cpu-moe` parameters |

---

## 🛠️ Management & Useful Commands

### Checking Service Health & Endpoints
```bash
# MoE router server health
docker compose exec llama-server curl -s http://localhost:8080/health

# Embedding server health
docker compose exec llama-embed curl -s http://localhost:8081/health

# List active models & router presets
docker compose exec open-webui curl -s http://llama-server:8080/v1/models
docker compose exec open-webui curl -s http://llama-embed:8081/v1/models
```

### Checking GPU Utilization
```bash
nvidia-smi
```

### Test General Chat Generation (Qwen 3.6 35B MoE)
```bash
docker compose exec open-webui curl -s http://llama-server:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3.6-35b-a3b",
    "messages": [{"role": "user", "content": "Explain quantum computing in one sentence."}]
  }'
```

### Test Coding Generation (Qwen 3 Coder 30B MoE)
```bash
docker compose exec open-webui curl -s http://llama-server:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-coder-30b-a3b",
    "messages": [{"role": "user", "content": "Write a Python function to check if a number is prime."}],
    "max_tokens": 128
  }'
```

### Test Embedding Generation via Llama-Embed
```bash
docker compose exec open-webui curl -s http://llama-embed:8081/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nomic-embed-text",
    "input": "Spencer Homelab Vector Grounding"
  }'
```

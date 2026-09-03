# Nous Research Hermes Agent

Hermes Agent is an autonomous agent framework and gateway providing tool execution, scheduling, delegation, and web automation capabilities.

---

## 🎯 Overview & Architecture

* **Role**: Autonomous AI agent runtime, API gateway, and management dashboard.
* **Container Name**: `hermes`
* **Image**: `nousresearch/hermes-agent:latest`
* **Command**: `gateway run` (supervised under `s6`)
* **Networks**:
  * `net1`: Ingress routing from Traefik.
  * `ai`: Connection to LiteLLM, Ollama, SearXNG, Firecrawl, Hindsight, and Browserless.
* **External Ingress & Ports**:
  * Gateway API: `https://hermes.spencer.lan` (`:8642` via Traefik)
  * Dashboard Web UI: `https://hermes-dashboard.spencer.lan` (`:9119` via Traefik)
  * MCP Server: `https://mcp.spencer.lan/sse` (`:8765` via Traefik)
  * Direct Host Port: `http://<host-ip>:9119` (Exposed port `9119:9119`)

```mermaid
graph TD
    Traefik[Traefik Proxy] -->|hermes.spencer.lan| Gateway[Hermes Gateway :8642]
    Traefik -->|hermes-dashboard.spencer.lan| Dashboard[Hermes Dashboard :9119]
    Traefik -->|mcp.spencer.lan| MCPServer[Hermes MCP Server :8765]
    
    subgraph Agent Runtime & Toolsets
        Gateway -->|LLM Inference| LiteLLM[LiteLLM Proxy :4000]
        LiteLLM -->|GPU Acceleration| Ollama[Ollama :11434]
        MCPServer -->|Tool Execution| Gateway
        Gateway -->|Web Search| SearXNG[SearXNG :8080]
        Gateway -->|Scrape & Extract| Firecrawl[Firecrawl :3002]
        Gateway -->|Browser CDP| Browserless[Browserless Chrome :3000]
        Gateway -->|Long-Term Memory| Hindsight[Hindsight :8888]
        Gateway -->|Docker Socket| Sandbox[Docker Sandbox Containers :nikolaik/python-nodejs]
    end
```

---

## ⚙️ Configuration & Toolsets

### 1. `hermes/config.yaml`
Configured to use **SearXNG** for queries, **Firecrawl** for content extraction, **Hindsight** for persistent memory, and **Docker** for sandboxed code execution:
```yaml
model:
  default: ${HERMES_MODEL}
  provider: ${HERMES_PROVIDER}
  base_url: ${CUSTOM_BASE_URL}  # http://litellm:4000/v1
  context_length: 65536
  ollama_num_ctx: 65536
custom_providers:
  - name: litellm
    base_url: http://litellm:4000/v1
    context_length: 65536
    models:
      - qwen2.5:14b
      - default
web:
  search_backend: searxng
  extract_backend: firecrawl
memory:
  provider: hindsight
terminal:
  backend: docker
  docker_image: nikolaik/python-nodejs:python3.11-nodejs20
  timeout: 180
  lifetime_seconds: 300
```

### 2. Sandboxed Execution Tools
When Hermes needs to execute shell commands or run scripts, it interacts with disposable Docker containers rather than running directly on the host or in the main container:

* **`terminal` (`terminal_tool`)**: Executes shell commands and scripts in a dedicated container.
* **`process`**: Spawns, monitors, and terminates background jobs inside the sandbox.
* **`execute_code`**: Runs Python scripts programmatically to chain tools and evaluate logic in the sandbox.
* **Security & Isolation**:
  * **Dropped Capabilities**: `ALL` capabilities dropped, with only minimal required flags added back (`DAC_OVERRIDE`, `CHOWN`, `FOWNER`).
  * **Privilege Restrictions**: `no-new-privileges` enforced to block privilege escalation.
  * **Ephemeral Storage**: `/workspace` (10 GB tmpfs), `/home` (1 GB tmpfs), and `/root` (1 GB tmpfs) run in-memory tmpfs scratch spaces that are completely discarded upon session cleanup.
  * **Process Limits**: PID ceiling (`256`) and shared memory size (`1 GB`).

### 3. Environment Variables (`.env`)

| Variable | Reference / Value | Purpose |
|---|---|---|
| `HERMES_API_KEY` | `${HERMES_API_KEY}` | API Server authentication key |
| `HERMES_MCP_KEY` | `${HERMES_MCP_KEY}` | MCP Server Bearer authentication token |
| `HERMES_PROVIDER` | `custom` | LLM backend provider type |
| `CUSTOM_BASE_URL` | `http://ollama:11434/v1` | Ollama OpenAI-compatible endpoint |
| `HERMES_MODEL` | `qwen2.5:14b` | Default primary agent LLM model |
| `HERMES_DASHBOARD` | `1` | Enables Web UI dashboard |
| `HERMES_DASHBOARD_BASIC_AUTH_USERNAME` | `spencer` | Dashboard login username |
| `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH` | `${...}` | Scrypt password hash for authentication |
| `SEARXNG_URL` | `http://searxng:8080` | SearXNG query endpoint |
| `FIRECRAWL_API_URL` | `http://firecrawl:3002` | Firecrawl extraction endpoint |
| `BROWSER_CDP_URL` | `ws://browserless:3000` | Browserless Chrome CDP endpoint |
| `HINDSIGHT_MODE` | `local_external` | Memory provider connection mode |
| `HINDSIGHT_API_URL` | `http://hindsight:8888` | Internal Hindsight service endpoint |
| `HINDSIGHT_BANK_ID` | `hermes` | Default memory bank identifier |
| `HERMES_TERMINAL_ENV` | `docker` | Terminal execution environment driver |
| `HERMES_TERMINAL_DOCKER_IMAGE` | `nikolaik/python-nodejs:python3.11-nodejs20` | Container image used for sandbox execution |

---

## 🔌 Model Context Protocol (MCP) Server

Hermes Agent exposes its internal homelab toolsets over the **Model Context Protocol (MCP)**, allowing external AI clients (Claude Desktop, Cursor, Antigravity IDE, Open WebUI MCP connectors, and external agents) to leverage homelab search, scraping, code sandbox, and workspace tools.

### 1. Endpoints & Access
* **Edge HTTPS URL**: `https://mcp.spencer.lan/sse` (Traefik TLS)
* **Message Ingress**: `https://mcp.spencer.lan/messages/`
* **Internal Docker URL**: `http://hermes:8765/sse` (over `ai` or `net1` bridge)
* **Healthcheck**: `https://mcp.spencer.lan/health` (`GET` — unauthenticated)
* **Authentication**: Enforces HTTP Bearer token via `Authorization: Bearer <HERMES_MCP_KEY>`.

### 2. Available Tools
| Tool Name | Backend Service | Description |
|---|---|---|
| `web_search` | SearXNG (`:8080`) | Privacy-respecting metasearch queries across search engines |
| `web_extract` | Firecrawl (`:3002`) | Markdown conversion, web page crawling, and content extraction |
| `execute_code` | Docker Sandbox | Safe Python script execution inside disposable container |
| `terminal` | Docker Sandbox | Non-interactive and interactive shell execution inside container sandbox |
| `process` | Docker Sandbox | Background process lifecycle management inside container |
| `read_file` | Workspace | Read files from the agent workspace |
| `write_file` | Workspace | Write files to the agent workspace |
| `patch` | Workspace | Apply contextual unified diffs to files |
| `search_files` | Workspace | Grep and regex search across workspace codebase |
| `vision_analyze` | LiteLLM / Ollama | Analyze images with multimodal vision models |
| `text_to_speech` | edge-tts | Convert text to speech audio files |
| `skills_list` | Hermes Registry | Enumerate installed agent skills and capabilities |
| `skill_view` | Hermes Registry | Inspect instructions and runbooks for a specific skill |

### 3. Client Configuration Examples

#### A. Claude Desktop / Remote SSE Client (`claude_desktop_config.json`)
```json
{
  "mcpServers": {
    "hermes-homelab": {
      "url": "https://mcp.spencer.lan/sse",
      "headers": {
        "Authorization": "Bearer c4d029f837f1e00d2f32ca233ec5a48e228e4f608ce06ee9c6cbe8b66ba5a779"
      }
    }
  }
}
```

#### B. Claude Desktop / Local Host Stdio (`claude_desktop_config.json`)
If running on the same host machine with Docker socket access:
```json
{
  "mcpServers": {
    "hermes-homelab-stdio": {
      "command": "docker",
      "args": [
        "exec",
        "-i",
        "hermes",
        "python3",
        "/opt/data/scripts/hermes_mcp_server.py",
        "--stdio"
      ]
    }
  }
}
```

#### C. Open WebUI MCP Connector
1. Navigate to **Admin Settings > Tools > Valves / MCP**.
2. Add new MCP server:
   - **Type**: `SSE`
   - **Server URL**: `http://hermes:8765/sse` (internal) or `https://mcp.spencer.lan/sse`
   - **Headers**: `{"Authorization": "Bearer c4d029f837f1e00d2f32ca233ec5a48e228e4f608ce06ee9c6cbe8b66ba5a779"}`

---

## 📁 Mounted Volumes

| Host Path | Container Path | Purpose |
|---|---|---|
| `./hermes` | `/opt/data` | Persists agent state, databases (`state.db`, `kanban.db`, `projects.db`), skills, memories, and configuration |
| `./hermes/init/03-mcp-server.sh` | `/etc/cont-init.d/03-mcp-server` | Read-only s6 initialization script auto-supervising the MCP server on container boot |
| `/var/run/docker.sock` | `/var/run/docker.sock` | Docker daemon socket allowing Hermes to manage ephemeral sandbox containers |


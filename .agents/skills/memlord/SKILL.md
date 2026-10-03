---
name: memlord
description: Structured workspace memory and procedural knowledge store. Use to store, retrieve, search, and manage project memories, architectural decisions, coding patterns, and cross-session homelab knowledge via Memlord MCP tools and REST API.
---

# Memlord MCP & Procedural Memory Integration

Memlord is a self-hosted Model Context Protocol (MCP) memory server engineered for persistent, structured agent memory with hybrid BM25 + pgvector KNN search fused via Reciprocal Rank Fusion (RRF).

---

## 🔌 Connection Details

* **Public MCP Endpoint**: `https://${MEMLORD_PUBLIC_DOMAIN}/mcp`
* **Internal LAN Endpoint**: `https://memlord.spencer.lan/mcp`
* **Configuration Files**:
  * Global: `~/.gemini/config/mcp_config.json`
  * Workspace: `.agents/mcp_config.json`
* **Authorization**:
  * Header: `Authorization: Bearer <API_KEY>`

---

## 🛠️ MCP Tools (11 Available)

When Memlord MCP tools are bound to the agent session:

| Tool | Parameters | Purpose |
|---|---|---|
| `store_memory` | `name`, `content`, `tags`, `workspace_id`, `expiry` | Save a new memory with automatic deduplication check. |
| `retrieve_memory` | `query`, `limit`, `workspace_id`, `tags` | Hybrid semantic vector + BM25 keyword search fused with RRF. |
| `recall_memory` | `time_query`, `workspace_id` | Query memories using natural language temporal expressions (e.g. "yesterday", "last week"). |
| `list_memories` | `workspace_id`, `page`, `page_size` | List paginated memories with optional tag and metadata filtering. |
| `search_by_tag` | `tags`, `operator` (`AND`/`OR`) | High-precision tag-based retrieval. |
| `get_memory` | `name` | Retrieve complete, unabbreviated body of a memory record. |
| `update_memory` | `name`, `content`, `tags`, `metadata` | Modify an existing memory item. |
| `delete_memory` | `name` | Permanently remove a memory item. |
| `move_memory` | `name`, `target_workspace_id` | Transfer a memory between workspaces. |
| `list_workspaces` | *None* | List available workspaces and IDs. |
| `dream_report` | *None* | Run memory consolidation pass analyzing conflicts and suggesting merges. |

---

## 🌐 Fallback REST API Execution (Terminal / Scripts)

If MCP tool invocation is unavailable or during direct shell scripts:

```bash
# Search Memories
curl -s -H "Authorization: Bearer <API_KEY>" "https://${MEMLORD_PUBLIC_DOMAIN}/api/search?q=<query>"

# Create Memory
curl -s -X POST -H "Authorization: Bearer <API_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"name": "example-note", "content": "Important SOP or context", "tags": ["sop", "project"]}' \
  https://${MEMLORD_PUBLIC_DOMAIN}/api/memories
```

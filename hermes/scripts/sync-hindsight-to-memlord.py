#!/usr/bin/env python3
"""
sync-hindsight-to-memlord.py - Synchronize Hindsight memories into Memlord MCP server.

Automates:
  1. Fetching valid memory units from Hindsight API (http://hindsight:8888).
  2. Tracking synced memory IDs in a durable state file to enable fast incremental sync.
  3. Formatting memories into Memlord structured schema (type mapping, tags, metadata).
  4. Ingesting new memories into Memlord via MCP Streamable HTTP transport.
  5. Optionally notifying Spencer's Homelab push notification gateway (ntfy) on updates or errors.

Usage:
  python3 sync-hindsight-to-memlord.py [OPTIONS]

Options:
  --dry-run              Preview actions and memory counts without writing to Memlord.
  --full-resync          Bypass local state cache and re-check all Hindsight memories.
  --limit <N>            Limit max memories processed in this run (default: 0 = all).
  --no-notify            Suppress push notification via ntfy.
  --topic <topic>        ntfy notification topic (default: agent-memory).
  --hindsight-url <url>  Hindsight API base URL (default: http://hindsight:8888).
  --memlord-url <url>    Memlord MCP endpoint URL (default: http://memlord:8000/mcp).
  -h, --help             Show this help message.
"""

import argparse
import asyncio
import json
import logging
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Set

try:
    import httpx
    from mcp.client.streamable_http import streamable_http_client
    from mcp import ClientSession
except ImportError:
    print("Error: Missing required Python packages (httpx, mcp).", file=sys.stderr)
    sys.exit(1)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("hindsight-to-memlord")


def find_env_file() -> Optional[Path]:
    """Search for Hermes .env file in standard homelab locations."""
    candidates = [
        Path("/opt/data/.env"),
        Path("/data/homelab/hermes/.env"),
        Path.home() / ".hermes" / ".env",
        Path(__file__).resolve().parent.parent / ".env",
        Path(".env"),
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    return None


def load_env_vars():
    """Load environment variables from Hermes .env if not already set in os.environ."""
    env_path = find_env_file()
    if env_path and env_path.is_file():
        try:
            with open(env_path, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    key, val = line.split("=", 1)
                    key = key.strip()
                    val = val.strip().strip("'\"")
                    if key and key not in os.environ:
                        os.environ[key] = val
        except Exception as e:
            logger.warning("Failed to parse env file %s: %s", env_path, e)


def get_state_file_path() -> Path:
    """Resolve state file storage path."""
    candidates = [
        Path("/opt/data/cron"),
        Path("/data/homelab/hermes/cron"),
        Path(__file__).resolve().parent.parent / "cron",
        Path(__file__).resolve().parent,
    ]
    for dir_path in candidates:
        if dir_path.is_dir():
            return dir_path / "hindsight_memlord_sync_state.json"
    return Path("/tmp/hindsight_memlord_sync_state.json")


def load_sync_state(state_file: Path) -> Dict[str, Any]:
    """Load previously synced memory IDs and timestamps."""
    if state_file.is_file():
        try:
            with open(state_file, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            logger.warning("Error reading state file %s: %s. Starting fresh.", state_file, e)
    return {"last_sync_time": None, "synced_ids": [], "sync_count": 0}


def save_sync_state(state_file: Path, state: Dict[str, Any]):
    """Persist sync state to file safely."""
    try:
        state_file.parent.mkdir(parents=True, exist_ok=True)
        tmp_file = state_file.with_suffix(".tmp")
        with open(tmp_file, "w", encoding="utf-8") as f:
            json.dump(state, f, indent=2)
        tmp_file.replace(state_file)
    except Exception as e:
        logger.error("Failed to save sync state to %s: %s", state_file, e)


def send_notification(
    title: str,
    message: str,
    topic: str = "agent-memory",
    priority: str = "3",
    tags: str = "brain,recycle",
):
    """Send alert/summary via homelab notify.sh dispatcher or ntfy HTTP endpoint."""
    script_candidates = [
        Path(__file__).resolve().parent / "notify.sh",
        Path("/opt/data/scripts/notify.sh"),
        Path("/data/homelab/hermes/scripts/notify.sh"),
    ]
    for script in script_candidates:
        if script.is_file() and os.access(script, os.X_OK):
            try:
                subprocess.run(
                    [
                        str(script),
                        "-t",
                        title,
                        "-p",
                        priority,
                        "-g",
                        tags,
                        topic,
                        message,
                    ],
                    check=False,
                    timeout=10,
                )
                return
            except Exception as e:
                logger.warning("notify.sh execution failed: %s", e)

    # Fallback to direct HTTP post to ntfy
    ntfy_url = os.environ.get("NTFY_URL") or "http://ntfy:80"
    try:
        with httpx.Client(timeout=5.0) as client:
            client.post(
                f"{ntfy_url.rstrip('/')}/{topic}",
                content=message,
                headers={"Title": title, "Priority": priority, "Tags": tags},
            )
    except Exception as e:
        logger.debug("Direct ntfy notification failed: %s", e)


def fetch_hindsight_memories(
    base_url: str, bank_id: str = "hermes"
) -> List[Dict[str, Any]]:
    """Fetch all valid memory units from Hindsight API with pagination."""
    url = f"{base_url.rstrip('/')}/v1/default/banks/{bank_id}/memories/list"
    all_items: List[Dict[str, Any]] = []
    limit = 100
    offset = 0

    with httpx.Client(timeout=30.0) as client:
        while True:
            params = {"limit": limit, "offset": offset, "state": "valid"}
            resp = client.get(url, params=params)
            resp.raise_for_status()
            data = resp.json()
            items = data.get("items", [])
            if not items:
                break
            all_items.extend(items)
            total = data.get("total", len(all_items))
            offset += len(items)
            if offset >= total or len(items) < limit:
                break

    return all_items


def map_fact_to_memlord_type(fact_type: Optional[str]) -> str:
    """Map Hindsight fact_type to valid Memlord memory_type."""
    # Memlord allowed types: 'fact', 'preference', 'instruction', 'feedback', 'decision', 'insight'
    mapping = {
        "world": "fact",
        "observation": "insight",
        "experience": "fact",
        "preference": "preference",
        "instruction": "instruction",
        "feedback": "feedback",
        "decision": "decision",
        "insight": "insight",
    }
    return mapping.get(str(fact_type).lower(), "fact")


def sanitize_tags(raw_tags: Optional[List[str]]) -> List[str]:
    """Filter and sanitize tags for Memlord storage."""
    tags = {"hindsight", "sync"}
    if raw_tags:
        for t in raw_tags:
            t_str = str(t).strip()
            # Omit noisy session IDs from tags (still kept in metadata)
            if t_str and not t_str.startswith("session:"):
                tags.add(t_str)
    return sorted(list(tags))


async def sync_memories_to_memlord(
    memories_to_sync: List[Dict[str, Any]],
    memlord_url: str,
    api_key: str,
    dry_run: bool = False,
) -> Dict[str, Any]:
    """Connect to Memlord MCP server and store memories."""
    stats = {
        "total_queued": len(memories_to_sync),
        "synced": 0,
        "already_exists": 0,
        "failed": 0,
        "synced_ids": [],
    }

    if not memories_to_sync:
        return stats

    if dry_run:
        logger.info("[DRY RUN] Would sync %d memories to Memlord", len(memories_to_sync))
        stats["synced"] = len(memories_to_sync)
        stats["synced_ids"] = [m["id"] for m in memories_to_sync]
        return stats

    headers = {"Authorization": f"Bearer {api_key}"}
    async with httpx.AsyncClient(headers=headers, timeout=60.0) as http_client:
        async with streamable_http_client(memlord_url, http_client=http_client) as (
            read_stream,
            write_stream,
        ):
            async with ClientSession(read_stream, write_stream) as session:
                await session.initialize()
                logger.info("Connected to Memlord MCP session. Beginning ingestion...")

                for idx, item in enumerate(memories_to_sync, start=1):
                    item_id = item["id"]
                    name = f"hindsight-{item_id}"
                    content = item.get("text", "").strip()
                    if not content:
                        continue

                    mem_type = map_fact_to_memlord_type(item.get("fact_type"))
                    tags = sanitize_tags(item.get("tags"))
                    metadata = {
                        "source": "hindsight",
                        "hindsight_id": item_id,
                        "fact_type": item.get("fact_type"),
                        "entities": item.get("entities"),
                        "context": item.get("context"),
                        "document_id": item.get("document_id"),
                        "date": item.get("date") or item.get("mentioned_at"),
                    }

                    args = {
                        "name": name,
                        "content": content,
                        "memory_type": mem_type,
                        "tags": tags,
                        "metadata": metadata,
                        "force": True,
                    }

                    try:
                        res = await session.call_tool("store_memory", args)
                        # Parse tool result if returned text
                        res_text = ""
                        if res.content:
                            for c in res.content:
                                if hasattr(c, "text"):
                                    res_text += c.text

                        if '"created":false' in res_text.replace(" ", ""):
                            stats["already_exists"] += 1
                        else:
                            stats["synced"] += 1

                        stats["synced_ids"].append(item_id)

                        if idx % 25 == 0 or idx == len(memories_to_sync):
                            logger.info(
                                "Progress: %d/%d processed (%d created, %d existing)",
                                idx,
                                len(memories_to_sync),
                                stats["synced"],
                                stats["already_exists"],
                            )
                    except Exception as exc:
                        stats["failed"] += 1
                        logger.error("Failed to store memory %s (%s): %s", name, item_id, exc)

    return stats


def main():
    load_env_vars()

    parser = argparse.ArgumentParser(
        description="Synchronize Hindsight memories into Memlord MCP server."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview actions without modifying Memlord",
    )
    parser.add_argument(
        "--full-resync",
        action="store_true",
        help="Ignore cached sync state and evaluate all Hindsight memories",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Limit number of memories processed (0 = unlimited)",
    )
    parser.add_argument(
        "--no-notify",
        action="store_true",
        help="Suppress push notification via ntfy",
    )
    parser.add_argument(
        "--topic",
        type=str,
        default="agent-memory",
        help="ntfy topic for push notification (default: agent-memory)",
    )
    parser.add_argument(
        "--hindsight-url",
        type=str,
        default=os.environ.get("HINDSIGHT_API_URL", "http://hindsight:8888"),
        help="Hindsight API URL (default: http://hindsight:8888)",
    )
    parser.add_argument(
        "--memlord-url",
        type=str,
        default=os.environ.get("MEMLORD_MCP_URL", "http://memlord:8000/mcp"),
        help="Memlord MCP URL (default: http://memlord:8000/mcp)",
    )
    parser.add_argument(
        "--bank-id",
        type=str,
        default=os.environ.get("HINDSIGHT_BANK_ID", "hermes"),
        help="Hindsight memory bank identifier (default: hermes)",
    )

    args = parser.parse_args()

    api_key = (
        os.environ.get("MCP_MEMLORD_API_KEY")
        or os.environ.get("MEMLORD_API_KEY")
    )
    if not api_key:
        logger.error("MCP_MEMLORD_API_KEY environment variable is missing.")
        sys.exit(1)

    state_file = get_state_file_path()
    state = load_sync_state(state_file)
    synced_set: Set[str] = set() if args.full_resync else set(state.get("synced_ids", []))

    logger.info(
        "Starting Hindsight -> Memlord sync (Bank: %s, State Cache: %d entries)",
        args.bank_id,
        len(synced_set),
    )

    start_time = time.time()
    try:
        hindsight_memories = fetch_hindsight_memories(
            args.hindsight_url, bank_id=args.bank_id
        )
        logger.info(
            "Retrieved %d valid memories from Hindsight.", len(hindsight_memories)
        )
    except Exception as e:
        err_msg = f"Failed to fetch memories from Hindsight: {e}"
        logger.error(err_msg)
        if not args.no_notify:
            send_notification(
                "❌ Hindsight Sync Failed",
                err_msg,
                topic=args.topic,
                priority="4",
                tags="warning,x",
            )
        sys.exit(1)

    to_sync = [m for m in hindsight_memories if m.get("id") not in synced_set]
    if args.limit > 0:
        to_sync = to_sync[: args.limit]

    logger.info(
        "Found %d new memories pending sync (Total in Hindsight: %d, Already Synced: %d)",
        len(to_sync),
        len(hindsight_memories),
        len(hindsight_memories) - len(to_sync),
    )

    if not to_sync:
        print("✓ Hindsight to Memlord sync completed: all memories are up to date.")
        return

    try:
        stats = asyncio.run(
            sync_memories_to_memlord(
                to_sync, args.memlord_url, api_key, dry_run=args.dry_run
            )
        )
    except Exception as e:
        err_msg = f"Failed to execute Memlord MCP sync: {e}"
        logger.error(err_msg)
        if not args.no_notify:
            send_notification(
                "❌ Memlord Ingestion Failed",
                err_msg,
                topic=args.topic,
                priority="4",
                tags="warning,x",
            )
        sys.exit(1)

    elapsed = time.time() - start_time

    # Update state file
    if not args.dry_run and stats["synced_ids"]:
        all_synced_ids = list(set(state.get("synced_ids", []) + stats["synced_ids"]))
        state["synced_ids"] = all_synced_ids
        state["last_sync_time"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        state["sync_count"] = state.get("sync_count", 0) + stats["synced"]
        save_sync_state(state_file, state)

    summary = (
        f"✓ Hindsight to Memlord sync finished in {elapsed:.1f}s:\n"
        f"  - Total examined in Hindsight: {len(hindsight_memories)}\n"
        f"  - New memories stored in Memlord: {stats['synced']}\n"
        f"  - Existing / duplicate skipped: {stats['already_exists']}\n"
        f"  - Failures: {stats['failed']}\n"
        f"  - Total active in sync ledger: {len(state.get('synced_ids', []))}"
    )
    print(summary)

    if stats["synced"] > 0 and not args.no_notify and not args.dry_run:
        send_notification(
            "🧠 Memory Sync Complete",
            f"Synced {stats['synced']} new memories from Hindsight into Memlord ({elapsed:.1f}s).",
            topic=args.topic,
            priority="2",
            tags="brain,white_check_mark",
        )


if __name__ == "__main__":
    main()

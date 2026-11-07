#!/usr/bin/env python3
"""
import-memories-to-openwebui.py - Import memories from Memlord and Hindsight into Open WebUI.

Extracts:
1. Core workspace procedural memories, user profile, and architectural rules from Memlord (pgvector).
2. Valid conversational memories and facts from Hindsight API (http://hindsight:8888).
Deduplicates and imports them into Open WebUI's user memory store via Open WebUI REST API.
"""

import argparse
import json
import logging
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Set
import urllib.request
import urllib.error

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("memory-importer")


def get_memlord_memories() -> List[Dict[str, Any]]:
    """Query Memlord memories from PostgreSQL database in pgvector container."""
    cmd = [
        "docker", "exec", "pgvector", "psql", "-U", "postgres", "-d", "memlord",
        "-t", "-A", "-F", "|||",
        "-c", "SELECT name, content, memory_type, metadata::text FROM memories;"
    ]
    res = subprocess.run(cmd, capture_output=True, text=True, check=True)
    memories = []
    for line in res.stdout.strip().split("\n"):
        if not line:
            continue
        parts = line.split("|||")
        if len(parts) >= 2:
            name = parts[0].strip()
            content = parts[1].strip()
            mem_type = parts[2].strip() if len(parts) > 2 else "fact"
            metadata_raw = parts[3].strip() if len(parts) > 3 else "{}"
            if content:
                memories.append({
                    "source": "memlord",
                    "name": name,
                    "content": content,
                    "type": mem_type,
                    "metadata": metadata_raw,
                })
    return memories


def get_hindsight_memories(hindsight_url: str = "http://hindsight:8888", bank_id: str = "hermes") -> List[Dict[str, Any]]:
    """Fetch all valid memories from Hindsight via hermes container or direct connection."""
    all_items = []
    limit = 100
    offset = 0

    while True:
        url = f"{hindsight_url.rstrip('/')}/v1/default/banks/{bank_id}/memories/list?limit={limit}&offset={offset}&state=valid"
        cmd = ["docker", "exec", "hermes", "curl", "-s", url]
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        if not res.stdout.strip():
            break
        data = json.loads(res.stdout)
        items = data.get("items", [])
        if not items:
            break
        all_items.extend(items)
        total = data.get("total", len(all_items))
        offset += len(items)
        if offset >= total or len(items) < limit:
            break

    memories = []
    for item in all_items:
        text = item.get("text", "").strip()
        if text:
            memories.append({
                "source": "hindsight",
                "id": item.get("id"),
                "content": text,
                "fact_type": item.get("fact_type"),
            })
    return memories


def get_openwebui_token(base_url: str, email: str, password: str) -> str:
    """Sign in to Open WebUI to acquire a bearer session token."""
    login_url = f"{base_url.rstrip('/')}/api/v1/auths/signin"
    payload = json.dumps({"email": email, "password": password}).encode("utf-8")
    cmd = [
        "docker", "exec", "-i", "open-webui", "curl", "-s", "-X", "POST",
        login_url, "-H", "Content-Type: application/json", "-d", "@-"
    ]
    proc = subprocess.run(cmd, input=payload.decode("utf-8"), capture_output=True, text=True, check=True)
    data = json.loads(proc.stdout)
    token = data.get("token")
    if not token:
        raise RuntimeError(f"Failed to authenticate with Open WebUI: {proc.stdout}")
    return token


def get_existing_openwebui_memories(base_url: str, token: str) -> Set[str]:
    """Retrieve existing memory contents to prevent duplicates."""
    url = f"{base_url.rstrip('/')}/api/v1/memories/"
    cmd = [
        "docker", "exec", "open-webui", "curl", "-s",
        "-H", f"Authorization: Bearer {token}",
        url
    ]
    res = subprocess.run(cmd, capture_output=True, text=True, check=True)
    existing = set()
    try:
        items = json.loads(res.stdout)
        if isinstance(items, list):
            for item in items:
                content = item.get("content", "").strip()
                if content:
                    existing.add(content.lower())
    except Exception as e:
        logger.warning(f"Could not parse existing Open WebUI memories: {e}")
    return existing


def add_openwebui_memory(base_url: str, token: str, content: str) -> bool:
    """Add a single memory item to Open WebUI via REST API."""
    url = f"{base_url.rstrip('/')}/api/v1/memories/add"
    payload = json.dumps({"content": content})
    cmd = [
        "docker", "exec", "-i", "open-webui", "curl", "-s", "-X", "POST",
        url,
        "-H", f"Authorization: Bearer {token}",
        "-H", "Content-Type: application/json",
        "-d", "@-"
    ]
    proc = subprocess.run(cmd, input=payload, capture_output=True, text=True, check=True)
    if '"id":' in proc.stdout and '"user_id":' in proc.stdout:
        return True
    logger.error(f"Failed to add memory: {proc.stdout}")
    return False


def get_admin_credentials() -> tuple[str, str]:
    """Retrieve admin credentials from environment or .env.passwords file."""
    email = os.environ.get("OPENWEBUI_ADMIN_EMAIL", "james@jamesspencer.me")
    password = os.environ.get("OPENWEBUI_ADMIN_PASSWORD")
    if not password:
        passwords_file = Path("/data/homelab/.env.passwords")
        if passwords_file.is_file():
            with open(passwords_file, "r") as f:
                for line in f:
                    if line.startswith("OPENWEBUI_ADMIN_PASSWORD="):
                        password = line.split("=", 1)[1].strip()
                        break
    return email, password or ""


def main():
    parser = argparse.ArgumentParser(description="Import memories from Memlord and Hindsight to Open WebUI.")
    parser.add_argument("--base-url", default="http://localhost:8080", help="Open WebUI base URL (internal container URL)")
    parser.add_argument("--email", default=None, help="Open WebUI admin email")
    parser.add_argument("--password", default=None, help="Open WebUI admin password")
    parser.add_argument("--limit", type=int, default=0, help="Limit number of memories imported (0 = all)")
    args = parser.parse_args()

    default_email, default_pw = get_admin_credentials()
    email = args.email or default_email
    password = args.password or default_pw

    if not password:
        logger.error("Admin password not provided and not found in .env.passwords.")
        sys.exit(1)

    logger.info("Connecting to Open WebUI...")
    token = get_openwebui_token(args.base_url, email, password)
    logger.info("Successfully authenticated with Open WebUI.")

    existing_memories = get_existing_openwebui_memories(args.base_url, token)
    logger.info(f"Open WebUI currently has {len(existing_memories)} memory items.")

    logger.info("Fetching memories from Memlord...")
    memlord_items = get_memlord_memories()
    logger.info(f"Retrieved {len(memlord_items)} memories from Memlord.")

    logger.info("Fetching memories from Hindsight...")
    hindsight_items = get_hindsight_memories()
    logger.info(f"Retrieved {len(hindsight_items)} memories from Hindsight.")

    # Deduplicate memories
    candidates = []
    seen = set(existing_memories)

    # Prioritize core Memlord memories (profile, infrastructure, project conventions)
    for m in memlord_items:
        content = m["content"].strip()
        cleaned_key = " ".join(content.lower().split())
        if cleaned_key not in seen:
            seen.add(cleaned_key)
            candidates.append({"source": "memlord", "content": content})

    # Add unique Hindsight memories
    for h in hindsight_items:
        content = h["content"].strip()
        cleaned_key = " ".join(content.lower().split())
        if cleaned_key not in seen:
            seen.add(cleaned_key)
            candidates.append({"source": "hindsight", "content": content})

    if args.limit > 0:
        candidates = candidates[:args.limit]

    logger.info(f"Found {len(candidates)} new unique memories to import into Open WebUI.")

    imported = 0
    failed = 0
    start_time = time.time()

    for idx, item in enumerate(candidates, start=1):
        content = item["content"]
        # Limit memory content length to standard single-fact chunk if excessive
        if len(content) > 1000:
            content = content[:997] + "..."

        ok = add_openwebui_memory(args.base_url, token, content)
        if ok:
            imported += 1
        else:
            failed += 1

        if idx % 25 == 0 or idx == len(candidates):
            logger.info(f"Progress: {idx}/{len(candidates)} processed ({imported} imported, {failed} failed)...")

    elapsed = time.time() - start_time
    logger.info(f"Memory import complete in {elapsed:.1f}s: {imported} imported, {failed} failed.")


if __name__ == "__main__":
    main()

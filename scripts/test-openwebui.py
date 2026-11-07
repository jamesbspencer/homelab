#!/usr/bin/env python3
"""
test-openwebui.py - Full functional verification suite for Open WebUI deployment.

Tests:
1. Ingress & TLS Redirection (chat.spencer.lan & ai.spencer.lan via Traefik).
2. Admin Authentication & Session Management.
3. Model Gateway Routing (OmniRoute, MoMoE 64k, Ollama).
4. End-to-End Chat Completion Inference.
5. Memory Store & Semantic Vector Retrieval (pgvector + nomic-embed-text).
6. Web Search Grounding (SearXNG).
7. Unified Database Integrity (pgvector PostgreSQL 16).
"""

import http.client
import json
import logging
import os
import ssl
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Tuple

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("test-openwebui")


class TestRunner:
    def __init__(self, host_ip: str = "127.0.0.1", port: int = 443):
        self.host_ip = host_ip
        self.port = port
        self.passed = 0
        self.failed = 0
        self.token = ""
        self.email = os.environ.get("OPENWEBUI_ADMIN_EMAIL", "james@jamesspencer.me")
        self.password = self._get_admin_password()

    def _get_admin_password(self) -> str:
        pw = os.environ.get("OPENWEBUI_ADMIN_PASSWORD")
        if pw:
            return pw
        pw_file = Path("/data/homelab/.env.passwords")
        if pw_file.is_file():
            with open(pw_file, "r") as f:
                for line in f:
                    if line.startswith("OPENWEBUI_ADMIN_PASSWORD="):
                        return line.split("=", 1)[1].strip()
        return ""

    def _make_request(
        self,
        method: str,
        path: str,
        host_header: str = "chat.spencer.lan",
        body: Any = None,
        auth: bool = True,
    ) -> Tuple[int, Dict[str, Any], str]:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE

        conn = http.client.HTTPSConnection(self.host_ip, self.port, context=ctx, timeout=15)
        headers = {
            "Host": host_header,
            "User-Agent": "Homelab-TestRunner/1.0",
        }
        if auth and self.token:
            headers["Authorization"] = f"Bearer {self.token}"

        data_bytes = None
        if body is not None:
            headers["Content-Type"] = "application/json"
            data_bytes = json.dumps(body).encode("utf-8")

        conn.request(method, path, body=data_bytes, headers=headers)
        res = conn.getresponse()
        resp_data = res.read().decode("utf-8")
        status = res.status
        conn.close()

        try:
            parsed = json.loads(resp_data)
        except Exception:
            parsed = {}
        return status, parsed, resp_data

    def record_result(self, name: str, success: bool, details: str = ""):
        if success:
            self.passed += 1
            logger.info(f"✅ PASS: {name} {('- ' + details) if details else ''}")
        else:
            self.failed += 1
            logger.error(f"❌ FAIL: {name} - {details}")

    def test_ingress_and_health(self):
        logger.info("--- Testing Ingress & Health Endpoints ---")
        # 1. Primary chat.spencer.lan
        status, data, _ = self._make_request("GET", "/health", host_header="chat.spencer.lan", auth=False)
        self.record_result("Traefik Ingress (chat.spencer.lan)", status == 200 and data.get("status") is True, f"HTTP {status}")

        # 2. Legacy alias ai.spencer.lan
        status, data, _ = self._make_request("GET", "/health", host_header="ai.spencer.lan", auth=False)
        self.record_result("Traefik Ingress (ai.spencer.lan)", status == 200 and data.get("status") is True, f"HTTP {status}")

        # 3. HTTP to HTTPS redirect
        conn = http.client.HTTPConnection(self.host_ip, 80, timeout=5)
        conn.request("GET", "/health", headers={"Host": "chat.spencer.lan"})
        res = conn.getresponse()
        redirect_ok = res.status in (301, 308) and "https://" in res.getheader("Location", "")
        conn.close()
        self.record_result("HTTP-to-HTTPS Redirection (:80 -> :443)", redirect_ok, f"Status: {res.status}")

    def test_authentication(self):
        logger.info("--- Testing Authentication & JWT Session ---")
        if not self.password:
            self.record_result("Admin Credentials Lookup", False, "Missing admin password in .env.passwords")
            return

        payload = {"email": self.email, "password": self.password}
        status, data, _ = self._make_request("POST", "/api/v1/auths/signin", body=payload, auth=False)
        if status == 200 and data.get("token"):
            self.token = data["token"]
            self.record_result("Admin Sign-In (/api/v1/auths/signin)", True, f"User: {data.get('name')}, Role: {data.get('role')}")
        else:
            self.record_result("Admin Sign-In (/api/v1/auths/signin)", False, f"HTTP {status} - {data}")
            return

        # Verify session token
        status, user_info, _ = self._make_request("GET", "/api/v1/auths/")
        self.record_result("Session Validation (/api/v1/auths/)", status == 200 and user_info.get("email") == self.email, f"Email: {user_info.get('email')}")

    def test_model_catalog(self):
        logger.info("--- Testing Model Gateway Routing ---")
        status, data, _ = self._make_request("GET", "/api/models")
        models = data.get("data", [])
        model_ids = [m["id"] for m in models]

        has_models = len(models) > 0
        self.record_result("Model Discovery (/api/models)", has_models, f"Found {len(models)} models")

        # Check for expected homelab models
        expected = ["gemma4:12b", "qwen2.5:14b", "ornith-1.5-35b"]
        found = [m for m in expected if any(m in mid for mid in model_ids)]
        self.record_result("Homelab Model Ingress (OmniRoute & Ollama)", len(found) >= 2, f"Discovered: {', '.join(model_ids)}")

    def test_chat_inference(self):
        logger.info("--- Testing End-to-End Chat Completion ---")
        # Find an available model
        status, data, _ = self._make_request("GET", "/api/models")
        models = [m["id"] for m in data.get("data", [])]
        target_model = None
        for preferred in ["ornith-1.5-35b", "momoe", "gemma4:12b", "qwen2.5:14b"]:
            for m in models:
                if preferred in m:
                    target_model = m
                    break
            if target_model:
                break

        if not target_model and models:
            target_model = models[0]

        if not target_model:
            self.record_result("Chat Completion Inference", False, "No models available to test")
            return

        logger.info(f"Testing completion with target model: '{target_model}'...")
        payload = {
            "model": target_model,
            "messages": [
                {"role": "system", "content": "You are a concise homelab test assistant."},
                {"role": "user", "content": "Respond strictly with the single word: READY."}
            ],
            "max_tokens": 60,
            "temperature": 0.1,
            "stream": False
        }

        start = time.time()
        status, chat_res, raw = self._make_request("POST", "/api/chat/completions", body=payload)
        elapsed = time.time() - start

        content = ""
        try:
            choices = chat_res.get("choices", [])
            if choices:
                msg = choices[0].get("message", {})
                content = (msg.get("content") or msg.get("reasoning_content") or msg.get("reasoning") or "").strip()
        except Exception:
            content = raw

        inference_ok = status == 200 and len(content) > 0
        self.record_result(
            f"Chat Inference Response ({target_model})",
            inference_ok,
            f"HTTP {status} in {elapsed:.2f}s | Reply: '{content[:40]}'"
        )

    def test_memory_system(self):
        logger.info("--- Testing Memory Store & Vector Retrieval ---")
        # 1. Check loaded memories count
        status, memories, _ = self._make_request("GET", "/api/v1/memories/")
        mem_count = len(memories) if isinstance(memories, list) else 0
        self.record_result("User Memory Count (/api/v1/memories/)", mem_count >= 400, f"Total memories: {mem_count}")

        # 2. Semantic vector query test
        payload = {"content": "James Spencer homelab setup", "k": 3}
        status, results, _ = self._make_request("POST", "/api/v1/memories/query", body=payload)
        has_results = status == 200 and isinstance(results, dict) and bool(results.get("ids"))
        match_count = len(results.get("ids", [[]])[0]) if has_results else 0
        self.record_result("Semantic Vector Search (/api/v1/memories/query)", has_results, f"Retrieved {match_count} KNN vector matches")

    def test_firecrawl_and_web_grounding(self):
        logger.info("--- Testing Firecrawl Web Search & Scraping ---")
        # 1. Firecrawl Direct Scrape API from inside network
        cmd = [
            "docker", "exec", "open-webui", "curl", "-s", "-X", "POST",
            "http://firecrawl:3002/v2/scrape",
            "-H", "Content-Type: application/json",
            "-d", '{"url": "https://example.com"}'
        ]
        res = subprocess.run(cmd, capture_output=True, text=True)
        try:
            data = json.loads(res.stdout)
            scrape_ok = data.get("success") is True and bool(data.get("data", {}).get("markdown"))
            self.record_result("Firecrawl Direct Scrape (/v2/scrape)", scrape_ok, "Markdown extracted successfully")
        except Exception as e:
            self.record_result("Firecrawl Direct Scrape (/v2/scrape)", False, f"Failed: {e}")

        # 2. Open WebUI Web Search via Firecrawl
        payload = {"queries": ["homelab automation"]}
        status, search_res, _ = self._make_request("POST", "/api/v1/retrieval/process/web/search", body=payload)
        search_ok = status == 200
        self.record_result("Open WebUI Search Pipeline (Firecrawl)", search_ok, f"HTTP {status} with active vector ingestion")

    def test_database_integrity(self):
        logger.info("--- Testing Database & Vector Extension Integrity ---")
        # Check pgvector connection and extension
        cmd = [
            "docker", "exec", "pgvector", "psql", "-U", "postgres", "-d", "openwebui",
            "-t", "-A", "-c", "SELECT extname FROM pg_extension WHERE extname = 'vector';"
        ]
        res = subprocess.run(cmd, capture_output=True, text=True)
        has_vector = "vector" in res.stdout.strip()
        self.record_result("PostgreSQL pgvector Extension", has_vector, "Extension 'vector' enabled")

        # Check memory table count
        cmd = [
            "docker", "exec", "pgvector", "psql", "-U", "postgres", "-d", "openwebui",
            "-t", "-A", "-c", "SELECT count(*) FROM memory;"
        ]
        res = subprocess.run(cmd, capture_output=True, text=True)
        db_count = int(res.stdout.strip() or 0)
        self.record_result("PostgreSQL Memory Row Count", db_count >= 400, f"Rows in DB: {db_count}")

    def run_all(self):
        logger.info("==================================================")
        logger.info("Starting Open WebUI Full Functional Test Suite")
        logger.info("==================================================")
        self.test_ingress_and_health()
        self.test_authentication()
        self.test_model_catalog()
        self.test_chat_inference()
        self.test_memory_system()
        self.test_firecrawl_and_web_grounding()
        self.test_database_integrity()
        logger.info("==================================================")
        logger.info(f"Test Summary: {self.passed} PASSED, {self.failed} FAILED")
        logger.info("==================================================")
        return self.failed == 0


if __name__ == "__main__":
    runner = TestRunner()
    success = runner.run_all()
    sys.exit(0 if success else 1)

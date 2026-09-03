#!/usr/bin/env python3
"""
Hermes Agent Model Context Protocol (MCP) Server.

Exposes homelab tools (SearXNG search, Firecrawl scraping, Docker sandbox execution,
workspace files, vision analysis, and skills) via:
  1. HTTP/SSE transport (default): For network MCP clients (Open WebUI, remote IDEs)
     routed via Traefik (https://mcp.spencer.lan/sse).
  2. Stdio transport (--stdio): For local MCP clients (Claude Desktop, Cursor)
     spawned directly via `docker exec -i`.

Authentication:
  Enforces Bearer token authentication via HERMES_MCP_KEY (or HERMES_API_KEY).
  Requests to /health bypass authentication for container/proxy health checks.
"""

from __future__ import annotations

import argparse
import asyncio
import inspect
import json
import logging
import os
import sys
from typing import Any, Callable, Dict, List, Optional, Set

logger = logging.getLogger("hermes_mcp_server")

# JSON Schema to Python type mapping for MCPServer signature synthesis
_JSON_TO_PY = {
    "string": str,
    "integer": int,
    "number": float,
    "boolean": bool,
    "array": list,
    "object": dict,
}

DEFAULT_EXPOSED_TOOLS: tuple[str, ...] = (
    # Web Intelligence
    "web_search",
    "web_extract",
    # Docker Sandbox Execution
    "execute_code",
    "terminal",
    "process",
    # Workspace & File Management
    "read_file",
    "write_file",
    "patch",
    "search_files",
    # Vision & Media
    "vision_analyze",
    "text_to_speech",
    # Skills
    "skills_list",
    "skill_view",
)


def _signature_from_schema(schema: Optional[Dict[str, Any]]) -> tuple[inspect.Signature, Dict[str, Any]]:
    """Synthesize an inspect.Signature from a JSON schema object."""
    props = (schema or {}).get("properties") or {}
    required: Set[str] = set((schema or {}).get("required") or [])
    params: List[inspect.Parameter] = []
    annots: Dict[str, Any] = {}

    for pname, pspec in props.items():
        if pname.startswith("_"):
            continue
        py = _JSON_TO_PY.get((pspec or {}).get("type"), Any)
        ann, default = (
            (py, inspect.Parameter.empty)
            if pname in required
            else (Optional[py], None)
        )
        annots[pname] = ann
        params.append(
            inspect.Parameter(
                pname, inspect.Parameter.KEYWORD_ONLY, annotation=ann, default=default
            )
        )

    return inspect.Signature(params, return_annotation=str), annots


def build_mcp_server() -> Any:
    """Build and register tools on an MCPServer instance."""
    try:
        from mcp.server import MCPServer
    except ImportError as exc:
        raise ImportError(f"mcp package required for Hermes MCP server: {exc}") from exc

    from model_tools import get_tool_definitions, handle_function_call

    mcp = MCPServer(
        "hermes-tools",
        instructions=(
            "Hermes Agent homelab toolset. Exposes web search (SearXNG), "
            "web extraction (Firecrawl), sandboxed code and terminal execution (Docker sandbox), "
            "workspace file management, vision analysis, and agent skills."
        ),
    )

    # Determine tool list
    custom_tools = os.environ.get("HERMES_MCP_TOOLS")
    if custom_tools:
        tools_to_expose = [t.strip() for t in custom_tools.split(",") if t.strip()]
    else:
        tools_to_expose = list(DEFAULT_EXPOSED_TOOLS)

    # Gather available Hermes tool definitions
    all_defs = {
        td["function"]["name"]: td["function"]
        for td in (get_tool_definitions(quiet_mode=True) or [])
        if isinstance(td, dict) and td.get("type") == "function"
    }

    registered_count = 0
    for name in tools_to_expose:
        spec = all_defs.get(name)
        if spec is None:
            logger.warning("Tool '%s' not registered in Hermes, skipping", name)
            continue

        description = spec.get("description") or f"Hermes {name} tool"
        params_schema = spec.get("parameters") or {"type": "object", "properties": {}}

        def _make_handler(tool_name: str, schema: Optional[Dict[str, Any]]) -> Callable[..., str]:
            sig, annots = _signature_from_schema(schema)

            def _dispatch(**kwargs: Any) -> str:
                try:
                    args = {k: v for k, v in kwargs.items() if v is not None}
                    return handle_function_call(tool_name, args or {})
                except Exception as exc:
                    logger.exception("Error executing tool %s", tool_name)
                    return json.dumps({"error": str(exc), "tool": tool_name})

            _dispatch.__name__ = tool_name
            _dispatch.__doc__ = description
            _dispatch.__signature__ = sig
            _dispatch.__annotations__ = {**annots, "return": str}
            return _dispatch

        try:
            mcp.add_tool(
                _make_handler(name, params_schema),
                name=name,
                description=description,
            )
        except TypeError:
            handler = _make_handler(name, params_schema)
            handler = mcp.tool(name=name, description=description)(handler)

        registered_count += 1

    logger.info("Hermes MCP server registered %d/%d tools", registered_count, len(tools_to_expose))
    return mcp


def create_sse_application(mcp_server: Any, auth_token: Optional[str] = None):
    """Wrap MCPServer Starlette SSE app with authentication and healthcheck endpoints."""
    from starlette.middleware import Middleware
    from starlette.middleware.base import BaseHTTPMiddleware
    from starlette.requests import Request
    from starlette.responses import JSONResponse, Response
    from starlette.routing import Route

    class BearerAuthMiddleware(BaseHTTPMiddleware):
        async def dispatch(self, request: Request, call_next: Any) -> Response:
            # Allow health checks without authentication
            if request.url.path in ("/health", "/healthz", "/ping"):
                return await call_next(request)

            # If no auth token is configured, allow all
            if not auth_token:
                return await call_next(request)

            # Check Authorization: Bearer <token>
            auth_header = request.headers.get("Authorization", "")
            token = ""
            if auth_header.startswith("Bearer "):
                token = auth_header[7:].strip()
            elif "token" in request.query_params:
                token = request.query_params["token"]
            elif "api_key" in request.query_params:
                token = request.query_params["api_key"]

            if token != auth_token:
                return JSONResponse(
                    {
                        "error": "Unauthorized",
                        "detail": "Missing or invalid Bearer token for Hermes MCP server",
                    },
                    status_code=401,
                )

            return await call_next(request)

    async def health_endpoint(request: Request) -> JSONResponse:
        return JSONResponse(
            {
                "status": "healthy",
                "service": "hermes-mcp-server",
                "transport": "sse",
            }
        )

    # Base Starlette app from MCPServer
    starlette_app = mcp_server.sse_app(
        sse_path="/sse",
        message_path="/messages/",
        host="0.0.0.0",
    )

    # Add /health route
    starlette_app.routes.insert(0, Route("/health", endpoint=health_endpoint, methods=["GET"]))

    # Add BearerAuthMiddleware
    starlette_app.add_middleware(BearerAuthMiddleware)

    return starlette_app


def main() -> int:
    parser = argparse.ArgumentParser(description="Hermes Model Context Protocol (MCP) Server")
    parser.add_argument("--stdio", action="store_true", help="Run in stdio mode (JSON-RPC on stdin/stdout)")
    parser.add_argument("--host", default=os.environ.get("MCP_HOST", "0.0.0.0"), help="Bind host for SSE server")
    parser.add_argument("--port", type=int, default=int(os.environ.get("MCP_PORT", "8765")), help="Bind port for SSE server")
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose debug logging")
    args = parser.parse_args()

    log_level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(
        level=log_level,
        stream=sys.stderr,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )

    # Quiet mode to prevent stdout pollution in stdio mode
    os.environ.setdefault("HERMES_QUIET", "1")
    os.environ.setdefault("HERMES_REDACT_SECRETS", "true")

    auth_token = os.environ.get("HERMES_MCP_KEY") or os.environ.get("HERMES_API_KEY")

    try:
        server = build_mcp_server()
    except Exception as exc:
        sys.stderr.write(f"Failed to initialize Hermes MCP server: {exc}\n")
        return 1

    if args.stdio:
        logger.info("Starting Hermes MCP server on stdio transport...")
        try:
            server.run(transport="stdio")
        except KeyboardInterrupt:
            return 0
        except Exception as exc:
            logger.exception("Hermes MCP stdio server error: %s", exc)
            return 1
    else:
        import uvicorn

        logger.info(
            "Starting Hermes MCP server on SSE transport (http://%s:%d/sse)...",
            args.host,
            args.port,
        )
        if auth_token:
            logger.info("Bearer token authentication is ENABLED.")
        else:
            logger.warning("No HERMES_MCP_KEY or HERMES_API_KEY found; running WITHOUT authentication.")

        app = create_sse_application(server, auth_token=auth_token)
        config = uvicorn.Config(
            app,
            host=args.host,
            port=args.port,
            log_level="info" if args.verbose else "warning",
            access_log=args.verbose,
        )
        uv_server = uvicorn.Server(config)
        try:
            asyncio.run(uv_server.serve())
        except KeyboardInterrupt:
            return 0
        except Exception as exc:
            logger.exception("Hermes MCP SSE server error: %s", exc)
            return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())

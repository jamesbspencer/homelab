# Browserless Chrome

Browserless provides a headless Chromium browser instance supporting the Chrome DevTools Protocol (CDP) and Playwright for rendering JavaScript-heavy websites and automating browser workflows.

---

## 🎯 Overview & Architecture

* **Role**: Headless browser automation server for Open WebUI and local agent tools.
* **Container Name**: `browserless`
* **Image**: `browserless/chrome:latest`
* **Internal Port**: `3000`
* **Network**: `ai` (Internal AI network)
* **WebSocket Endpoint**: `ws://browserless:3000`

---

## ⚙️ Configuration & Environment

| Variable | Value | Purpose |
|---|---|---|
| `MAX_CONCURRENT_SESSIONS` | `10` | Caps simultaneous active Chrome browser contexts |

---

## 🔗 Integrated Consumers

1. **Open WebUI Web Loader**:
   - `RAG_WEB_LOADER_ENGINE=playwright`
   - `PLAYWRIGHT_WS_URI=ws://browserless:3000`
2. **Hermes Agent Browser Tool**:
   - `BROWSER_CDP_URL=ws://browserless:3000`

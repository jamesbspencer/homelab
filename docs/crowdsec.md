# CrowdSec Security Engine & Traefik Bouncer Guide

CrowdSec is an open-source, modernized intrusion detection and prevention engine (IPS/IDS) that protects homelab web services from brute-force attacks, port scanning, web application exploits (CVE probes), and malicious bots.

In this homelab, CrowdSec pairs with the **Traefik Bouncer Plugin** (`github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin`) to analyze HTTP access logs and block malicious actors at the Traefik edge reverse proxy before requests reach internal services.

---

## 🏗️ Architecture & Topology

```
                  ┌────────────────────────────────────────────────────────┐
                  │                      Client / Internet                 │
                  └───────────────────────────┬────────────────────────────┘
                                              │ HTTPS (:443)
                                              ▼
┌───────────────────────────────────────── Traefik ─────────────────────────────────────────┐
│                                                                                           │
│   ┌───────────────────────────────────────────────────────────────────────────────────┐   │
│   │                      Traefik Bouncer Plugin (Stream Mode)                         │   │
│   │   - In-memory decision cache (zero latency overhead on incoming requests)        │   │
│   │   - Periodic sync with CrowdSec LAPI (:8080)                                      │   │
│   │   - Whitelisted private subnets (127.0.0.1/32, 192.168.0.0/16, 10.0.0.0/8)        │   │
│   └───────────────────────┬───────────────────────────────────┬───────────────────────┘   │
│                           │ Allowed                           │ Banned                    │
│                           ▼                                   ▼                           │
│                 Internal Homelab Services               403 Forbidden                     │
│                 (Open WebUI, LiteLLM, Hermes)                                             │
│                                                                                           │
│   Writes access.log ───► /var/log/traefik/access.log                                      │
└─────────────────────────────────────┬─────────────────────────────────────────────────────┘
                                      │ Mounted volume (:ro)
                                      ▼
┌──────────────────────────────────────── CrowdSec ─────────────────────────────────────────┐
│                                                                                           │
│   - Log Acquisition: /etc/crowdsec/acquis.d/traefik.yaml                                  │
│   - Parsers & Scenarios: crowdsecurity/traefik, crowdsecurity/http-cve                    │
│   - Local API (LAPI): http://crowdsec:8080                                                │
│   - Central API (CAPI): Community blocklist consensus sync                                │
│                                                                                           │
└───────────────────────────────────────────────────────────────────────────────────────────┘
```

### Key Components:
- **`crowdsec` container**: Runs the Local API (LAPI), ingests Traefik access logs via `/var/log/traefik/access.log`, detects malicious patterns, and synchronizes community blocklists with the CrowdSec Central API.
- **Traefik Bouncer Plugin**: Loaded dynamically by Traefik on boot. Operates in **Stream Mode**, syncing decisions from LAPI in the background every 60 seconds and filtering traffic in memory.
- **`traefik/logs/access.log`**: Structured JSON access log written by Traefik and ingested in real time by CrowdSec.

---

## ⚙️ Configuration Files

| File | Purpose |
|---|---|
| [`docker-compose.yaml`](file:///data/homelab/docker-compose.yaml) | Defines the `crowdsec` service on `net1`, binds `./traefik/logs` to both Traefik and CrowdSec, mounts `./traefik/crowdsec_bouncer_key` |
| [`traefik/traefik.yml`](file:///data/homelab/traefik/traefik.yml) | Enables `accessLog`, registers `experimental.plugins.crowdsec-bouncer`, attaches `crowdsec-bouncer@file` to entryPoint `websecure` |
| [`traefik/dynamic.yml`](file:///data/homelab/traefik/dynamic.yml) | Defines `crowdsec-bouncer` middleware in `stream` mode using `crowdsecLapiKeyFile` and `clientTrustedIPs` |
| [`crowdsec/config/acquis.d/traefik.yaml`](file:///data/homelab/crowdsec/config/acquis.d/traefik.yaml) | Directs CrowdSec to acquire and parse `/var/log/traefik/access.log` using the `traefik` parser |
| [`traefik/crowdsec_bouncer_key`](file:///data/homelab/traefik/crowdsec_bouncer_key) | Secure key file containing the 32-byte hex bouncer API token (file permissions `600`, gitignored) |

---

## 🛠️ CLI Operations (`cscli`)

All management is performed using the `cscli` utility inside the `crowdsec` container.

### 1. View Active Decisions (Bans)
```bash
docker exec -it crowdsec cscli decisions list
```

### 2. View Security Alerts
```bash
docker exec -it crowdsec cscli alerts list
```

To view details on a specific alert ID:
```bash
docker exec -it crowdsec cscli alerts inspect <ALERT_ID>
```

### 3. Check Bouncer Registration & Activity
```bash
docker exec -it crowdsec cscli bouncers list
```
*Look for `traefik-bouncer` with its IP and last pull timestamp.*

### 4. Inspect Log Acquisition & Processing Metrics
```bash
docker exec -it crowdsec cscli metrics
```
*Displays lines read from `/var/log/traefik/access.log`, parsed lines, and scenario trigger counts.*

### 5. Manually Ban an IP Address
```bash
docker exec -it crowdsec cscli decisions add --ip 1.2.3.4 --duration 24h --reason "manual ban"
```

### 6. Manually Unban an IP Address
```bash
docker exec -it crowdsec cscli decisions delete --ip 1.2.3.4
```

---

## 📦 Installed Collections

CrowdSec automatically downloads and maintains the following collections on startup (configured via `COLLECTIONS` in `docker-compose.yaml`):
- `crowdsecurity/traefik`: Log parsers for Traefik access log formats.
- `crowdsecurity/http-cve`: Detection scenarios for known HTTP CVEs, path traversal, exploit probes, and malicious scanners.
- `crowdsecurity/whitelist-good-actors`: Whitelists known benign search engine crawlers (Googlebot, Bingbot, DuckDuckGo) and CDN nodes.

To install additional hub collections or scenarios:
```bash
docker exec -it crowdsec cscli collections install <collection-name>
docker compose restart crowdsec
```

---

## 🔒 Whitelisting & Trusted Networks

Local homelab networks are excluded from bouncer enforcement via `clientTrustedIPs` in [`traefik/dynamic.yml`](file:///data/homelab/traefik/dynamic.yml):
```yaml
clientTrustedIPs:
  - "127.0.0.1/32"
  - "192.168.0.0/16"
  - "10.0.0.0/8"
```
Requests originating from these subnets bypass decision enforcement to avoid accidental lockouts during local administration.

# Authentik Centralized Identity & Access Management (IAM) Guide

Authentik is an all-in-one, modern open-source Identity Provider (IdP) and single sign-on (SSO) gateway powering Spencer's homelab. It features a graphical administration portal, visual authentication flow builder, native OpenID Connect (OIDC) / SAML provider capabilities, and Traefik ForwardAuth Proxy Outposts.

---

## 🏗️ Architecture & Topology

```
                  ┌────────────────────────────────────────────────────────┐
                  │                      Client Browser                    │
                  └───────────────────────────┬────────────────────────────┘
                                              │ HTTPS (:443)
                                              ▼
┌───────────────────────────────────────── Traefik ─────────────────────────────────────────┐
│                                                                                           │
│   Incoming Request (e.g. https://hindsight.spencer.lan or https://traefik.spencer.lan)     │
│                                              │                                            │
│                                              ▼ ForwardAuth Check                          │
│                     http://authentik-server:9000/outpost.goauthentik.io/auth/traefik      │
│                                              │                                            │
│                        ┌─────────────────────┴─────────────────────┐                      │
│                        │ 200 OK (Authorized)                       │ 302 Redirect         │
│                        ▼                                           ▼                      │
│               Proxied Web Service                     Redirect to Login Portal            │
│               (Hindsight, Traefik Dash)               https://sso.spencer.lan/if/flow/... │
│                                                                                           │
└───────────────────────────────────────────────────────────────────────────────────────────┘
                                              │
                                              ▼
┌────────────────────────────────────── Authentik Core ─────────────────────────────────────┐
│                                                                                           │
│   ┌───────────────────────────────────────────────────────────────────────────────────┐   │
│   │                 authentik-server (Port :9000 on net1, db, redis)                  │   │
│   │   - Admin UI, User Portal, API, Embedded Traefik Outpost                          │   │
│   │   - Ingress Domains: https://sso.spencer.lan & https://login.spencer.lan          │   │
│   └─────────────────────────┬───────────────────────────────────┬─────────────────────┘   │
│                             │                                   │                         │
│                             ▼                                   ▼                         │
│   ┌───────────────────────────────────┐               ┌───────────────────────────────┐   │
│   │        pgvector Database          │               │         Valkey Cache          │   │
│   │   - authentik db on :5432 (db)    │               │   - Session/Queue :6379 (redis│   │
│   └─────────────────▲─────────────────┘               └───────────────▲───────────────┘   │
│                     │                                                 │                   │
│   ┌─────────────────┴─────────────────────────────────────────────────┴───────────────┐   │
│   │                 authentik-worker (Background Tasks on db, redis)                  │   │
│   │   - Flow execution, Celery background tasks, notification dispatch                │   │
│   └───────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                           │
└───────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## ⚙️ Ingress & Core Endpoints

| Endpoint | Purpose | Network |
|---|---|---|
| `https://sso.spencer.lan` | Primary LAN User & Admin Authentication Portal | `net1` (:9000) |
| `https://login.spencer.lan` | Secondary LAN Portal Alias | `net1` (:9000) |
| `https://<sso-public-domain>` | Public SSO Authentication Portal (Let's Encrypt) | `net1` (:9000) |
| `https://sso.spencer.lan/if/flow/initial-setup/` | First-time installation setup wizard (`akadmin`) | `net1` (:9000) |
| `http://authentik-server:9000/outpost.goauthentik.io/auth/traefik` | Traefik ForwardAuth validation outpost endpoint | Internal `net1` |

---

## 🚀 Initial Setup & Admin Provisioning

When the containers start for the first time:

1. **Access Initial Setup Wizard**:
   Navigate to:
   ```
   https://sso.spencer.lan/if/flow/initial-setup/
   ```
2. **Configure Superuser (`akadmin`)**:
   - Set a strong master password for the default administrator account `akadmin`.
   - Complete the wizard to enter the Authentik Admin Interface.
3. **Create Regular Accounts**:
   - Navigate to **Directory** ➡️ **Users** ➡️ **Create User**.
   - Create your personal account (e.g. `admin_user`), specify your email, and set your password or invite link.
   - Add the user to the `authentik Admins` group under **Directory** ➡️ **Groups** if administrative privileges are required.

---

## 🛡️ Protecting Applications with Traefik ForwardAuth

To protect any web dashboard (e.g. Hindsight, Traefik Dashboard, or future services) with Authentik:

### Step 1: Create a Provider in Authentik Admin
1. Go to **Applications** ➡️ **Providers** ➡️ **Create**.
2. Select **Proxy Provider**.
3. **Name**: `Hindsight Provider` (or service name).
4. **Mode**: `Forward auth (single application)`.
5. **External Host**: `https://hindsight.spencer.lan`.
6. Click **Finish**.

### Step 2: Create the Application in Authentik Admin
1. Go to **Applications** ➡️ **Applications** ➡️ **Create**.
2. **Name**: `Hindsight`.
3. **Slug**: `hindsight`.
4. **Provider**: Select the `Hindsight Provider` created in Step 1.
5. Click **Create**.

### Step 3: Bind to the Embedded Outpost
1. Go to **Applications** ➡️ **Outposts**.
2. Edit the default **`authentik Embedded Outpost`**.
3. In the **Applications** multi-select field, select your newly created application (e.g. `Hindsight`).
4. Click **Update**.

### Step 4: Add Traefik Labels in `docker-compose.yaml`
Attach the `authentik@file` middleware to the container's Traefik router:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.hindsight.rule=Host(`hindsight.spencer.lan`)"
  - "traefik.http.routers.hindsight.entrypoints=websecure"
  - "traefik.http.routers.hindsight.tls=true"
  - "traefik.http.routers.hindsight.middlewares=authentik@file"
  - "traefik.http.services.hindsight.loadbalancer.server.port=9999"
```

---

## 🔌 Integrating OIDC (OpenID Connect) Applications

For applications that natively support OAuth2/OIDC (e.g. Hermes Agent, Nextcloud, Grafana):

1. In Authentik, an OAuth2/OpenID Provider can be created via Admin UI or programmatically via the **Authentik REST API** (`/api/v3/`):
   - **Endpoint**: `https://<sso-public-domain>/api/v3/providers/oauth2/`
   - **Authorization**: `Bearer <token>`
   - **Redirect URIs**: `https://<hermes-public-domain>/auth/callback` (Mode: `strict`, Type: `authorization`)
   - **Signing Key**: `authentik Self-signed Certificate` (RS256)
   - **Client ID**: `hermes`
2. **Hermes Agent Integration**:
   - **Issuer URL**: `https://<sso-public-domain>/application/o/hermes/`
   - **Discovery Metadata**: `https://<sso-public-domain>/application/o/hermes/.well-known/openid-configuration`
   - **Client ID**: `hermes`
   - **Client Secret**: In `.env` as `HERMES_DASHBOARD_OIDC_CLIENT_SECRET`
   - **Public Callback**: `https://<hermes-public-domain>/auth/callback`
   - Hermes activates its native `self-hosted` OIDC provider plugin, redirecting users seamlessly to Authentik for single sign-on without Traefik proxy middleware interception.

---

## ⚡ Programmatic API Bypass Isolation

Autonomous agent tools and machine-to-machine APIs must not be blocked by SSO redirects. The following endpoints bypass ForwardAuth by omitting the `authentik@file` middleware:

- `https://mcp.spencer.lan/*` (Hermes Model Context Protocol server)
- `https://hermes-api.spencer.lan/*` (Hermes Gateway and worker API)
- `https://llm.spencer.lan/v1/*` (LiteLLM OpenAI-compatible router and health probes)

---

## 🛠️ Operational Commands & Troubleshooting

### Inspect Container Logs
```bash
docker compose logs -f authentik-server
docker compose logs -f authentik-worker
```

### Check Database Connection
```bash
docker exec pgvector psql -U postgres -d authentik -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';"
```

### Test ForwardAuth Endpoint Reachability
```bash
curl -k -I http://authentik-server:9000/outpost.goauthentik.io/auth/traefik
```
Expected response: `HTTP/1.1 401 Unauthorized` or redirect (indicating ForwardAuth outpost is active and listening).

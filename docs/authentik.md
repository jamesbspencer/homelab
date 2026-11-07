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
│   Incoming Request (e.g. https://home.spencer.lan or https://traefik.spencer.lan)       │
│                                              │                                            │
│                                              ▼ ForwardAuth Check                          │
│                     http://authentik-server:9000/outpost.goauthentik.io/auth/traefik      │
│                                              │                                            │
│                        ┌─────────────────────┴─────────────────────┐                      │
│                        │ 200 OK (Authorized)                       │ 302 Redirect         │
│                        ▼                                           ▼                      │
│               Proxied Web Service                     Redirect to Login Portal            │
│               (Homepage, Traefik Dash)                https://sso.spencer.lan/if/flow/... │
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
| `https://<sso-public-domain>` | Public SSO Authentication & Administration Portal | `net1` (:9000) |
| `https://sso.spencer.lan` | Local LAN User & Admin Authentication Portal Alias | `net1` (:9000) |
| `https://login.spencer.lan` | Secondary LAN Portal Alias | `net1` (:9000) |
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

To protect any web dashboard (e.g. Homepage, Dozzle, Traefik Dashboard, or future services) with Authentik:

### Step 1: Create a Provider in Authentik Admin
1. Go to **Applications** ➡️ **Providers** ➡️ **Create**.
2. Select **Proxy Provider**.
3. **Name**: `Homepage Provider` (or service name).
4. **Mode**: `Forward auth (single application)`.
5. **External Host**: `https://home.spencer.lan`.
6. Click **Finish**.

### Step 2: Create the Application in Authentik Admin
1. Go to **Applications** ➡️ **Applications** ➡️ **Create**.
2. **Name**: `Homepage`.
3. **Slug**: `homepage`.
4. **Provider**: Select the `Homepage Provider` created in Step 1.
5. Click **Create**.

### Step 3: Bind to the Embedded Outpost
1. Go to **Applications** ➡️ **Outposts**.
2. Edit the default **`authentik Embedded Outpost`**.
3. In the **Applications** multi-select field, select your newly created application (e.g. `Homepage`).
4. Click **Update**.

### Step 4: Add Traefik Labels in `docker-compose.yaml`
Attach the `authentik@file` middleware to the container's Traefik router:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.homepage.rule=Host(`home.spencer.lan`)"
  - "traefik.http.routers.homepage.entrypoints=websecure"
  - "traefik.http.routers.homepage.tls=true"
  - "traefik.http.routers.homepage.middlewares=authentik@file"
  - "traefik.http.services.homepage-svc.loadbalancer.server.port=3000"
```

---

## 🔌 Integrating OIDC (OpenID Connect) Applications

For applications that natively support OAuth2/OIDC (e.g. Gitea, Nextcloud, Grafana):

1. In Authentik, an OAuth2/OpenID Provider can be created via Admin UI or programmatically via the **Authentik REST API** (`/api/v3/`):
   - **Endpoint**: `https://<sso-public-domain>/api/v3/providers/oauth2/`
   - **Authorization**: `Bearer <token>`
   - **Grant Types**: `["authorization_code", "refresh_token"]` (Required for standard web SSO code flows)
   - **Redirect URIs**: Application callback URLs (Mode: `strict`, Type: `authorization`)
   - **Signing Key**: `authentik Self-signed Certificate` (RS256)
   - **Client ID & Secret**: Application credentials
2. **Archived / Decommissioned Integrations**:
   - **LiteLLM Proxy** (Archived): Formerly used Client ID `litellm`. Retired and replaced by [OmniRoute](omniroute.md).
   - **Hermes Agent** (Archived): Formerly used Client ID `hermes` with issuer `https://<sso-public-domain>/application/o/hermes/`. Retired alongside Hermes Agent.

---

## ⚡ Programmatic API Bypass Isolation

Autonomous agent tools and machine-to-machine APIs must not be blocked by SSO redirects. The following endpoints bypass ForwardAuth by omitting the `authentik@file` middleware:

- `https://llm.spencer.lan/v1/*` (OmniRoute OpenAI & Anthropic compatible router and health probes)

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

---

## 📲 Real-Time Push Notifications (ntfy)

Authentik is integrated with the homelab's **ntfy** push notification gateway to dispatch real-time security alerts:
- **Notification Transport**: `ntfy-alerts` (`webhook_slack` mode targeting `http://ntfy:80/alerts` over Docker network `net1`)
- **Configured Security Rules & Matchers**:
  - `notify-login-failed`: Dispatches alerts on failed authentication attempts (`action: login_failed`)
  - `notify-suspicious-request`: Dispatches alerts on anomalous or suspicious HTTP requests (`action: suspicious_request`)
  - Core system health: Linked to configuration errors, configuration warnings, software updates, and policy/system exceptions.
- **Verification Command**:
  ```bash
  docker exec authentik-server ak shell -c "from authentik.core.models import User; from authentik.events.models import NotificationTransport, Notification; t = NotificationTransport.objects.get(name='ntfy-alerts'); u = User.objects.first(); n = Notification(body='Test security alert from Authentik', user=u, severity='warning'); t.send(n)"
  ```

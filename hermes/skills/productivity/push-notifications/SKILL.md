---
name: push-notifications
description: "Send push notifications to user devices via ntfy."
version: 1.0.0
author: "Hermes Agent & Spencer"
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [Notifications, Ntfy, Push, Alerts, Webhook]
prerequisites:
  commands: [curl]
---

# Push Notifications (ntfy)

Send instant push notifications and alerts to Spencer's mobile and desktop devices through the self-hosted ntfy gateway.

## When to Use

- Dispatching completion alerts when long-running background tasks, data extractions, or code builds finish.
- Pushing urgent notifications about system errors, service outages, or security anomalies.
- Proactively alerting the user when requested (e.g. "let me know when X happens").
- DO NOT use for routine conversational replies or minor step-by-step progress updates.

## Prerequisites

- Network access to internal ntfy endpoint `http://ntfy:80` (available on the Docker `ai` network) or external `https://push.spencer.lan`.
- No authentication tokens required for internal LAN/network publishing.

## How to Run

### 1. Basic Notification
To send a message to the default `hermes` topic:
```bash
curl -s -d "Backup completed successfully." http://ntfy:80/hermes
```

### 2. High-Priority Alert with Metadata
To send an alert with custom title, priority, tags, and action buttons:
```bash
curl -s \
  -H "Title: Critical System Alert" \
  -H "Priority: high" \
  -H "Tags: warning,rotating_light" \
  -H "Click: https://hermes.spencer.lan" \
  -d "Memory consumption exceeded 90%." \
  http://ntfy:80/hermes
```

### 3. Using the Helper Script
If available in the environment:
```bash
/opt/data/scripts/notify.sh -t "Task Completed" -p 3 -g "white_check_mark,robot" hermes "Autonomous task finished."
```

## Available Topics

- `hermes`: AI Agent task completions, status reports, and autonomous findings.
- `alerts`: Security events, CrowdSec bans, and system warnings.
- `backups`: Database dumps and snapshot archive reports.

## Priority Scale

- `min` / `1`: Silent notification, no vibration or sound.
- `low` / `2`: Low-priority chime.
- `default` / `3`: Standard notification sound & vibrate.
- `high` / `4`: High-urgency alert with prominent popup.
- `urgent` / `5`: Maximum urgency persistent alarm.

## Pitfalls

- Avoid spaces in `-H "Tags: tag1,tag2"` argument (comma-separated, no spaces).
- Topic names are case-sensitive and must be URL-safe (lowercase ASCII recommended).

## Verification

Send a test ping and verify HTTP 200 with JSON receipt:
```bash
curl -s -d "Verification ping from Hermes" http://ntfy:80/hermes | grep -q '"event":"message"' && echo "Notification sent successfully."
```

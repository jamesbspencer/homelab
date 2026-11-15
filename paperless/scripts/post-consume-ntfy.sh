#!/bin/bash
# Paperless-ngx post-consumption script: send push notifications to ntfy
DOCUMENT_TITLE="${DOCUMENT_TITLE:-Unknown Document}"
DOCUMENT_ID="${DOCUMENT_ID:-0}"
DOCUMENT_URL="https://paperless.spencer.lan/documents/${DOCUMENT_ID}/details"

curl -s \
  -H "Title: Paperless: Document Ingested" \
  -H "Tags: page_facing_up,paperless" \
  -H "Click: ${DOCUMENT_URL}" \
  -d "Successfully processed and indexed: ${DOCUMENT_TITLE}" \
  "http://ntfy:80/paperless" > /dev/null 2>&1 || true

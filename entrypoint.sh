#!/bin/bash
set -e

chown -R openclaw:openclaw /data
chmod 700 /data

if [ ! -d /data/.linuxbrew ]; then
  cp -a /home/linuxbrew/.linuxbrew /data/.linuxbrew
fi

rm -rf /home/linuxbrew/.linuxbrew
ln -sfn /data/.linuxbrew /home/linuxbrew/.linuxbrew

# ── Claw by Aditor: Inject workspace template on first run ──────────
WORKSPACE="${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"
WORKSPACE_REPO="${CLAW_WORKSPACE_REPO:-}"

if [ -n "$WORKSPACE_REPO" ] && [ ! -f "$WORKSPACE/.workspace-init" ]; then
  echo "[claw-setup] Injecting workspace from $WORKSPACE_REPO..."
  mkdir -p "$WORKSPACE"
  TMPDIR=$(mktemp -d)
  if git clone --depth=1 "$WORKSPACE_REPO" "$TMPDIR" 2>/dev/null; then
    # Copy workspace files, don't overwrite existing
    cp -rn "$TMPDIR"/* "$WORKSPACE"/ 2>/dev/null || true
    cp -rn "$TMPDIR"/.* "$WORKSPACE"/ 2>/dev/null || true
    rm -rf "$TMPDIR"
    touch "$WORKSPACE/.workspace-init"
    # Run skills installation if present
    if [ -x "$WORKSPACE/.openclaw-skills/install.sh" ]; then
      echo "[claw-setup] Running skills installation..."
      bash "$WORKSPACE/.openclaw-skills/install.sh"
    fi
    echo "[claw-setup] Workspace initialized from repo"
  else
    echo "[claw-setup] WARNING: Could not clone workspace repo, using defaults"
    rm -rf "$TMPDIR"
  fi
fi

# ── Inject BOOTSTRAP.md from env if provided and not yet consumed ───
if [ -n "$CLAW_BOOTSTRAP_MD" ] && [ ! -f "$WORKSPACE/.bootstrap-done" ]; then
  mkdir -p "$WORKSPACE"
  if [ ! -f "$WORKSPACE/BOOTSTRAP.md" ]; then
    echo "$CLAW_BOOTSTRAP_MD" > "$WORKSPACE/BOOTSTRAP.md"
    echo "[claw-setup] BOOTSTRAP.md injected"
  fi
fi

chown -R openclaw:openclaw /data

# ── Claw by Aditor: Post-setup cost-saving config ──────────────────
# These run in background after gateway starts, applying cost defaults
if [ -n "$CLAW_HEARTBEAT_MODEL" ] || [ -n "$CLAW_HEARTBEAT_EVERY" ]; then
  (
    # Wait for gateway to be ready
    sleep 30
    OPENCLAW_BIN=$(which openclaw 2>/dev/null || echo "node /usr/local/lib/node_modules/openclaw/dist/entry.js")
    
    if [ -n "$CLAW_HEARTBEAT_MODEL" ]; then
      $OPENCLAW_BIN config set agents.defaults.heartbeat.model "$CLAW_HEARTBEAT_MODEL" 2>/dev/null && \
        echo "[claw-setup] Heartbeat model set to $CLAW_HEARTBEAT_MODEL" || true
    fi
    
    if [ -n "$CLAW_HEARTBEAT_EVERY" ]; then
      $OPENCLAW_BIN config set agents.defaults.heartbeat.every "$CLAW_HEARTBEAT_EVERY" 2>/dev/null && \
        echo "[claw-setup] Heartbeat interval set to $CLAW_HEARTBEAT_EVERY" || true
    fi
  ) &
fi

exec gosu openclaw node src/server.js

# ── Claw by Aditor: Auto-approve first Telegram pairing ─────────────
if [ "$CLAW_AUTO_APPROVE_FIRST" = "true" ]; then
  (
    echo "[Auto-Pair] Waiting for first pairing request..."
    sleep 90  # Wait for gateway to fully start
    
    # Poll for pairing code (wait up to 5 minutes)
    for i in {1..30}; do
      PAIRING_CODE=$(timeout 10 openclaw pairing list telegram 2>/dev/null | grep -o 'Code: [A-Z0-9]*' | head -1 | cut -d' ' -f2)
      
      if [ -n "$PAIRING_CODE" ]; then
        echo "[Auto-Pair] Found pairing code: $PAIRING_CODE"
        if openclaw pairing approve telegram "$PAIRING_CODE" 2>/dev/null; then
          echo "[Auto-Pair] ✓ First Telegram pairing approved: $PAIRING_CODE"
          break
        else
          echo "[Auto-Pair] Failed to approve, retrying..."
        fi
      fi
      
      sleep 10
    done
    
    if [ -z "$PAIRING_CODE" ]; then
      echo "[Auto-Pair] No pairing request found after 5 minutes"
    fi
  ) &
fi


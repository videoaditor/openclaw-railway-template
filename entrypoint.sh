#!/bin/bash
set -e

# ── Fix permissions FIRST (before writing config) ──────────────────
chown -R openclaw:openclaw /data
chmod 700 /data

if [ ! -d /data/.linuxbrew ]; then
  cp -a /home/linuxbrew/.linuxbrew /data/.linuxbrew
fi

rm -rf /home/linuxbrew/.linuxbrew
ln -sfn /data/.linuxbrew /home/linuxbrew/.linuxbrew

# ── Claw by Aditor: Write openclaw.json on first boot ──────────────
CONFIG_DIR="/data/.openclaw"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"

if [ ! -f "$CONFIG_FILE" ]; then
  if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$OPENCLAW_DEFAULT_MODEL" ] && [ -n "$TELEGRAM_OWNER_ID" ]; then
    echo "[claw-setup] Writing openclaw.json with owner approval..."
    mkdir -p "$CONFIG_DIR"
    
    # Write the config file with proper JSON structure
    cat > "$CONFIG_FILE" << 'EOCFG'
{
  "agents": {
    "defaults": {
      "model": "MODEL_PLACEHOLDER",
      "thinking": "off"
    }
  },
  "channels": {
    "telegram": {
      "default": {
        "token": "TOKEN_PLACEHOLDER",
        "allowFrom": ["OWNER_ID_PLACEHOLDER"]
      }
    }
  }
}
EOCFG
    
    # Replace placeholders (safer than trying to inject into heredoc)
    sed -i "s|MODEL_PLACEHOLDER|$OPENCLAW_DEFAULT_MODEL|g" "$CONFIG_FILE"
    sed -i "s|TOKEN_PLACEHOLDER|$TELEGRAM_BOT_TOKEN|g" "$CONFIG_FILE"
    sed -i "s|OWNER_ID_PLACEHOLDER|$TELEGRAM_OWNER_ID|g" "$CONFIG_FILE"
    
    # FIX: Set ownership to openclaw user (UID 1000)
    chown -R openclaw:openclaw "$CONFIG_DIR"
    
    echo "[claw-setup] ✓ openclaw.json created with owner $TELEGRAM_OWNER_ID"
  else
    echo "[claw-setup] Skipping config (missing TOKEN, MODEL, or OWNER_ID)"
  fi
fi

# ── Inject workspace template ───────────────────────────────────────
WORKSPACE="${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"
WORKSPACE_REPO="${CLAW_WORKSPACE_REPO:-}"

if [ -n "$WORKSPACE_REPO" ] && [ ! -f "$WORKSPACE/.workspace-init" ]; then
  echo "[claw-setup] Injecting workspace from $WORKSPACE_REPO..."
  mkdir -p "$WORKSPACE"
  TMPDIR=$(mktemp -d)
  if git clone --depth=1 "$WORKSPACE_REPO" "$TMPDIR" 2>/dev/null; then
    cp -rn "$TMPDIR"/* "$WORKSPACE"/ 2>/dev/null || true
    cp -rn "$TMPDIR"/.* "$WORKSPACE"/ 2>/dev/null || true
    rm -rf "$TMPDIR"
    touch "$WORKSPACE/.workspace-init"
    echo "[claw-setup] Workspace initialized"
    
    # Run skills installation
    if [ -x "$WORKSPACE/.openclaw-skills/install.sh" ]; then
      echo "[claw-setup] Running skills installation..."
      bash "$WORKSPACE/.openclaw-skills/install.sh"
    fi
  else
    echo "[claw-setup] WARNING: Could not clone workspace repo"
    rm -rf "$TMPDIR"
  fi
fi

# FIX: Final permission sweep (Gemini's master key)
chown -R 1000:1000 /data

# Start server as openclaw user (UID 1000)
exec gosu openclaw node src/server.js

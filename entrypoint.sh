#!/bin/bash
set -e

chown -R openclaw:openclaw /data
chmod 700 /data

if [ ! -d /data/.linuxbrew ]; then
  cp -a /home/linuxbrew/.linuxbrew /data/.linuxbrew
fi

rm -rf /home/linuxbrew/.linuxbrew
ln -sfn /data/.linuxbrew /home/linuxbrew/.linuxbrew

# ── Claw by Aditor: Pre-configure OpenClaw on first boot ───────────
CONFIG_DIR="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
CONFIG_FILE="$CONFIG_DIR/config.json"

if [ ! -f "$CONFIG_FILE" ] && [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$OPENCLAW_DEFAULT_MODEL" ]; then
  echo "[claw-setup] Writing OpenClaw config..."
  mkdir -p "$CONFIG_DIR"
  
  cat > "$CONFIG_FILE" << EOCFG
{
  "agents": {
    "defaults": {
      "model": "${OPENCLAW_DEFAULT_MODEL}",
      "thinking": "off"
    }
  },
  "channels": {
    "telegram": {
      "default": {
        "token": "${TELEGRAM_BOT_TOKEN}"
      }
    }
  }
}
EOCFG
  
  chown openclaw:openclaw "$CONFIG_FILE"
  echo "[claw-setup] ✓ OpenClaw pre-configured"
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

chown -R openclaw:openclaw /data

exec gosu openclaw node src/server.js

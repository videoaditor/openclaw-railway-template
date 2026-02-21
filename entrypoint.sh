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

exec gosu openclaw node src/server.js

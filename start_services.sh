#!/usr/bin/env bash
# ==============================================================================
# Service Supervisor for TabbyAPI Container
# ==============================================================================
#
# DESCRIPTION:
# This script is the designated ENTRYPOINT for the container. Its primary
# responsibilities are:
#   1. Performing initial, one-time setup as the root user.
#   2. Dropping privileges to a non-root user ('somneruser') for enhanced security.
#   3. Starting and supervising all necessary background services (tailscaled,
#      TabbyAPI, Caddy).
#   4. Ensuring a clean shutdown if any supervised service fails.
#
# AI-NOTE: This script follows a "supervisor" pattern. It launches several
# background processes and uses `wait -n` to pause until one of them exits,
# at which point it terminates the container. This is a lightweight alternative
# to more complex init systems like systemd.
#
# ==============================================================================

# ------------------------------------------------------------------------------
# Script Configuration and Safety
# ------------------------------------------------------------------------------
# `set -e`: Exit immediately if a command exits with a non-zero status.
# `set -u`: Treat unset variables as an error when substituting.
# `set -o pipefail`: The return value of a pipeline is the status of the last
#                    command to exit with a non-zero status, or zero if no
#                    command exited with a non-zero status.
set -euo pipefail

# ==============================================================================
# Initial Root-Level Setup & Privilege Drop
# ==============================================================================
# RATIONALE: The script starts as the `root` user. This block performs actions
# that require root privileges (like creating state directories) before
# re-executing itself as the unprivileged `somneruser` using `gosu`.
# This is a critical security best practice. All subsequent commands will run
# as the non-root user.
# ------------------------------------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
    # Create state and socket directories for Tailscale, owned by the runtime user.
    TS_STATE_DIR="/home/somneruser/.local/state/tailscale"
    TS_SOCKET_DIR="/home/somneruser/.local/run/tailscale"
    mkdir -p "$TS_STATE_DIR" "$TS_SOCKET_DIR"
    chown -R somneruser:somneruser "$TS_STATE_DIR" "$TS_SOCKET_DIR"
    # Re-execute this script as 'somneruser'
    exec gosu somneruser "$0" "$@"
fi

# ==============================================================================
# --- From this point on, the script is running as the non-root 'somneruser' ---
# ==============================================================================

# ==============================================================================
# Enhanced Runtime Diagnostics
# ==============================================================================
# RATIONALE: This block provides a quick "health check" of the Python environment
# upon container startup. It verifies that key dependencies can be imported,
# allowing for fast failure detection if the environment is misconfigured.
# It runs *before* the main services to provide clear, early diagnostic output.
# ------------------------------------------------------------------------------
echo ">>> Final Import Test:"
python3.11 -c "import torch, flash_attn, exllamav3; print('✅ All key DEPENDENCIES imported successfully!')" || { echo "❌ Dependency import test failed!"; exit 1; }
echo "=== End Diagnostics ==="

# ==============================================================================
# Service Definitions and Startup
# ==============================================================================
# Define state directory paths for user-level services.
TS_STATE_DIR="/home/somneruser/.local/state/tailscale"
TS_SOCKET_DIR="/home/somneruser/.local/run/tailscale"
# Allow TAILSCALE_AUTHKEY to be passed in as an environment variable, but don't fail if it's not set.
: "${TAILSCALE_AUTHKEY:=}"

# 1. Start Tailscale Daemon
# The tailscaled process is started in the background (&).
echo "[INFO] Starting tailscaled..." >&2
tailscaled \
  --state="${TS_STATE_DIR}/tailscaled.state" \
  --socket="${TS_SOCKET_DIR}/tailscaled.sock" \
  --tun=userspace-networking &
TAILSCALED_PID=$!
# Give the daemon a moment to initialize.
sleep 5

# 2. Initialize Tailscale Interface
# Connects the container to the Tailscale network using the provided auth key if available.
echo "[INFO] Bringing up Tailscale interface..." >&2
tailscale --socket="${TS_SOCKET_DIR}/tailscaled.sock" up \
  --hostname="runpod-forge" \
  --accept-dns=false \
  ${TAILSCALE_AUTHKEY:+--auth-key=${TAILSCALE_AUTHKEY}}

# 3. Launch TabbyAPI Server
# ARCHITECTURAL NOTE: We launch the server by executing `main.py` directly.
# This project is structured as a script-based application, not a standard
# installable Python package, so `python -m tabbyapi.main` will not work.
echo "[INFO] Starting TabbyAPI server..." >&2

# Explicitly change to the source directory to ensure the script's working
# directory is correct, allowing it to find its modules and config files.
cd /opt/tabbyapi-src

# --- Pre-Launch Sanity Check ---
# Log the context right before launching the Python script to aid in debugging.
echo "[SANITY CHECK] Current user is: $(whoami)"
echo "[SANITY CHECK] Current directory is: $(pwd)"
echo "[SANITY CHECK] Contents of current directory:"
ls -la
echo "[SANITY CHECK] PATH variable is: $PATH"
echo "--- End Sanity Check ---"

# Launch the server in the background.
python3.11 main.py --config config.yml &
TABBY_PID=$!

# 4. Health Check Loop
# RATIONALE: This loop prevents the script from proceeding until the TabbyAPI
# server is actually listening on its port. It also provides an early exit if
# the server process crashes immediately upon startup.
echo "[INFO] Waiting for TabbyAPI to become healthy on port 5000..." >&2
for i in {1..120}; do
  if ss -ltn | grep -q ':5000'; then
    echo "[INFO] TabbyAPI is listening on :5000 (PID $TABBY_PID)." >&2
    break
  fi
  if ! ps -p $TABBY_PID &>/dev/null; then
    echo "[ERROR] TabbyAPI (PID $TABBY_PID) crashed during startup." >&2
    exit 1
  fi
  sleep 1
done

# Fail fatally if the server didn't start after the timeout.
if ! ss -ltn | grep -q ':5000'; then
  echo "[FATAL] TabbyAPI failed to start within 30 seconds." >&2
  exit 1
fi

# 5. Launch Caddy Reverse Proxy
# Starts the Caddy server in the background to act as a reverse proxy.
echo "[INFO] Starting Caddy reverse proxy..." >&2
caddy run --config /etc/caddy/Caddyfile &
CADDY_PID=$!

echo "[INFO] All services ready. PIDs => tailscaled:${TAILSCALED_PID}, tabby:${TABBY_PID}, caddy:${CADDY_PID}" >&2

# 6. Process Supervision
# `wait -n` will pause the script until ANY of the background jobs exit.
# This keeps the container alive and ensures a clean shutdown if any service fails.
wait -n $TAILSCALED_PID $TABBY_PID $CADDY_PID
echo "[INFO] A supervised process has exited. Shutting down."

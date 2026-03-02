#!/usr/bin/env bash
set -euo pipefail

# SentinelOS: bring up MATE panel + desktop on an already-running LightDM/Xorg session
# Usage: run from tty1 as the live user (e.g., sentinel)
#   bash sentinelos-start-mate-desktop.sh
#
# This script:
#  - Finds the current mate-session for the target user
#  - Extracts DISPLAY/XAUTHORITY/DBUS_SESSION_BUS_ADDRESS/XDG_RUNTIME_DIR from its environment
#  - Starts mate-panel and caja --force-desktop using the same session credentials
#  - Attempts to switch to VT7

TARGET_USER="${TARGET_USER:-${SUDO_USER:-${USER}}}"

log() { printf '[SentinelOS] %s\n' "$*"; }
warn() { printf '[SentinelOS][WARN] %s\n' "$*" >&2; }

# Find latest mate-session for the user
PID="$(pgrep -u "$TARGET_USER" -n mate-session || true)"
if [[ -z "${PID}" ]]; then
  warn "No mate-session found for user '${TARGET_USER}'."
  warn "Is LightDM autologin/session actually started? Try: ps -ef | grep -E 'lightdm|Xorg|mate-session'"
  exit 1
fi

ENVFILE="/proc/${PID}/environ"
if [[ ! -r "${ENVFILE}" ]]; then
  warn "Cannot read ${ENVFILE}. (PID=${PID})"
  exit 1
fi

get_env() {
  local key="$1"
  tr '\0' '\n' < "${ENVFILE}" | awk -F= -v k="${key}" '$1==k{print substr($0, index($0,$2)); exit}'
}

DISPLAY_VAL="$(get_env DISPLAY || true)"
XAUTH_VAL="$(get_env XAUTHORITY || true)"
DBUS_VAL="$(get_env DBUS_SESSION_BUS_ADDRESS || true)"
XDG_RUNTIME_VAL="$(get_env XDG_RUNTIME_DIR || true)"

[[ -n "${DISPLAY_VAL}" ]] || DISPLAY_VAL=":0"
[[ -n "${XAUTH_VAL}" ]] || XAUTH_VAL="/home/${TARGET_USER}/.Xauthority"

log "mate-session PID: ${PID}"
log "DISPLAY=${DISPLAY_VAL}"
log "XAUTHORITY=${XAUTH_VAL}"
[[ -n "${DBUS_VAL}" ]] && log "DBUS_SESSION_BUS_ADDRESS is set" || warn "DBUS_SESSION_BUS_ADDRESS not found in mate-session env (panel may still start, but some integrations may fail)"
[[ -n "${XDG_RUNTIME_VAL}" ]] && log "XDG_RUNTIME_DIR=${XDG_RUNTIME_VAL}" || warn "XDG_RUNTIME_DIR not found in mate-session env"

if [[ ! -f "${XAUTH_VAL}" ]]; then
  warn "Xauthority file not found: ${XAUTH_VAL}"
  warn "If Xorg uses a different -auth file, you may need to merge the cookie into ~/.Xauthority."
else
  log "Xauthority file exists: ${XAUTH_VAL}"
fi

# Run command as TARGET_USER if needed
run_as_target_user() {
  if [[ "${USER}" == "${TARGET_USER}" && "${EUID}" -ne 0 ]]; then
    bash -lc "$*"
    return
  fi

  if command -v runuser >/dev/null 2>&1 && [[ "${EUID}" -eq 0 ]]; then
    runuser -u "${TARGET_USER}" -- bash -lc "$*"
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo -u "${TARGET_USER}" bash -lc "$*"
    return
  fi

  if command -v su >/dev/null 2>&1; then
    su -s /bin/bash - "${TARGET_USER}" -c "$*"
    return
  fi

  warn "No method available to run commands as ${TARGET_USER} (need sudo/runuser/su)."
  exit 1
}

# Start MATE components
log "Starting mate-panel and caja on ${DISPLAY_VAL} ..."
run_as_target_user "env DISPLAY='${DISPLAY_VAL}' XAUTHORITY='${XAUTH_VAL}' DBUS_SESSION_BUS_ADDRESS='${DBUS_VAL}' XDG_RUNTIME_DIR='${XDG_RUNTIME_VAL}' mate-panel --replace >/dev/null 2>&1 & disown || true"
run_as_target_user "env DISPLAY='${DISPLAY_VAL}' XAUTHORITY='${XAUTH_VAL}' DBUS_SESSION_BUS_ADDRESS='${DBUS_VAL}' XDG_RUNTIME_DIR='${XDG_RUNTIME_VAL}' caja --force-desktop >/dev/null 2>&1 & disown || true"

sleep 1

# Attempt to switch to VT7 (where Xorg usually lives)
if command -v chvt >/dev/null 2>&1; then
  log "Switching to VT7 (chvt 7) ..."
  if [[ "${EUID}" -eq 0 ]]; then
    chvt 7 || true
  elif command -v sudo >/dev/null 2>&1; then
    sudo chvt 7 || true
  else
    warn "Need sudo/root to run chvt. Try Ctrl+Alt+F7 manually."
  fi
else
  warn "chvt not found. Try Ctrl+Alt+F7 manually."
fi

log "Done. If the screen is still blank, run these from tty1 for diagnostics:"
log "  ps -ef | egrep 'lightdm|Xorg|mate-session|mate-panel|caja|marco' | grep -v egrep"
log "  sudo tail -n 200 /var/log/lightdm/lightdm.log"
log "  sudo tail -n 200 /var/log/lightdm/x-0.log"

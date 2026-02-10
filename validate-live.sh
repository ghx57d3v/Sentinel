#!/usr/bin/env bash
# Sentinel OS – Live Session Validation
# Must be run from a LIVE boot

set -euo pipefail

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

pass() {
  echo "[ OK ] $*"
}

echo "=== Sentinel OS LIVE Validation ==="

# -------------------------------------------------
# Check we are actually in live mode
# -------------------------------------------------
if ! grep -q 'boot=live' /proc/cmdline; then
  fail "System is not booted in LIVE mode"
fi
pass "Detected LIVE boot mode"

# -------------------------------------------------
# Check live user exists
# -------------------------------------------------
LIVE_USER="user"
id "$LIVE_USER" >/dev/null 2>&1 || fail "Live user '$LIVE_USER' does not exist"
pass "Live user exists"

# -------------------------------------------------
# Live user must NOT be admin
# -------------------------------------------------
if groups "$LIVE_USER" | grep -qw sudo; then
  fail "Live user has sudo privileges"
fi
pass "Live user has no sudo privileges"

# -------------------------------------------------
# Live user password must be locked
# -------------------------------------------------
if passwd -S "$LIVE_USER" | grep -q 'P'; then
  fail "Live user password is not locked"
fi
pass "Live user password is locked"

# -------------------------------------------------
# Autologin is allowed ONLY in live
# -------------------------------------------------
if [ ! -f /etc/lightdm/lightdm.conf.d/60-sentinel-live-autologin.conf ]; then
  fail "Live autologin config missing"
fi
pass "Live autologin config present"

# -------------------------------------------------
# Firewall must be active even in live
# -------------------------------------------------
command -v nft >/dev/null 2>&1 || fail "nftables not installed"
nft list ruleset | grep -q 'table inet sentinel' || fail "Sentinel firewall rules not loaded"
pass "Sentinel firewall active"

# -------------------------------------------------
# AppArmor should be enabled (enforcing is acceptable but not required in live)
# -------------------------------------------------
command -v aa-status >/dev/null 2>&1 || fail "AppArmor tools missing"
aa-status | grep -q "apparmor is enabled" || fail "AppArmor not enabled"
pass "AppArmor enabled"

# -------------------------------------------------
# Visible LIVE warning (best-effort)
# -------------------------------------------------
if ! grep -R "SENTINEL LIVE" /etc/dconf/db/local.d >/dev/null 2>&1; then
  fail "LIVE warning banner not configured"
fi
pass "LIVE warning banner configured"

echo
echo "[SUCCESS] LIVE validation passed"
exit 0
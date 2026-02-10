#!/usr/bin/env bash
# Sentinel OS – Installed System Validation
# Must NOT be run in live mode

set -euo pipefail

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

pass() {
  echo "[ OK ] $*"
}

echo "=== Sentinel OS INSTALLED Validation ==="

# -------------------------------------------------
# Ensure NOT live mode
# -------------------------------------------------
if grep -q 'boot=live' /proc/cmdline; then
  fail "System is running in LIVE mode"
fi
pass "Detected installed system"

# -------------------------------------------------
# Sentinel packages must be installed
# -------------------------------------------------
REQUIRED_PKGS=(
  sentinel-release
  sentinel-hardening
  sentinel-firewall
  sentinel-auth
)

for pkg in "${REQUIRED_PKGS[@]}"; do
  dpkg -s "$pkg" >/dev/null 2>&1 || fail "Required package missing: $pkg"
done
pass "All Sentinel policy packages installed"

# -------------------------------------------------
# Firewall validation
# -------------------------------------------------
command -v nft >/dev/null 2>&1 || fail "nftables not installed"
nft list ruleset | grep -q 'table inet sentinel' || fail "Sentinel firewall rules not active"
pass "Firewall active with Sentinel rules"

# -------------------------------------------------
# AppArmor enforcing
# -------------------------------------------------
command -v aa-status >/dev/null 2>&1 || fail "AppArmor tools missing"
aa-status | grep -q "profiles are in enforce mode" || fail "AppArmor not enforcing"
pass "AppArmor enforcing"

# -------------------------------------------------
# PAM faillock active
# -------------------------------------------------
if ! faillog -a >/dev/null 2>&1; then
  fail "faillock/faillog not functioning"
fi
pass "PAM faillock operational"

# -------------------------------------------------
# Umask policy
# -------------------------------------------------
EXPECTED_UMASK="0027"
CURRENT_UMASK="$(umask)"
[ "$CURRENT_UMASK" = "$EXPECTED_UMASK" ] || fail "Umask is $CURRENT_UMASK (expected $EXPECTED_UMASK)"
pass "Umask policy enforced"

# -------------------------------------------------
# Unattended upgrades enabled
# -------------------------------------------------
systemctl is-enabled unattended-upgrades.service >/dev/null 2>&1 || \
  fail "unattended-upgrades not enabled"
pass "Automatic security updates enabled"

# -------------------------------------------------
# No unexpected listening ports
# -------------------------------------------------
LISTENING="$(ss -lntup | awk 'NR>1 {print}')"
if [ -n "$LISTENING" ]; then
  echo "[INFO] Listening sockets detected:"
  ss -lntup
  fail "Unexpected listening ports present"
fi
pass "No unexpected listening network services"

# -------------------------------------------------
# SSH policy (only if installed)
# -------------------------------------------------
if dpkg -s openssh-server >/dev/null 2>&1; then
  dpkg -s sentinel-ssh >/dev/null 2>&1 || fail "openssh-server installed without sentinel-ssh"
  pass "SSH installed and governed by sentinel-ssh"
else
  pass "SSH not installed (acceptable)"
fi

echo
echo "[SUCCESS] INSTALLED system validation passed"
exit 0
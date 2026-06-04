#!/bin/bash
# MacbyeDPI DNS Redirector — uninstall script
# Stops the daemon, restores original DNS settings, removes all installed files.
#
# Usage:  sudo ./uninstall.sh

set -e

PLIST_DIR="/Library/LaunchDaemons"
PLIST_LABEL="com.macbyedpi.dnsredir"
PLIST_FILE="${PLIST_DIR}/${PLIST_LABEL}.plist"
BINARY_DST="/usr/local/bin/macbyedpi_dnsredir"
SAVED_DNS_FILE="/usr/local/etc/macbyedpi_saved_dns.conf"

if [[ $EUID -ne 0 ]]; then
    echo "Error: run as root:  sudo ./uninstall.sh"
    exit 1
fi

echo "=== MacbyeDPI DNS Redirector Uninstall ==="
echo ""

# Stop and unload daemon
if [[ -f "${PLIST_FILE}" ]]; then
    echo "[1/4] Stopping daemon..."
    launchctl unload "${PLIST_FILE}" 2>/dev/null || true
    rm -f "${PLIST_FILE}"
    echo "Daemon stopped and removed."
else
    echo "[1/4] Daemon not found (already removed?)."
fi

# Restore DNS
echo ""
echo "[2/4] Restoring original DNS settings..."
if [[ -f "${SAVED_DNS_FILE}" ]]; then
    SERVICE=$(grep "^SERVICE=" "${SAVED_DNS_FILE}" | cut -d= -f2-)
    DNS=$(grep "^DNS=" "${SAVED_DNS_FILE}" | cut -d= -f2-)
    echo "Restoring '${SERVICE}' DNS to: ${DNS}"
    if [[ "$DNS" == "Empty" || -z "$DNS" ]]; then
        networksetup -setdnsservers "${SERVICE}" "Empty"
    else
        # DNS might be multi-line; convert to space-separated
        DNS_ONELINE=$(echo "$DNS" | tr '\n' ' ')
        # shellcheck disable=SC2086
        networksetup -setdnsservers "${SERVICE}" ${DNS_ONELINE}
    fi
    rm -f "${SAVED_DNS_FILE}"
    echo "DNS restored."
else
    echo "No saved DNS config found at ${SAVED_DNS_FILE}."
    echo "Please restore your DNS settings manually in:"
    echo "  System Settings → Network → [interface] → Details → DNS"
fi

# Flush DNS cache
dscacheutil -flushcache
killall -HUP mDNSResponder 2>/dev/null || true

# Remove binary
echo ""
echo "[3/4] Removing binary..."
if [[ -f "${BINARY_DST}" ]]; then
    rm -f "${BINARY_DST}"
    echo "Removed ${BINARY_DST}."
else
    echo "Binary not found (already removed?)."
fi

# Remove logs
echo ""
echo "[4/4] Removing logs..."
rm -f /var/log/macbyedpi_dnsredir.log /var/log/macbyedpi_dnsredir_err.log
echo "Logs removed."

echo ""
echo "=== Uninstall complete ==="

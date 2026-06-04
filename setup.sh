#!/bin/bash
# MacbyeDPI DNS Redirector — setup script
# Builds the binary, installs it, configures macOS DNS, and registers a launchd daemon.
#
# Usage:
#   sudo ./setup.sh --dns-addr 77.88.8.8 --dns-port 1253
#   sudo ./setup.sh --dns-addr 8.8.8.8   --dns-port 53
#
# To uninstall:
#   sudo ./uninstall.sh

set -e

INSTALL_DIR="/usr/local/bin"
PLIST_DIR="/Library/LaunchDaemons"
PLIST_LABEL="com.macbyedpi.dnsredir"
PLIST_FILE="${PLIST_DIR}/${PLIST_LABEL}.plist"
BINARY_NAME="macbyedpi_dnsredir"
BINARY_SRC="$(cd "$(dirname "$0")" && pwd)/${BINARY_NAME}"
BINARY_DST="${INSTALL_DIR}/${BINARY_NAME}"
SAVED_DNS_FILE="/usr/local/etc/macbyedpi_saved_dns.conf"

DNS_ADDR=""
DNS_PORT="53"

# --------------------------------------------------------------------------
# Parse arguments
# --------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dns-addr) DNS_ADDR="$2"; shift 2 ;;
        --dns-port) DNS_PORT="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: sudo $0 --dns-addr <IP> [--dns-port <port>]"
            echo ""
            echo "  --dns-addr <IP>    Upstream DNS server to forward queries to"
            echo "  --dns-port <port>  Upstream DNS port [default: 53]"
            echo ""
            echo "Recommended upstreams (non-standard port = bypasses ISP interception):"
            echo "  77.88.8.8  port 1253   (Yandex DNS — same as goodbyeDPI default)"
            echo "  8.8.8.8    port 53     (Google DNS — may still be intercepted)"
            echo "  1.1.1.1    port 53     (Cloudflare)"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -z "$DNS_ADDR" ]]; then
    echo "Error: --dns-addr is required."
    echo "Run: sudo $0 --help"
    exit 1
fi

# --------------------------------------------------------------------------
# Must run as root
# --------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "Error: this script must be run as root."
    echo "Run: sudo $0 --dns-addr $DNS_ADDR --dns-port $DNS_PORT"
    exit 1
fi

echo "=== MacbyeDPI DNS Redirector Setup ==="
echo ""
echo "Upstream DNS : ${DNS_ADDR}:${DNS_PORT}"
echo ""

# --------------------------------------------------------------------------
# Step 1: Build
# --------------------------------------------------------------------------
echo "[1/5] Building..."
cd "$(dirname "$0")"
make clean >/dev/null 2>&1 || true
make

# --------------------------------------------------------------------------
# Step 2: Install binary
# --------------------------------------------------------------------------
echo ""
echo "[2/5] Installing binary to ${BINARY_DST}..."
mkdir -p "${INSTALL_DIR}"
cp "${BINARY_SRC}" "${BINARY_DST}"
chmod 755 "${BINARY_DST}"

# --------------------------------------------------------------------------
# Step 3: Detect active network service and save current DNS
# --------------------------------------------------------------------------
echo ""
echo "[3/5] Detecting network interface and saving current DNS settings..."

# Find the primary active network service (first one with a router)
PRIMARY_SERVICE=""
while IFS= read -r service; do
    # Skip empty lines, the header line, and disabled services (marked with *)
    [[ -z "$service" ]] && continue
    [[ "$service" == "An asterisk"* ]] && continue
    [[ "$service" == \** ]] && continue
    router=$(networksetup -getinfo "$service" 2>/dev/null | grep "^Router:" | awk '{print $2}')
    if [[ -n "$router" && "$router" != "none" ]]; then
        PRIMARY_SERVICE="$service"
        break
    fi
done < <(networksetup -listallnetworkservices 2>/dev/null)

if [[ -z "$PRIMARY_SERVICE" ]]; then
    echo "Warning: could not auto-detect active network service."
    echo "Available services:"
    networksetup -listallnetworkservices
    echo ""
    # Non-interactive fallback: try common names
    for svc in "Wi-Fi" "Ethernet" "iPhone USB"; do
        if networksetup -getinfo "$svc" 2>/dev/null | grep -q "IP address:"; then
            PRIMARY_SERVICE="$svc"
            echo "Auto-selected: ${PRIMARY_SERVICE}"
            break
        fi
    done
fi

if [[ -z "$PRIMARY_SERVICE" ]]; then
    echo "Error: could not detect network service. Please edit setup.sh and set PRIMARY_SERVICE manually."
    exit 1
fi

echo "Using network service: ${PRIMARY_SERVICE}"

# Save original DNS
ORIGINAL_DNS=$(networksetup -getdnsservers "$PRIMARY_SERVICE" 2>/dev/null || echo "")
if echo "$ORIGINAL_DNS" | grep -q "There aren't any DNS Servers"; then
    ORIGINAL_DNS="Empty"
fi
mkdir -p "$(dirname "$SAVED_DNS_FILE")"
echo "SERVICE=${PRIMARY_SERVICE}" > "${SAVED_DNS_FILE}"
echo "DNS=${ORIGINAL_DNS}"       >> "${SAVED_DNS_FILE}"
echo "Saved original DNS to ${SAVED_DNS_FILE}: ${ORIGINAL_DNS}"

# --------------------------------------------------------------------------
# Step 4: Create launchd plist
# --------------------------------------------------------------------------
echo ""
echo "[4/5] Creating launchd daemon at ${PLIST_FILE}..."

cat > "${PLIST_FILE}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>

    <key>ProgramArguments</key>
    <array>
        <string>${BINARY_DST}</string>
        <string>--dns-addr</string>
        <string>${DNS_ADDR}</string>
        <string>--dns-port</string>
        <string>${DNS_PORT}</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/var/log/macbyedpi_dnsredir.log</string>

    <key>StandardErrorPath</key>
    <string>/var/log/macbyedpi_dnsredir_err.log</string>
</dict>
</plist>
EOF

chown root:wheel "${PLIST_FILE}"
chmod 644 "${PLIST_FILE}"

# Unload if already running
launchctl unload "${PLIST_FILE}" 2>/dev/null || true

# Load and start
launchctl load "${PLIST_FILE}"
echo "Daemon loaded and started."

# --------------------------------------------------------------------------
# Step 5: Set macOS DNS to 127.0.0.1
# --------------------------------------------------------------------------
echo ""
echo "[5/5] Setting DNS for '${PRIMARY_SERVICE}' to 127.0.0.1..."
networksetup -setdnsservers "${PRIMARY_SERVICE}" 127.0.0.1

# Flush DNS cache
dscacheutil -flushcache
killall -HUP mDNSResponder 2>/dev/null || true
echo "DNS cache flushed."

# --------------------------------------------------------------------------
# Done
# --------------------------------------------------------------------------
echo ""
echo "=== Setup complete! ==="
echo ""
echo "All DNS queries on your Mac now go:"
echo "  App → 127.0.0.1:53 (MacbyeDPI) → ${DNS_ADDR}:${DNS_PORT} (upstream)"
echo ""
echo "Test with:  dig discord.com"
echo "Logs at:    /var/log/macbyedpi_dnsredir.log"
echo ""
echo "To uninstall:  sudo ./uninstall.sh"

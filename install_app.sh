#!/bin/bash
# MacbyeDPI Menu Bar App — install script (requires sudo)
# 1. Passwordless sudoers entries for specific commands
# 2. Updates launchd plist (RunAtLoad=false — daemon doesn't auto-start at boot)
# 3. Copies .app to /Applications
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="${DIR}/MacbyeDPI.app"

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo ./install_app.sh"
    exit 1
fi

if [[ ! -d "${APP}" ]]; then
    echo "Error: MacbyeDPI.app not found. Run ./build_app.sh first."
    exit 1
fi

# Detect the console user (the logged-in user, not root)
USERNAME=$(stat -f%Su /dev/console)
echo "=== MacbyeDPI App Installer (user: ${USERNAME}) ==="
echo ""

# ---- 1. Sudoers — passwordless for specific commands only ----
echo "[1/3] Installing sudoers entries..."
SUDOERS_FILE="/etc/sudoers.d/macbyedpi"
cat > "${SUDOERS_FILE}" <<EOF
# MacbyeDPI - allow passwordless execution of specific DNS switching commands
${USERNAME} ALL=(ALL) NOPASSWD: /bin/launchctl start com.macbyedpi.dnsredir
${USERNAME} ALL=(ALL) NOPASSWD: /bin/launchctl stop com.macbyedpi.dnsredir
${USERNAME} ALL=(ALL) NOPASSWD: /usr/sbin/networksetup -setdnsservers Wi-Fi 127.0.0.1
${USERNAME} ALL=(ALL) NOPASSWD: /usr/sbin/networksetup -setdnsservers Wi-Fi Empty
${USERNAME} ALL=(ALL) NOPASSWD: /usr/sbin/dscacheutil -flushcache
${USERNAME} ALL=(ALL) NOPASSWD: /usr/bin/killall -HUP mDNSResponder
EOF
chmod 440 "${SUDOERS_FILE}"
echo "  → Installed: ${SUDOERS_FILE}"

# ---- 2. Update launchd plist: RunAtLoad=false (manual start only) ----
echo ""
echo "[2/3] Updating launchd plist (disable auto-start at boot)..."
PLIST_FILE="/Library/LaunchDaemons/com.macbyedpi.dnsredir.plist"

# Unload current daemon (if running)
launchctl unload "${PLIST_FILE}" 2>/dev/null || true

# Write updated plist
cat > "${PLIST_FILE}" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.macbyedpi.dnsredir</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/macbyedpi_dnsredir</string>
        <string>--dns-addr</string>
        <string>77.88.8.8</string>
        <string>--dns-port</string>
        <string>1253</string>
    </array>

    <key>RunAtLoad</key>
    <false/>

    <key>KeepAlive</key>
    <false/>

    <key>StandardOutPath</key>
    <string>/var/log/macbyedpi_dnsredir.log</string>

    <key>StandardErrorPath</key>
    <string>/var/log/macbyedpi_dnsredir_err.log</string>
</dict>
</plist>
PLIST

chown root:wheel "${PLIST_FILE}"
chmod 644 "${PLIST_FILE}"

# Re-load (registered but not started)
launchctl load "${PLIST_FILE}"
echo "  → Daemon registered (won't auto-start at boot)"

# ---- 3. Copy app to /Applications ----
echo ""
echo "[3/3] Installing MacbyeDPI.app to /Applications..."
rm -rf "/Applications/MacbyeDPI.app"
cp -r "${APP}" "/Applications/MacbyeDPI.app"
# Remove quarantine flag so macOS doesn't block it
xattr -dr com.apple.quarantine "/Applications/MacbyeDPI.app" 2>/dev/null || true
echo "  → Installed: /Applications/MacbyeDPI.app"

# Make sure DNS is currently off (clean state)
networksetup -setdnsservers "Wi-Fi" Empty 2>/dev/null || true
dscacheutil -flushcache 2>/dev/null || true
killall -HUP mDNSResponder 2>/dev/null || true

echo ""
echo "=== Installation complete! ==="
echo ""
echo "Launch the app:"
echo "  open /Applications/MacbyeDPI.app"
echo ""
echo "Or search for 'MacbyeDPI' in Launchpad."
echo ""
echo "The Discord icon will appear in your menu bar."
echo "Click it → 'Turn On for Discord' / 'Turn Off'"

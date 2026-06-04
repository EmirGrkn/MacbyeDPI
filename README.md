# MacbyeDPI

**macOS port of GoodbyeDPI's DNS redirection feature — bypasses ISP DNS poisoning via a native menu bar app.**

MacbyeDPI runs a lightweight DNS redirector daemon that intercepts all DNS queries on your Mac and forwards them to a trusted upstream server on a non-standard port, preventing your ISP from intercepting or poisoning them. A native Swift menu bar app lets you toggle it on/off with a single click.

> **Scope:** This is a port of GoodbyeDPI's `--dns-addr` / `--dns-port` feature only. Active DPI circumvention (packet fragmentation, TTL manipulation, fake packets) is not implemented — see [Similar projects](#similar-projects) if you need full DPI bypass on macOS.

---

## Requirements

- macOS 10.13 (High Sierra) or later
- Apple Silicon or Intel Mac
- Xcode Command Line Tools (`xcode-select --install`)

---

## Quick start

```bash
# 1. Build
make
bash build_app.sh

# 2. Install (requires sudo)
sudo bash install_app.sh

# 3. Launch
open /Applications/MacbyeDPI.app
```

The Discord icon appears in your menu bar. Click **Turn On for Discord** to activate.

Default upstream: **Yandex DNS `77.88.8.8:1253`** — same non-standard port as GoodbyeDPI's recommended `2_any_country_dnsredir.cmd` script.

---

## How it works

MacbyeDPI consists of two components:

### 1. DNS Redirector (`macbyedpi_dnsredir`)

A C daemon that listens on `127.0.0.1:53` and transparently forwards all UDP DNS queries to a configurable upstream DNS server — on any port. Because queries leave your machine on a non-standard port (e.g. 1253 instead of 53), ISP middleboxes that intercept or poison standard DNS traffic never see them.

**Query flow:**
```
App → 127.0.0.1:53 (MacbyeDPI) → 77.88.8.8:1253 (Yandex DNS)
```

The daemon remaps query IDs to track concurrent requests and routes responses back to the correct caller.

### 2. Menu Bar App (`MacbyeDPI.app`)

A native Swift/Cocoa app that lives in the menu bar. On toggle:

- **Turn On** — starts the launchd daemon via `launchctl`, sets Wi-Fi DNS to `127.0.0.1`
- **Turn Off** — stops the daemon, restores Wi-Fi DNS to system default
- Flushes the DNS cache (`dscacheutil`, `mDNSResponder`) on every toggle

The app uses passwordless `sudo` for a specific, minimal set of commands (configured in `/etc/sudoers.d/macbyedpi` during installation) — no full root access is granted.

---

## Build from source

```bash
# Build the DNS redirector daemon (C)
make

# Build the menu bar app (Swift) and assemble the .app bundle
bash build_app.sh
```

### Install

```bash
sudo bash install_app.sh
```

This script:
1. Creates `/etc/sudoers.d/macbyedpi` with NOPASSWD entries for the specific commands the app needs
2. Registers the launchd daemon at `/Library/LaunchDaemons/com.macbyedpi.dnsredir.plist` (manual start only — does not run at boot)
3. Copies `MacbyeDPI.app` to `/Applications`

### Uninstall

```bash
sudo bash uninstall.sh
```

---

## Advanced: manual daemon setup

For headless use or a different upstream DNS, use `setup.sh` directly:

```bash
sudo ./setup.sh --dns-addr 77.88.8.8 --dns-port 1253   # Yandex DNS (recommended)
sudo ./setup.sh --dns-addr 8.8.8.8   --dns-port 53     # Google DNS
sudo ./setup.sh --dns-addr 1.1.1.1   --dns-port 53     # Cloudflare
```

`setup.sh` builds the daemon, installs it to `/usr/local/bin`, registers a launchd daemon with `RunAtLoad=true` (auto-starts at boot), and sets your Mac's DNS immediately.

### DNS redirector options

```
Usage: sudo ./macbyedpi_dnsredir --dns-addr <IP> [options]

  --dns-addr   <IP>    Upstream DNS server IP (required)
  --dns-port   <port>  Upstream DNS server port [default: 53]
  --listen-addr <IP>   Local address to listen on [default: 127.0.0.1]
  --listen-port <port> Local port to listen on [default: 53]
  --verbose            Print each redirected query
  --help               Show this help
```

---

## How to check if it's working

```bash
# Should return an answer from Yandex DNS, not your ISP
dig discord.com

# Check daemon logs
tail -f /var/log/macbyedpi_dnsredir.log
```

If sites that were blocked are now accessible after enabling MacbyeDPI, your ISP was using DNS poisoning. If they remain blocked, your ISP may be using Active DPI (packet inspection) — see [Similar projects](#similar-projects) for tools that handle this.

---

## Similar projects

- **[GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI)** by @ValdikSS — the original, Windows only, full DPI bypass
- **[zapret](https://github.com/bol-van/zapret)** by @bol-van — full DPI bypass for macOS, Linux and Windows
- **[SpoofDPI](https://github.com/xvzc/SpoofDPI)** by @xvzc — DPI bypass for macOS and Linux
- **[ByeDPI](https://github.com/hufrea/byedpi)** by @hufrea — Linux/Windows

---

## Credits

Inspired by [GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) by @ValdikSS.

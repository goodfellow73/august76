#!/usr/bin/env bash
# ============================================================
#  Pi-hole YouTube Ad Blocker — Setup Script
#  Tested on: Ubuntu 22.04/24.04, Debian 11/12, Raspberry Pi OS
#
#  What it does:
#    1. Installs Pi-hole (if not already installed)
#    2. Loads a curated YouTube ad domain blocklist
#    3. Adds three well-maintained community blocklists
#    4. Rebuilds Pi-hole gravity (applies all lists)
#    5. Prints per-network and Private DNS instructions for
#       Poco / MIUI Android phones
#
#  Run as root:
#    sudo bash setup.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BLOCKLIST="$SCRIPT_DIR/youtube-blocklist.txt"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fatal()   { echo -e "${RED}[FATAL]${NC} $*"; exit 1; }

# ── 0. Preflight ─────────────────────────────────────────────────────────────

[[ $EUID -ne 0 ]] && fatal "Run as root:  sudo bash $0"
command -v curl &>/dev/null || apt-get install -y -qq curl
command -v sqlite3 &>/dev/null || apt-get install -y -qq sqlite3

echo ""
echo "============================================================"
echo "   Pi-hole YouTube Ad Blocker Setup"
echo "============================================================"
echo ""

# ── 1. Install Pi-hole ────────────────────────────────────────────────────────

if command -v pihole &>/dev/null; then
  success "Pi-hole already installed ($(pihole version --pihole | head -1))"
else
  info "Installing Pi-hole (unattended — default settings)..."
  curl -sSL https://install.pi-hole.net | PIHOLE_SKIP_OS_CHECK=true bash /dev/stdin --unattended
  success "Pi-hole installed"
fi

GRAVITY_DB="/etc/pihole/gravity.db"
[[ -f "$GRAVITY_DB" ]] || fatal "gravity.db not found at $GRAVITY_DB — Pi-hole installation may have failed"

# ── 2. Copy local YouTube blocklist ──────────────────────────────────────────

DEST_LIST="/etc/pihole/youtube-ads-blocklist.txt"
info "Copying YouTube blocklist to $DEST_LIST ..."
cp "$LOCAL_BLOCKLIST" "$DEST_LIST"
chmod 644 "$DEST_LIST"
success "Local blocklist installed ($(grep -c '^[^#]' "$DEST_LIST") domains)"

# Register in Pi-hole's database (Pi-hole v5+)
sqlite3 "$GRAVITY_DB" <<'SQL'
INSERT OR IGNORE INTO adlist (address, enabled, comment)
VALUES ('file:///etc/pihole/youtube-ads-blocklist.txt', 1, 'YouTube Ad Blocker — local curated list');
SQL

# ── 3. Add community-maintained blocklists ────────────────────────────────────

info "Adding community blocklists..."

declare -A LISTS=(
  ["Hagezi Pro (comprehensive, low false-positives)"]="https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt"
  ["Steven Black hosts (well-maintained classic)"]="https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
  ["AdGuard DNS filter (Google/YouTube ad rules)"]="https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt"
)

for name in "${!LISTS[@]}"; do
  url="${LISTS[$name]}"
  sqlite3 "$GRAVITY_DB" \
    "INSERT OR IGNORE INTO adlist (address, enabled, comment) VALUES ('$url', 1, '$name');" \
    && info "  Added: $name" \
    || warn "  Already present or failed: $name"
done

# ── 4. Rebuild gravity ────────────────────────────────────────────────────────

info "Rebuilding Pi-hole gravity (downloads all lists — may take a minute)..."
pihole -g
success "Gravity updated"

# ── 5. Restart DNS ───────────────────────────────────────────────────────────

pihole restartdns &>/dev/null || true
success "Pi-hole DNS restarted"

# ── 6. Print phone setup instructions ────────────────────────────────────────

PIHOLE_IP=$(hostname -I | awk '{print $1}')
ADMIN_URL="http://$PIHOLE_IP/admin"

echo ""
echo "============================================================"
echo -e "  ${GREEN}Setup complete!${NC}"
echo "============================================================"
echo ""
echo -e "  Pi-hole IP:     ${CYAN}$PIHOLE_IP${NC}"
echo -e "  Admin panel:    ${CYAN}$ADMIN_URL${NC}"
echo ""
echo "────────────────────────────────────────────────────────────"
echo "  How to set up your Poco phone (MIUI / Android 12+):"
echo "────────────────────────────────────────────────────────────"
echo ""
echo "  OPTION A — Per Wi-Fi network (easiest, only works on Wi-Fi):"
echo "  ┌─────────────────────────────────────────────────────────┐"
echo "  │ 1. Settings → Wi-Fi                                     │"
echo "  │ 2. Long-press your home network → Modify network        │"
echo "  │ 3. Advanced options → IP settings → Static              │"
echo "  │ 4. DNS 1: $PIHOLE_IP"
echo "  │    DNS 2: 1.1.1.1  (fallback)                           │"
echo "  │ 5. Save                                                  │"
echo "  └─────────────────────────────────────────────────────────┘"
echo ""
echo "  OPTION B — Router-level (every device, Wi-Fi + phone):"
echo "  ┌─────────────────────────────────────────────────────────┐"
echo "  │ Log into your router admin (usually 192.168.1.1)        │"
echo "  │ Find DHCP / DNS settings                                │"
echo "  │ Set Primary DNS: $PIHOLE_IP"
echo "  │ Leave Secondary DNS blank (Pi-hole handles fallback)    │"
echo "  │ Save & reboot router                                    │"
echo "  └─────────────────────────────────────────────────────────┘"
echo ""
echo "  OPTION C — Android Private DNS (works on mobile data too):"
echo "  ┌─────────────────────────────────────────────────────────┐"
echo "  │ Requires Pi-hole to be reachable from mobile network.   │"
echo "  │ 1. Run:  sudo bash setup-dot.sh  (see setup-dot.sh)     │"
echo "  │ 2. Settings → More connection settings → Private DNS    │"
echo "  │ 3. Choose 'Private DNS provider hostname'               │"
echo "  │ 4. Enter your Pi-hole's public hostname or IP           │"
echo "  └─────────────────────────────────────────────────────────┘"
echo ""
echo "────────────────────────────────────────────────────────────"
echo "  What gets blocked:"
echo "    ✓ YouTube overlay / banner ads"
echo "    ✓ YouTube ad SDK (reduces pre-roll ads)"
echo "    ✓ Google ad tracking and attribution"
echo "    ✓ DoubleClick ad network"
echo ""
echo "  What may still appear:"
echo "    ~ Some pre-roll video ads (served from googlevideo.com"
echo "      which can't be blocked without breaking video playback)"
echo "    ~ For 100% video ad blocking on Android without a"
echo "      new app: patch your YouTube APK with ReVanced"
echo "      https://revanced.app"
echo "────────────────────────────────────────────────────────────"
echo ""

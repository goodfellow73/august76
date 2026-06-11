#!/usr/bin/env bash
# ============================================================
#  Pi-hole DNS-over-TLS (DoT) Setup
#  Enables Android "Private DNS" to point to your Pi-hole,
#  so ad blocking works on mobile data — not just Wi-Fi.
#
#  Requires: Pi-hole already installed (run setup.sh first)
#  Run as root:  sudo bash setup-dot.sh
# ============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fatal()   { echo -e "${RED}[FATAL]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && fatal "Run as root: sudo bash $0"

# ── Install Unbound (acts as a DNS resolver with TLS) ────────────────────────
info "Installing unbound..."
apt-get install -y -qq unbound

# ── Install stunnel (wraps Pi-hole DNS in TLS) ───────────────────────────────
info "Installing stunnel4..."
apt-get install -y -qq stunnel4

# ── Generate self-signed cert for DoT ────────────────────────────────────────
CERT_DIR="/etc/stunnel"
mkdir -p "$CERT_DIR"

if [[ ! -f "$CERT_DIR/pihole-dot.pem" ]]; then
  info "Generating self-signed TLS certificate..."
  openssl req -new -x509 -days 3650 -nodes \
    -out "$CERT_DIR/pihole-dot.pem" \
    -keyout "$CERT_DIR/pihole-dot.pem" \
    -subj "/CN=pihole-dot" 2>/dev/null
  chmod 600 "$CERT_DIR/pihole-dot.pem"
  success "Certificate generated: $CERT_DIR/pihole-dot.pem"
else
  success "Certificate already exists"
fi

# ── Configure stunnel to wrap port 853 (DoT) → port 53 ──────────────────────
cat > /etc/stunnel/pihole-dot.conf <<'CONF'
; stunnel config — wraps Pi-hole's DNS port 53 in TLS on port 853
; Port 853 is the standard DNS-over-TLS (DoT) port (RFC 7858)

foreground = no
pid = /var/run/stunnel4/stunnel4.pid

[dns-tls]
accept  = 853
connect = 127.0.0.1:53
cert    = /etc/stunnel/pihole-dot.pem
CONF

# Enable stunnel autostart
sed -i 's/^ENABLED=0/ENABLED=1/' /etc/default/stunnel4 2>/dev/null || true

# ── Open port 853 in firewall (if ufw is active) ─────────────────────────────
if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
  info "Opening port 853/tcp in ufw..."
  ufw allow 853/tcp comment "DNS-over-TLS for Android Private DNS" &>/dev/null
  success "Port 853 opened in ufw"
fi

# ── Start stunnel ─────────────────────────────────────────────────────────────
systemctl enable stunnel4 &>/dev/null || true
systemctl restart stunnel4
success "stunnel4 started (DoT on port 853)"

# ── Done ─────────────────────────────────────────────────────────────────────

PIHOLE_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "============================================================"
echo -e "  ${GREEN}DNS-over-TLS (DoT) enabled!${NC}"
echo "============================================================"
echo ""
echo "  Your Pi-hole now accepts encrypted DNS on port 853."
echo ""
echo "────────────────────────────────────────────────────────────"
echo "  Poco phone Private DNS setup (works on Wi-Fi AND data):"
echo "────────────────────────────────────────────────────────────"
echo ""
echo "  1. Settings → More connection settings → Private DNS"
echo "  2. Choose: Private DNS provider hostname"
echo -e "  3. Enter: ${CYAN}$PIHOLE_IP${NC}"
echo "     (If your Pi-hole has a domain name, use that instead)"
echo "  4. Tap Save"
echo ""
echo "  NOTE: Using a raw IP as hostname for Private DNS works on"
echo "  most Android versions but some may require a real hostname."
echo "  If it fails, use the per-Wi-Fi DNS method from setup.sh."
echo ""
echo "  To verify it's working:"
echo "    Open YouTube on your Poco → watch a video"
echo "    Check Pi-hole admin panel for blocked queries:"
echo -e "    ${CYAN}http://$PIHOLE_IP/admin${NC}"
echo ""

#!/usr/bin/env bash
# Idempotent frps installer for the personal-gateway VPS relay.
#
# The VPS is a pure frp relay: no Docker, no nginx, no auth logic here.
# Usage (as root, on the VPS):
#   1. copy this directory to the VPS  (scp -r vps-gateway root@<vps>:/root/)
#   2. cp gateway.env.example gateway.env  &&  edit gateway.env
#   3. ./install.sh
# Re-running is safe: it upgrades/reconfigures and restarts frps.
#
# China-network note: if GitHub releases are unreachable from the VPS,
# pre-download frp_<version>_linux_<arch>.tar.gz on another machine, place it
# next to this script (or set FRP_TARBALL=/path/to.tgz in gateway.env),
# and re-run — no download will be attempted.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${HERE}/gateway.env"
PREFIX="/opt/frp"
UNIT="/etc/systemd/system/frps.service"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "==> $*"; }

[[ $EUID -eq 0 ]] || die "run as root"
[[ -f "$ENV_FILE" ]] || die "missing $ENV_FILE (cp gateway.env.example gateway.env and edit it)"

# shellcheck disable=SC1090
source "$ENV_FILE"
: "${FRP_TOKEN:?set in gateway.env}"
: "${FRP_BIND_PORT:=7000}"
: "${PUBLIC_PORT:=300}"
: "${DASHBOARD_USER:=admin}"
: "${DASHBOARD_PASSWORD:?set in gateway.env}"
: "${FRP_VERSION:=0.61.2}"

case "$(uname -m)" in
  x86_64)  ARCH=amd64 ;;
  aarch64) ARCH=arm64 ;;
  *) die "unsupported arch $(uname -m)" ;;
esac

# --- 1. frps binary -----------------------------------------------------------
mkdir -p "$PREFIX"
TARBALL_NAME="frp_${FRP_VERSION}_linux_${ARCH}.tar.gz"
need_download=1
if [[ -x "$PREFIX/frps" ]] && "$PREFIX/frps" --version 2>/dev/null | grep -qx "$FRP_VERSION"; then
  log "frps $FRP_VERSION already installed"
  need_download=0
fi

if [[ $need_download -eq 1 ]]; then
  SRC="${FRP_TARBALL:-${HERE}/${TARBALL_NAME}}"
  if [[ -f "$SRC" ]]; then
    log "using local tarball $SRC"
    tar xzf "$SRC" -C /tmp
  else
    URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${TARBALL_NAME}"
    log "downloading $URL"
    curl -fsSL --connect-timeout 15 -o "/tmp/$TARBALL_NAME" "$URL" \
      || die "download failed — pre-download $TARBALL_NAME elsewhere, place it next to install.sh (or set FRP_TARBALL), and re-run"
    tar xzf "/tmp/$TARBALL_NAME" -C /tmp
  fi
  install -m 0755 "/tmp/frp_${FRP_VERSION}_linux_${ARCH}/frps" "$PREFIX/frps"
  rm -rf "/tmp/frp_${FRP_VERSION}_linux_${ARCH}" "/tmp/$TARBALL_NAME"
fi

# --- 2. config ----------------------------------------------------------------
esc() { printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g'; }
render() {
  local out="$1"; shift
  cp "${HERE}/frps.toml.template" "$out"
  local key
  for key in FRP_TOKEN FRP_BIND_PORT PUBLIC_PORT DASHBOARD_USER DASHBOARD_PASSWORD; do
    sed -i "s|\${${key}}|$(esc "${!key}")|g" "$out"
  done
}
render "$PREFIX/frps.toml"
chmod 600 "$PREFIX/frps.toml"
log "wrote $PREFIX/frps.toml"

# --- 3. systemd ---------------------------------------------------------------
cat > "$UNIT" <<EOF
[Unit]
Description=frp server (personal gateway relay)
After=network.target

[Service]
Type=simple
ExecStart=$PREFIX/frps -c $PREFIX/frps.toml
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable frps >/dev/null
if systemctl is-active --quiet frps; then
  systemctl restart frps
else
  systemctl start frps
fi
sleep 1
systemctl is-active --quiet frps || { journalctl -u frps --no-pager -n 20; die "frps failed to start"; }

log "frps $($PREFIX/frps --version) running"
cat <<EOF

Done. Now open these ports in the cloud provider SECURITY GROUP (not just the
OS firewall):
  ${FRP_BIND_PORT}/tcp   frp control (frpc clients connect here)
  ${PUBLIC_PORT}/tcp     personal gateway public entry
  7001/tcp               mouding MCP (if used on this VPS)
Do NOT open 7500 publicly — the dashboard listens on 127.0.0.1 only:
  ssh -L 7500:127.0.0.1:7500 root@<this-vps>
EOF

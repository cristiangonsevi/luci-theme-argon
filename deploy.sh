#!/bin/sh
# deploy.sh — Deploy luci-theme-argon changes to your OpenWrt router via SCP
#
# Usage:
#   ./deploy.sh <router-ip>
#
# Example:
#   ./deploy.sh 192.168.1.1
#
# First time? Set up SSH keys so it doesn't ask for password every time:
#   ssh-copy-id root@192.168.1.1
#
# Or set a SSH config alias in ~/.ssh/config:
#   Host router
#     HostName 192.168.1.1
#     User root

set -e

ROUTER="$1"

if [ -z "$ROUTER" ]; then
    echo "Usage: $0 <router-ip>"
    echo "Example: $0 192.168.1.1"
    exit 1
fi

# SSH multiplexing — single connection, no repeated password prompts
SSH_SOCKET="/tmp/luci-argon-$ROUTER.sock"
SSH_CTL="-o ControlPath=$SSH_SOCKET -o ControlMaster=auto -o ControlPersist=300"
SCP_CTL="-o ControlPath=$SSH_SOCKET -o ControlMaster=auto"

cleanup() {
    ssh $SSH_CTL -O exit root@"$ROUTER" 2>/dev/null || true
}
trap cleanup EXIT

echo "🚀 Deploying luci-theme-argon to root@$ROUTER ..."
echo "   (first connection may ask for password — subsequent ones won't)"

# ── Static assets (CSS, fonts, images, JS) ──────────────────────────
echo "  → Copying static assets..."
scp $SCP_CTL -rq htdocs/luci-static/argon root@"$ROUTER":/www/luci-static/
scp $SCP_CTL htdocs/luci-static/resources/menu-argon.js \
    root@"$ROUTER":/www/luci-static/resources/menu-argon.js

# ── ucode templates ─────────────────────────────────────────────────
echo "  → Copying ucode templates..."
ssh $SSH_CTL root@"$ROUTER" "mkdir -p /usr/share/ucode/luci/template/themes/argon"
scp $SCP_CTL -rq ucode/template/themes/argon/*.ut \
    root@"$ROUTER":/usr/share/ucode/luci/template/themes/argon/

# ── RPCD wallpaper plugin ───────────────────────────────────────────
echo "  → Copying RPCD wallpaper plugin..."
scp $SCP_CTL root/usr/libexec/rpcd/luci.argon_wallpaper \
    root@"$ROUTER":/usr/libexec/rpcd/luci.argon_wallpaper
ssh $SSH_CTL root@"$ROUTER" "chmod +x /usr/libexec/rpcd/luci.argon_wallpaper"

# ── ACL permissions ─────────────────────────────────────────────────
echo "  → Copying ACL rules..."
scp $SCP_CTL root/usr/share/rpcd/acl.d/luci-theme-argon.json \
    root@"$ROUTER":/usr/share/rpcd/acl.d/luci-theme-argon.json

# ── Reload everything ───────────────────────────────────────────────
echo "  → Restarting services..."
ssh $SSH_CTL root@"$ROUTER" "/etc/init.d/rpcd restart"
ssh $SSH_CTL root@"$ROUTER" "/etc/init.d/uhttpd restart"

echo ""
echo "✅ Done! Theme has been deployed to $ROUTER"
echo "   Refresh your browser (hard reload: Ctrl+Shift+R)"

#!/bin/sh
# deploy.sh — Deploy luci-theme-argon changes to your OpenWrt router
#
# Usage:
#   ./deploy.sh <router-ip>
#
# Example:
#   ./deploy.sh 192.168.1.1
#
# First time? Set up SSH keys so it doesn't ask for password every time:
#   ssh-copy-id root@192.168.1.1

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

cleanup() {
    ssh $SSH_CTL -O exit root@"$ROUTER" 2>/dev/null || true
}
trap cleanup EXIT

# Uses ssh+cat instead of scp (OpenWrt Dropbear lacks sftp-server)
put() {
    local src="$1" dst="$2"
    ssh $SSH_CTL root@"$ROUTER" "cat > '$dst'" < "$src"
}

put_recursive() {
    local src_dir="$1" dst_dir="$2"
    tar c -C "$(dirname "$src_dir")" "$(basename "$src_dir")" 2>/dev/null |
    ssh $SSH_CTL root@"$ROUTER" "mkdir -p '$dst_dir' && tar xf - -C '$dst_dir'"
}

echo "🚀 Deploying luci-theme-argon to root@$ROUTER ..."
echo "   (first connection may ask for password — subsequent ones won't)"

# ── Static assets (CSS, fonts, images, JS) ──────────────────────────
echo "  → Copying static assets..."
put_recursive htdocs/luci-static/argon /www/luci-static/argon
put htdocs/luci-static/resources/menu-argon.js /www/luci-static/resources/menu-argon.js

# ── ucode templates ─────────────────────────────────────────────────
echo "  → Copying ucode templates..."
ssh $SSH_CTL root@"$ROUTER" "mkdir -p /usr/share/ucode/luci/template/themes/argon"
put_recursive ucode/template/themes/argon /usr/share/ucode/luci/template/themes/argon

# ── RPCD wallpaper plugin ───────────────────────────────────────────
echo "  → Copying RPCD wallpaper plugin..."
put root/usr/libexec/rpcd/luci.argon_wallpaper /usr/libexec/rpcd/luci.argon_wallpaper
ssh $SSH_CTL root@"$ROUTER" "chmod +x /usr/libexec/rpcd/luci.argon_wallpaper"

# ── ACL permissions ─────────────────────────────────────────────────
echo "  → Copying ACL rules..."
put root/usr/share/rpcd/acl.d/luci-theme-argon.json /usr/share/rpcd/acl.d/luci-theme-argon.json

# ── Reload everything ───────────────────────────────────────────────
echo "  → Restarting services..."
ssh $SSH_CTL root@"$ROUTER" "/etc/init.d/rpcd restart"
ssh $SSH_CTL root@"$ROUTER" "/etc/init.d/uhttpd restart"

echo ""
echo "✅ Done! Theme has been deployed to $ROUTER"
echo "   Refresh your browser (hard reload: Ctrl+Shift+R)"

#!/bin/sh
# watch.sh — Watch source files and auto-deploy to OpenWrt router on change
#
# Usage:
#   ./watch.sh <router-ip>
#
# Example:
#   ./watch.sh 192.168.1.1
#
# Does everything automatically:
#   - Rebuilds LESS → CSS (if lessc available)
#   - Rebuilds Tailwind CSS (if node_modules exists)
#   - Deploys changed files to router via SSH
#   - Restarts services when needed
#
# First time? Set up SSH keys so it doesn't ask for password every time:
#   ssh-copy-id root@192.168.1.1
#
# Requires: ssh
# For real-time file watching: inotifywait (apt install inotify-tools)
# Falls back to polling every 2s if inotifywait is not available.

ROUTER="$1"
WATCH_DIRS="less htdocs ucode root"

if [ -z "$ROUTER" ]; then
    echo "Usage: $0 <router-ip>"
    echo "Example: $0 192.168.1.1"
    exit 1
fi

# SSH multiplexing — single connection reused for all subsequent calls
SSH_SOCKET="/tmp/luci-argon-watch-$ROUTER.sock"
SSH_CTL="-o ControlPath=$SSH_SOCKET -o ControlMaster=auto -o ControlPersist=600"

cleanup() {
    ssh $SSH_CTL -O exit root@"$ROUTER" 2>/dev/null || true
    rm -f /tmp/luci-argon-watch
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

# ── Build CSS (LESS + Tailwind) ─────────────────────────────────────

build_css() {
    # Recompile LESS if the compiler is available
    if command -v lessc >/dev/null 2>&1; then
        echo "  ◌ Compiling LESS → CSS..."
        lessc less/cascade.less htdocs/luci-static/argon/css/cascade.css 2>/dev/null
        lessc --clean-css less/dark.less htdocs/luci-static/argon/css/dark.css 2>/dev/null
    fi

    # Rebuild Tailwind if node_modules exists
    if [ -f package.json ] && [ -d node_modules ]; then
        echo "  ◌ Building Tailwind CSS..."
        npm run build 2>/dev/null
    fi
}

# ── Deploy helpers ──────────────────────────────────────────────────

deploy_all() {
    echo "── Deploying all files to $ROUTER ──"
    echo "   (first connection may ask for password, then it's seamless)"

    build_css

    echo "  ◌ Copying static assets..."
    put_recursive htdocs/luci-static/argon /www/luci-static
    put htdocs/luci-static/resources/menu-argon.js /www/luci-static/resources/menu-argon.js

    echo "  ◌ Copying ucode templates..."
    ssh $SSH_CTL root@"$ROUTER" "mkdir -p /usr/share/ucode/luci/template/themes" 2>/dev/null
    put_recursive ucode/template/themes/argon /usr/share/ucode/luci/template/themes

    echo "  ◌ Copying RPCD plugin..."
    put root/usr/libexec/rpcd/luci.argon_wallpaper /usr/libexec/rpcd/luci.argon_wallpaper
    ssh $SSH_CTL root@"$ROUTER" "chmod +x /usr/libexec/rpcd/luci.argon_wallpaper" 2>/dev/null

    echo "  ◌ Copying ACL rules..."
    put root/usr/share/rpcd/acl.d/luci-theme-argon.json /usr/share/rpcd/acl.d/luci-theme-argon.json

    echo "  ◌ Activating theme in LuCI..."
    ssh $SSH_CTL root@"$ROUTER" "uci set luci.themes.Argon=/luci-static/argon 2>/dev/null; uci set luci.main.mediaurlbase=/luci-static/argon 2>/dev/null; uci commit luci 2>/dev/null"

    echo "  ◌ Restarting services..."
    ssh $SSH_CTL root@"$ROUTER" "/etc/init.d/rpcd restart; /etc/init.d/uhttpd restart" 2>/dev/null

    echo "✅ Deploy complete — hard refresh browser (Ctrl+Shift+R)"
}

deploy_incremental() {
    local file="$1"

    # Always rebuild CSS first (fast: ~250ms tailwind, ~1s lessc)
    build_css

    echo "── Change detected: $file ──"

    case "$file" in
        less/*)
            # CSS was already rebuilt and compiled by build_css above.
            # Deploy the compiled files.
            put htdocs/luci-static/argon/css/cascade.css /www/luci-static/argon/css/cascade.css
            put htdocs/luci-static/argon/css/dark.css /www/luci-static/argon/css/dark.css 2>/dev/null
            put htdocs/luci-static/argon/css/tailwind.css /www/luci-static/argon/css/tailwind.css 2>/dev/null
            echo "  ◌ CSS updated — just refresh browser"
            ;;

        htdocs/luci-static/argon/*)
            local rel="${file#htdocs/luci-static/}"
            local dest="/www/luci-static/$rel"
            echo "  ◌ Copying $rel ..."
            ssh $SSH_CTL root@"$ROUTER" "mkdir -p $(dirname $dest)" 2>/dev/null
            put "$file" "$dest"
            # If it's a LESS change, the compiled CSS was already deployed by build_css
            ;;

        htdocs/luci-static/resources/*)
            put "$file" "/www/luci-static/resources/menu-argon.js"
            echo "  ◌ JS updated — just refresh browser"
            ;;

        ucode/*)
            local rel="${file#ucode/}"
            echo "  ◌ Copying $rel ..."
            ssh $SSH_CTL root@"$ROUTER" "mkdir -p /usr/share/ucode/luci/template/themes/argon" 2>/dev/null
            put "$file" "/usr/share/ucode/luci/$rel"
            # Tailwind was rebuilt by build_css, deploy it too
            put htdocs/luci-static/argon/css/tailwind.css /www/luci-static/argon/css/tailwind.css 2>/dev/null
            echo "  ◌ Restarting uhttpd..."
            ssh $SSH_CTL root@"$ROUTER" "/etc/init.d/uhttpd restart" 2>/dev/null
            ;;

        root/*)
            local rel="${file#root/}"
            echo "  ◌ Copying $rel ..."
            ssh $SSH_CTL root@"$ROUTER" "mkdir -p /$(dirname $rel)" 2>/dev/null
            put "$file" "/$rel"
            if echo "$rel" | grep -q "rpcd"; then
                ssh $SSH_CTL root@"$ROUTER" "chmod +x /$rel; /etc/init.d/rpcd restart" 2>/dev/null
            fi
            ;;
    esac
}

# ── main ────────────────────────────────────────────────────────────

deploy_all

if command -v inotifywait >/dev/null 2>&1; then
    echo ""
    echo "👀 Watching for changes (inotify) — edit a file and see it deploy instantly..."
    echo "   Press Ctrl+C to stop"
    echo ""

    inotifywait -m -r -e modify,create,delete,move $WATCH_DIRS --format '%w%f' 2>/dev/null |
    while read -r file; do
        deploy_incremental "$file"
    done
else
    echo ""
    echo "⚠️  inotifywait not found. Install it:  sudo apt install inotify-tools"
    echo "   Falling back to polling every 2 seconds."
    echo "   Press Ctrl+C to stop"
    echo ""

    touch /tmp/luci-argon-watch
    while true; do
        changed=$(find $WATCH_DIRS -newer /tmp/luci-argon-watch -type f 2>/dev/null | head -5)
        if [ -n "$changed" ]; then
            touch /tmp/luci-argon-watch
            for file in $changed; do
                deploy_incremental "$file"
            done
        fi
        sleep 2
    done
fi

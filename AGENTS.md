# luci-theme-argon — Agent Guide

An OpenWrt LuCI theme (v2.4.3). Provides a clean, customizable web interface for OpenWrt routers. NOT a Node.js/webapp project — it's an OpenWrt package built with the SDK.

## Quick Start

### Quick deploy + live reload

```bash
# One-time setup: SSH key so you're never asked for a password again
ssh-copy-id root@192.168.1.1

# First time: install Tailwind
npm install

# Build Tailwind CSS (re-run after adding new classes)
npm run build

# Then:
./deploy.sh 192.168.1.1     # one-time deploy
./watch.sh 192.168.1.1      # watch mode — auto-deploys on every file change
```

`deploy.sh` SCPs all files and restarts `rpcd` + `uhttpd`. Requires SSH root access.

`watch.sh` does a full deploy first, then watches for changes and deploys incrementally. LESS files are auto-recompiled if `lessc` is installed.

Both scripts use **SSH multiplexing** (`ControlMaster=auto`) — the first connection may ask for a password, but all subsequent ones reuse the same channel so there's zero prompting.

### Build the CSS

```bash
# Only needed if you edit .less files (requires lessc compiler):
#   npm install -g less less-plugin-clean-css
lessc less/cascade.css htdocs/luci-static/argon/css/cascade.css
lessc --clean-css less/dark.less htdocs/luci-static/argon/css/dark.css
```

### Build the SDK package

```bash
# 1. Clone into openwrt/package/luci-theme-argon
# 2. make menuconfig (choose LUCI → Themes → luci-theme-argon)
# 3. make package/luci-theme-argon/{clean,compile} V=s
```

## Project Structure

```
root/                       → OpenWrt filesystem overlay (installed to /)
  etc/uci-defaults/         → First-boot init script (registers theme in LuCI)
  usr/libexec/rpcd/         → RPCD plugin (online wallpaper fetching)
  usr/share/rpcd/acl.d/     → UCI ACL grants for theme config
ucode/template/themes/argon/ → LuCI ucode templates (.ut files)
htdocs/luci-static/
  argon/                    → Static assets served at /luci-static/argon/
    css/cascade.css         → Compiled main stylesheet
    css/dark.css             → Compiled dark mode stylesheet
    fonts/                   → Google Sans, TypoGraphica, argon icon font (woff2/woff)
    img/                     → SVG icons, background image, blank.png
    icon/                    → PWA/favicon icons
    background/              → User-dropped background images/videos
  resources/menu-argon.js   → Menu JS module (vanilla JS, loaded via L.require)
less/                       → LESS source files
  cascade.less              → Main stylesheet (imports fonts, normalize, pure, sysauth, layout)
  dark.less                  → Dark mode overrides
  layout.less               → Main layout components (sidebar, nav, header)
  sysauth.less              → Login page styles
  responsive.less           → Mobile/desktop responsive breakpoints
  page-fix.less             → Page-specific CSS fixes
  fonts.less                 → @font-face declarations
  normalize.less             → CSS reset (vendored)
  pure-min.less              → Pure CSS v3.0.0 minimal framework (vendored)
Makefile                     → OpenWrt package build definition
```

## Architecture & Control Flow

### Page rendering pipeline

1. **User requests** → `https://router/cgi-bin/luci/...`
2. **LuCI dispatcher** → loads the `ucode/template/themes/argon/header.ut` template
3. **header.ut** reads `/etc/config/argon` via `uci.cursor()` to get:
   - `primary` / `dark_primary` — theme colors (default `#5e72e4` / `#483d8b`)
   - `mode` — `normal` (OS-detect), `dark` (forced dark), or `light` (forced light)
   - `blur` / `transparency` — login page glass effect settings
   - Writes CSS custom properties into `<style>:root {...}</style>` inline
   - Injects `dark.css` inline based on mode
4. **Renders body** → sidebar (`.main-left`), header (`.main-right > header`), content area
5. **footer.ut** loads `menu-argon.js` via `L.require('menu-argon')`
6. **menu-argon.js** → Vanilla JS module using `baseclass.extend()`:
   - `ui.menu.load()` fetches menu tree from LuCI
   - `renderMainMenu()` builds hierarchical sidebar
   - `renderTabMenu()` builds nested tab navigation
   - Custom `SlideAnimations` object replaces jQuery slideUp/slideDown

### Login page

- `out_header_login.ut` includes `header_login.ut`
- `sysauth.ut` is the login page body template
- **Background selection** (in sysauth.ut):
  1. If `/etc/config/argon` has `online_wallpaper`, calls RPCD via `ubus.call("luci.argon_wallpaper", "get_url")`
  2. If no online wallpaper, scans `/www/luci-static/argon/background/` for local media
  3. Supports: `.jpg/jpeg/png/gif/webp` (image) and `.mp4/webm` (video)
- `footer_login.ut` closes the page

### Wallpaper RPCD service (`root/usr/libexec/rpcd/luci.argon_wallpaper`)

Shell script that:
- Fetches from Bing, Unsplash, or Wallhaven based on `online_wallpaper` UCI setting
- Caches URL in `/var/run/argon_<source>.url` (12-hour TTL)
- File-locked with `/var/lock/argon_<source>.lock`
- Called via `ubus call luci.argon_wallpaper get_url`

### Dark mode

- 3 modes controlled by `/etc/config/argon` → `mode` field:
  - `normal` (default): `@media (prefers-color-scheme: dark)` wraps `dark.css`
  - `dark`: dark.css always applied
  - `light`: dark.css never applied
- CSS variables (`--primary`, `--dark-primary`, etc.) control both themes
- Dark mode colors are baked into `dark.css` at compile time

### UCI configuration (`/etc/config/argon`)

```
config global
  option primary '#5e72e4'
  option dark_primary '#483d8b'
  option mode 'normal'           # normal|dark|light
  option blur '10'
  option blur_dark '10'
  option transparency '0.5'
  option transparency_dark '0.5'
  option online_wallpaper 'bing' # bing|unsplash|unsplash_<collection>|wallhaven|wallhaven_<tag>|none
```

## Key Code Patterns

### Vanilla JS (no jQuery, since v2.4.3)

- Module pattern: `return baseclass.extend({ __init__: function() { ... }, render: function() { ... } })`
- Menu loaded via `ui.menu.load().then(L.bind(this.render, this))`
- Event binding: `element.addEventListener('click', ui.createHandlerFn(this, 'methodName'))`
- DOM construction: `E('ul', { 'class': 'nav' }, [ items ])` (LuCI helper)
- String formatting: `'tabmenu-item-%s %s'.format(child.name, activeClass)`
- URL building: `L.url(base, path)` and `L.env.dispatchpath`

### LESS CSS

- First line of each LESS file specifies output (`// out: path` or `// out: false` for partials)
- `cascade.less` → `htdocs/luci-static/argon/css/cascade.css` (uncompressed)
- `dark.less` → `htdocs/luci-static/argon/css/dark.css` (compressed)
- Uses CSS custom properties (`:root { --primary: ... }`) extensively
- Nesting, `&.parent` selectors (standard Less)
- Imported order: fonts → normalize → pure-min → sysauth → layout → responsive → page-fix

### LuCI template patterns (.ut)

- `{% %}` for ucode logic blocks, `{{ expression }}` for output
- Variables available in templates: `dispatcher`, `media`, `resource`, `version`, `ctx`, `node`, `theme`
- `include("themes/" + theme + "/header_login")` for nested includes
- UCI access: `let cfg = cursor(); cfg.get_first('argon', 'global', 'primary')`
- `http.prepare_content('text/html; charset=UTF-8')` before any output
- File access: `import { readfile, access } from 'fs'`

## Releasing

- **Version**: `PKG_VERSION` (semver) and `PKG_RELEASE` (date-based) in Makefile
- **Release process**: Push to `master` that updates `Makefile` → GitHub Actions workflow:
  1. Checks if `PKG_VERSION` differs from latest GitHub release tag
  2. If new version: builds with OpenWrt SDK (24.10.0, x86/64)
  3. Creates GitHub release with `.ipk` artifacts
- **Release prerequisites**: Enable Actions → Settings → Actions → General → Read and write permissions

## Tailwind CSS

**Setup** (one-time):
```bash
npm install
```

**Build** (re-run when you add new Tailwind classes):
```bash
npm run build
```

Generated to `htdocs/luci-static/argon/css/tailwind.css` (~6KB minified). Linked in both `header.ut` and `header_login.ut`.

**Config**: `tailwind.config.js` scans `.ut`, `.js`, and `.html` files. Dark mode via `class` strategy. Extended theme includes custom colors (`surface`, `muted`, `muted-fg`, `border`, `border-strong`) and font families (`sans`, `logo`).

**Usage example** in templates:
```html
<div class="flex items-center justify-center min-h-screen bg-[#09090b]">
  <div class="w-full max-w-sm bg-surface border border-border rounded-xl shadow-2xl p-6">
```

**Important**: Run `npm run build && ./deploy.sh <ip>` after any change to `.ut` files that uses new Tailwind classes. The generated CSS is purged — only includes classes found in your templates.

## Updating CSS

After editing `.less` files, recompile:
```bash
# Requires the 'lessc' compiler (npm install -g less less-plugin-clean-css)
lessc less/cascade.less htdocs/luci-static/argon/css/cascade.css
lessc --clean-css less/dark.less htdocs/luci-static/argon/css/dark.css
```

The CSS outputs are committed to the repo (not gitignored).

## Gotchas

- **Not a Node.js project**: No `package.json`, no npm scripts, no webpack/vite. The "vite" mentioned in README is a future idea, not implemented here.
- **No local development server**: This theme runs inside OpenWrt's LuCI. Test by building the `.ipk` and installing on a router or in QEMU.
- **No automated tests**: There's no test suite. Visual/manual testing on real hardware or via OpenWrt SDK compile checks.
- **Fonts are all self-hosted**: `woff2` + `woff` formats only. No Google Fonts CDN dependency.
- **Logo font** ("TypoGraphica") is a custom font used only for the hostname in the sidebar. The rest uses "Google Sans" fallback chain.
- **Icon font** (`argon` family) is a custom icon set — adding new icons requires regenerating the woff files.
- **Compiled CSS is committed**: Don't forget to recompile LESS and commit both source and output.
- **Internet Explorer is dead**: The code intentionally ignores IE compatibility.
- **Firefox `backdrop-filter`**: Must be manually enabled in Firefox `about:config` (`layout.css.backdrop-filter.enabled`).

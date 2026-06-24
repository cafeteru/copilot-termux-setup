#!/bin/bash

# GitHub Copilot CLI Setup for Termux (Android)
#
# Since v1.0.48, Copilot CLI ships a Rust addon (runtime.node) compiled against
# glibc, which is incompatible with Android's Bionic libc.
#
# This script supports two strategies:
#   1. proot-distro (default, works on all Android versions)
#      Installs Copilot inside a Debian proot environment.
#   2. glibc-native (for devices where glibc-runner works)
#      Uses patchelf to run a linux-arm64 Node.js with Termux's glibc.
#
# Usage:
#   bash setup.sh                # Auto-detect best strategy
#   bash setup.sh proot          # Force proot-distro (default distro: debian)
#   bash setup.sh proot ubuntu   # Force proot-distro with a specific distro
#   bash setup.sh glibc          # Force glibc-native
#   bash setup.sh self-test      # Verify an existing proot install without changing it
#
# The proot strategy requires an apt-based distro (debian, ubuntu, kali, ...).
# You can also set the distro via the PROOT_DISTRO env var.
#
# Based on: https://github.com/github/copilot-cli/issues/3333

# Ensure running under Termux
if [ -z "${TERMUX_VERSION:-}" ]; then
  echo "Error: This setup script must be run inside Termux (TERMUX_VERSION not set). Exiting." >&2
  exit 1
fi

set -e  # Exit on error
set -u  # Exit on undefined variable

# Only aarch64 is supported
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
  echo "Error: Only aarch64/arm64 is supported. Detected: $ARCH" >&2
  exit 1
fi

# Configuration
NODE_VERSION="${NODE_VERSION:-v22.16.0}"
# PROOT_DISTRO can come from the env var or from the 2nd positional argument
# (e.g. `bash setup.sh proot ubuntu`). The inner installer uses apt-get, so
# only apt-based distros are supported.
PROOT_DISTRO="${PROOT_DISTRO:-debian}"
if [ -n "${2:-}" ]; then
    PROOT_DISTRO="$2"
fi

APT_BASED_DISTROS="debian ubuntu kali"
is_apt_based() {
    case " $APT_BASED_DISTROS " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# HELPER FUNCTIONS
################################################################################

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_step() {
    echo ""
    echo -e "${GREEN}▶${NC} ${BLUE}$1${NC}"
    echo ""
}

ensure_pkg() {
  local pkgname="$1"
  local check_cmd="${2:-}"

  if [ -n "$check_cmd" ]; then
    if command -v "$check_cmd" >/dev/null 2>&1; then
      print_info "$pkgname already available"
      return 0
    fi
  fi

  print_info "Installing $pkgname..."
  if pkg install -y "$pkgname"; then
    print_success "$pkgname installed"
  else
    print_error "Failed to install $pkgname"
    return 1
  fi
}

################################################################################
# STRATEGY SELECTION
################################################################################

# Determine strategy: proot or glibc-native
STRATEGY="${1:-auto}"

if [ "$STRATEGY" = "auto" ]; then
    SDK_VERSION="$(getprop ro.build.version.sdk 2>/dev/null || echo "0")"
    if [ "$SDK_VERSION" -ge 34 ] 2>/dev/null; then
        STRATEGY="proot"
        print_info "Android SDK $SDK_VERSION detected (14+). Using proot-distro strategy."
    else
        STRATEGY="glibc"
        print_info "Android SDK $SDK_VERSION detected. Using glibc-native strategy."
    fi
fi

################################################################################
# PROOT-DISTRO STRATEGY
################################################################################

install_via_proot() {
    print_header "GitHub Copilot CLI on Termux (proot-distro)"

    echo "This script will set up GitHub Copilot CLI inside a $PROOT_DISTRO proot"
    echo "environment. This is the most reliable method for Android 14+."
    echo ""
    echo "What it does:"
    echo "  1. Installs proot-distro and sets up $PROOT_DISTRO"
    echo "  2. Installs Node.js and Copilot CLI inside $PROOT_DISTRO"
    echo "  3. Creates a 'copilot' launcher in Termux"
    echo ""
    echo "Strategy: proot-distro ($PROOT_DISTRO)"
    echo "Termux ${TERMUX_VERSION:-unknown} (aarch64)"
    echo ""

    if [ -t 0 ]; then
        read -p "Press Enter to continue or Ctrl+C to abort..."
    fi

    ############################################################################
    # Step 1: Install proot-distro
    ############################################################################

    print_step "Step 1/4: Installing proot-distro"

    pkg update -y || print_warning "pkg update had issues, continuing..."
    ensure_pkg proot-distro proot-distro

    if ! is_apt_based "$PROOT_DISTRO"; then
        print_error "Distro '$PROOT_DISTRO' is not supported by this installer."
        print_info  "Supported distros (apt-based): $APT_BASED_DISTROS"
        print_info  "If you need another distro, install it manually and adapt the inner script."
        exit 1
    fi

    # Try to install the distro. If it already exists, proot-distro exits
    # non-zero with "container already exists" — that's fine, continue.
    print_info "Installing $PROOT_DISTRO (skipped automatically if already present)..."
    PROOT_INSTALL_OUTPUT="$(proot-distro install "$PROOT_DISTRO" 2>&1)" || PROOT_INSTALL_STATUS=$?
    PROOT_INSTALL_STATUS="${PROOT_INSTALL_STATUS:-0}"
    if [ "$PROOT_INSTALL_STATUS" -ne 0 ]; then
        echo "$PROOT_INSTALL_OUTPUT"
        if echo "$PROOT_INSTALL_OUTPUT" | grep -qi "already exists"; then
            print_info "$PROOT_DISTRO already present"
        else
            print_error "Failed to install $PROOT_DISTRO"
            exit 1
        fi
    else
        echo "$PROOT_INSTALL_OUTPUT"
        print_success "$PROOT_DISTRO installed or already up to date"
    fi

    ############################################################################
    # Step 2: Install Node.js and Copilot inside the proot
    ############################################################################

    print_step "Step 2/4: Installing Node.js and Copilot CLI inside $PROOT_DISTRO"

    # Create an install script to run inside the proot environment
    PROOT_SETUP_SCRIPT="$(mktemp)"
    cat > "$PROOT_SETUP_SCRIPT" << 'PROOTSCRIPT'
#!/bin/sh
set -e

# proot-distro leaks Termux's $PATH into the container, which exposes Termux's
# `node` (built for Android — process.platform === "android"). @github/copilot
# then looks for an "@github/copilot-android-*" package that does not exist.
# Force a clean Debian PATH so we always use the apt-installed Node at /usr/bin/node.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Make all apt operations non-interactive
export DEBIAN_FRONTEND=noninteractive

echo "==> Updating package lists..."
apt-get update -qq

echo "==> Installing dependencies..."
apt-get install -y -qq --no-install-recommends curl ca-certificates git bash 2>&1 | tail -5

# Install Node.js from NodeSource if Debian's /usr/bin/node is missing.
# Check for the specific path, not `command -v node`, to avoid false positives
# from Termux's node leaking through the proot mount.
if [ ! -x /usr/bin/node ]; then
    echo "==> Installing Node.js (NodeSource 22.x)..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
    apt-get install -y -qq nodejs 2>&1 | tail -3
fi

if [ ! -x /usr/bin/node ]; then
    echo "ERROR: /usr/bin/node not installed"
    exit 1
fi

NODE_BIN=/usr/bin/node
NPM_BIN=/usr/bin/npm
echo "==> Node.js $("$NODE_BIN" --version) at $NODE_BIN"
echo "==> Platform: $("$NODE_BIN" -e 'console.log(process.platform, process.arch)')"

# Install Copilot CLI
# Use --include=optional to ensure the platform-specific binary package
# (e.g. @github/copilot-linux-arm64) is installed. Some npm configs disable
# optional deps, which leaves the CLI without its native binary.
echo "==> Installing @github/copilot..."
"$NPM_BIN" install -g --include=optional @github/copilot

# Verify the platform package was actually installed. If not, install it
# explicitly. Map uname -m to the package suffix used by @github/copilot.
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|amd64)   PLATFORM_PKG="@github/copilot-linux-x64" ;;
    aarch64|arm64)  PLATFORM_PKG="@github/copilot-linux-arm64" ;;
    *) PLATFORM_PKG="" ;;
esac

NPM_ROOT="$("$NPM_BIN" root -g)"
if [ -n "$PLATFORM_PKG" ] && [ ! -d "$NPM_ROOT/$PLATFORM_PKG" ]; then
    echo "==> Platform package $PLATFORM_PKG missing, installing explicitly..."
    "$NPM_BIN" install -g --force "$PLATFORM_PKG" || {
        echo "ERROR: Could not install platform package $PLATFORM_PKG"
        exit 1
    }
fi

# Always create our own wrapper at a known absolute path to avoid PATH conflicts
# with Termux's launcher (which is visible inside proot via filesystem mount)
COPILOT_LOADER="$NPM_ROOT/@github/copilot/npm-loader.js"
if [ ! -f "$COPILOT_LOADER" ]; then
    echo "ERROR: Copilot CLI not found after install at $COPILOT_LOADER"
    exit 1
fi

# Wrapper pins both PATH and node to the Debian install. Without this, Termux's
# leaked node (process.platform === "android") is used and copilot fails with
# "no platform package found".
echo "==> Creating internal copilot wrapper at /usr/local/bin/copilot-cli..."
cat > /usr/local/bin/copilot-cli << WRAPPER
#!/bin/sh
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
exec /usr/bin/node "$COPILOT_LOADER" "\$@"
WRAPPER
chmod +x /usr/local/bin/copilot-cli

echo "==> Copilot CLI installed successfully"
/usr/local/bin/copilot-cli --version 2>/dev/null || true
PROOTSCRIPT

    chmod +x "$PROOT_SETUP_SCRIPT"

    if proot-distro login "$PROOT_DISTRO" -- sh "$PROOT_SETUP_SCRIPT"; then
        print_success "Copilot CLI installed inside $PROOT_DISTRO"
    else
        print_error "Failed to install Copilot inside proot"
        rm -f "$PROOT_SETUP_SCRIPT"
        exit 1
    fi
    rm -f "$PROOT_SETUP_SCRIPT"

    ############################################################################
    # Step 3: Create the copilot launcher in Termux
    ############################################################################

    print_step "Step 3/4: Creating copilot launcher"

    rm -f "$PREFIX/bin/copilot"
    cat > "$PREFIX/bin/copilot" << LAUNCHER
#!/data/data/com.termux/files/usr/bin/bash
# GitHub Copilot CLI launcher for Termux (proot-distro)
# Generated by copilot-termux-setup
# Uses absolute path /usr/local/bin/copilot-cli inside proot to avoid PATH conflict
# with this Termux launcher (which is visible inside the proot filesystem).

DISTRO="$PROOT_DISTRO"
CWD="$(pwd)"

# $0 inside sh -c receives CWD; "$@" expands to the remaining args (the user's args).
# No `shift` needed: positional params 1..N already exclude $0.
INNER='cd "$0" 2>/dev/null; exec /usr/local/bin/copilot-cli "$@"'

exec proot-distro login "$DISTRO" -- /bin/sh -c "$INNER" "$CWD" "$@"
LAUNCHER
    chmod +x "$PREFIX/bin/copilot"
    print_success "copilot launcher created at $PREFIX/bin/copilot"

    ############################################################################
    # Step 4: Verify
    ############################################################################

    print_step "Step 4/4: Verifying installation"

    if COPILOT_VERSION=$(copilot --version 2>/dev/null); then
        print_success "copilot --version: $COPILOT_VERSION"
    else
        print_warning "copilot --version check failed (may still work interactively)"
        print_info "Try running: copilot"
    fi

    print_header "Installation Complete!"

    echo "GitHub Copilot CLI is installed inside a $PROOT_DISTRO proot environment."
    echo ""
    echo "Usage:"
    echo "  copilot              # Launch Copilot CLI"
    echo "  copilot --version    # Check version"
    echo ""
    echo "The 'copilot' command automatically enters the proot environment."
    echo "Your Termux filesystem is accessible at the same paths inside proot."
    echo ""
    echo "To update Copilot:"
    echo "  proot-distro login $PROOT_DISTRO -- /usr/bin/npm update -g --include=optional @github/copilot"
    echo "  bash setup.sh proot"
    echo ""
    echo "Next steps:"
    echo "  1. Launch Copilot: copilot"
    echo "  2. Sign in: /login"
    echo "  3. Start coding with AI assistance!"
    echo ""
    print_success "Setup completed successfully!"
}

################################################################################
# GLIBC-NATIVE STRATEGY
################################################################################

install_via_glibc() {
    GLIBC_PREFIX="/data/data/com.termux/files/usr/glibc"
    NODE_DIR="$HOME/node-linux"
    COPILOT_DIR="${PREFIX}/lib/node_modules/@github/copilot"

    print_header "GitHub Copilot CLI on Termux (glibc-native)"

    echo "This script will set up GitHub Copilot CLI using the glibc"
    echo "compatibility layer with patchelf (no proot required)."
    echo ""
    echo "What it does:"
    echo "  1. Installs glibc-runner and patchelf"
    echo "  2. Downloads official linux-arm64 Node.js binary"
    echo "  3. Patches Node.js to use Termux's glibc"
    echo "  4. Installs @github/copilot via npm"
    echo "  5. Creates wrapper scripts and patches"
    echo ""
    echo "Strategy: glibc-native"
    echo "Termux ${TERMUX_VERSION:-unknown} (aarch64)"
    echo "Node.js target: $NODE_VERSION"
    echo ""

    if [ -t 0 ]; then
        read -p "Press Enter to continue or Ctrl+C to abort..."
    fi

    ############################################################################
    # Step 1: Install system dependencies
    ############################################################################

    print_step "Step 1/7: Installing system dependencies"

    # Clean up stale/broken repository entries
    SOURCES_LIST="$PREFIX/etc/apt/sources.list"
    if grep -q "grimler.se/termux-glibc" "$SOURCES_LIST" 2>/dev/null; then
        print_info "Removing stale grimler.se glibc repo..."
        sed -i '/grimler\.se\/termux-glibc/d' "$SOURCES_LIST"
    fi

    pkg update -y || print_warning "pkg update had issues, continuing..."
    pkg install -y termux-keyring 2>/dev/null || true

    ensure_pkg nodejs node
    ensure_pkg curl curl
    ensure_pkg tar tar
    ensure_pkg xz-utils xz
    ensure_pkg ripgrep rg

    # Install glibc repository
    print_info "Adding glibc repository..."
    pkg install -y glibc-repo 2>/dev/null || {
        print_warning "glibc-repo package not found, adding manually..."
        GLIBC_LIST="$PREFIX/etc/apt/sources.list.d/glibc.list"
        mkdir -p "$PREFIX/etc/apt/sources.list.d"
        cat > "$GLIBC_LIST" << 'REPO'
deb [trusted=yes] https://packages-cf.termux.dev/apt/termux-glibc/ glibc stable
REPO
        pkg update -y || true
    }

    # Install glibc-runner
    if pkg install -y glibc-runner; then
        print_success "glibc-runner installed"
    else
        print_error "Failed to install glibc-runner."
        echo "Consider using: bash setup.sh proot" >&2
        exit 1
    fi

    # Fix permissions and verify ld.so
    LD_SO="$GLIBC_PREFIX/lib/ld-linux-aarch64.so.1"
    chmod +x "$LD_SO" 2>/dev/null || true
    chmod +x "$GLIBC_PREFIX/bin/ld.so" 2>/dev/null || true

    if [ ! -f "$LD_SO" ]; then
        print_error "glibc dynamic linker not found at $LD_SO"
        exit 1
    fi
    print_success "glibc dynamic linker found"

    ensure_pkg patchelf patchelf

    ############################################################################
    # Step 2: Download and patch Node.js
    ############################################################################

    print_step "Step 2/7: Downloading linux-arm64 Node.js $NODE_VERSION"

    NODE_INSTALL_DIR="$NODE_DIR/$NODE_VERSION"

    if [ -f "$NODE_INSTALL_DIR/bin/node" ]; then
        print_info "Node.js $NODE_VERSION already downloaded, skipping"
    else
        mkdir -p "$NODE_DIR"
        NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-arm64.tar.xz"
        print_info "Downloading from $NODE_URL ..."

        TMP_TARBALL="$(mktemp)"
        if curl -fSL "$NODE_URL" -o "$TMP_TARBALL"; then
            tar xJf "$TMP_TARBALL" -C "$NODE_DIR/"
            mv "$NODE_DIR/node-${NODE_VERSION}-linux-arm64" "$NODE_INSTALL_DIR"
            rm -f "$TMP_TARBALL"
            print_success "Node.js $NODE_VERSION downloaded"
        else
            rm -f "$TMP_TARBALL"
            print_error "Failed to download Node.js $NODE_VERSION"
            exit 1
        fi
    fi

    # Patch Node.js ELF interpreter
    print_info "Patching Node.js binary with patchelf..."
    CURRENT_INTERP="$(patchelf --print-interpreter "$NODE_INSTALL_DIR/bin/node" 2>/dev/null || echo "")"
    if [ "$CURRENT_INTERP" = "$LD_SO" ]; then
        print_info "Node.js binary already patched"
    else
        if patchelf --set-interpreter "$LD_SO" --set-rpath "$GLIBC_PREFIX/lib" "$NODE_INSTALL_DIR/bin/node"; then
            print_success "Node.js binary patched"
        else
            print_error "Failed to patchelf Node.js binary"
            exit 1
        fi
    fi

    # Verify
    GLIBC_TEST="$(LD_LIBRARY_PATH="$GLIBC_PREFIX/lib" "$NODE_INSTALL_DIR/bin/node" -e "console.log('ok')" 2>&1)" || true
    if echo "$GLIBC_TEST" | grep -q "ok"; then
        print_success "Node.js binary works with glibc"
    else
        print_error "Node.js failed to run: $GLIBC_TEST"
        echo ""
        echo "The glibc-native strategy doesn't work on this device."
        echo "Re-run with proot strategy: bash setup.sh proot"
        exit 1
    fi

    ############################################################################
    # Step 3: Install Copilot
    ############################################################################

    print_step "Step 3/7: Installing @github/copilot globally via npm"

    if npm install -g --include=optional @github/copilot; then
        print_success "@github/copilot installed"
    else
        print_error "Failed to install @github/copilot"
        exit 1
    fi

    if [ ! -d "$COPILOT_DIR" ]; then
        COPILOT_DIR="$(npm root -g)/@github/copilot"
    fi
    if [ ! -d "$COPILOT_DIR" ]; then
        print_error "Cannot find Copilot install directory"
        exit 1
    fi
    print_info "Copilot installed at: $COPILOT_DIR"

    ############################################################################
    # Step 4: Create node-wrapper
    ############################################################################

    print_step "Step 4/7: Creating node-wrapper script"

    cat > "$NODE_INSTALL_DIR/bin/node-wrapper" << EOF
#!/data/data/com.termux/files/usr/bin/bash
REAL_NODE="\$(dirname "\$0")/node"
export LD_LIBRARY_PATH="$GLIBC_PREFIX/lib"
unset LD_PRELOAD
exec "\$REAL_NODE" "\$@"
EOF
    chmod +x "$NODE_INSTALL_DIR/bin/node-wrapper"
    print_success "node-wrapper created"

    ############################################################################
    # Step 5: Create preload script
    ############################################################################

    print_step "Step 5/7: Creating preload script"

    cat > "$NODE_INSTALL_DIR/copilot-preload.js" << 'EOF'
const path = require('path');
const wrapperPath = path.join(__dirname, 'bin', 'node-wrapper');
Object.defineProperty(process, 'execPath', {
  value: wrapperPath,
  writable: true,
  configurable: true
});
if (process.argv[0] && process.argv[0].includes('ld-linux-aarch64')) {
  process.argv[0] = wrapperPath;
}
EOF
    print_success "copilot-preload.js created"

    ############################################################################
    # Step 6: Create copilot launcher
    ############################################################################

    print_step "Step 6/7: Creating copilot launcher"

    rm -f "$PREFIX/bin/copilot"
    cat > "$PREFIX/bin/copilot" << EOF
#!/data/data/com.termux/files/usr/bin/bash
# GitHub Copilot CLI launcher for Termux (glibc-native)
# Generated by copilot-termux-setup

export SSL_CERT_FILE="/data/data/com.termux/files/usr/etc/tls/cert.pem"
export SSL_CERT_DIR="/data/data/com.termux/files/usr/etc/tls/certs"
export NODE_EXTRA_CA_CERTS="/data/data/com.termux/files/usr/etc/tls/cert.pem"
export NODE_OPTIONS="--no-warnings"
export LD_LIBRARY_PATH="$GLIBC_PREFIX/lib"
unset LD_PRELOAD

exec "$NODE_INSTALL_DIR/bin/node" -r "$NODE_INSTALL_DIR/copilot-preload.js" "$COPILOT_DIR/npm-loader.js" "\$@"
EOF
    chmod +x "$PREFIX/bin/copilot"
    print_success "copilot launcher created at $PREFIX/bin/copilot"

    ############################################################################
    # Step 7: Patch shell paths
    ############################################################################

    print_step "Step 7/7: Patching hardcoded shell paths for Termux"

    for JS_FILE in "$COPILOT_DIR/app.js" "$COPILOT_DIR/sdk/index.js"; do
        if [ -f "$JS_FILE" ] && grep -q '"/bin/bash"' "$JS_FILE"; then
            sed -i 's|"/bin/bash"|process.env.SHELL\|\|"/bin/bash"|g' "$JS_FILE"
            print_success "Patched $(basename "$JS_FILE")"
        fi
    done

    # Symlink ripgrep
    SYSTEM_RG="$(command -v rg 2>/dev/null || true)"
    if [ -n "$SYSTEM_RG" ]; then
        COPILOT_RG_DIR="$COPILOT_DIR/ripgrep/bin/linux-arm64"
        if [ ! -e "$COPILOT_RG_DIR/rg" ]; then
            mkdir -p "$COPILOT_RG_DIR"
            ln -sf "$SYSTEM_RG" "$COPILOT_RG_DIR/rg"
            print_success "Linked system rg to Copilot expected path"
        fi
    fi

    ############################################################################
    # Verify
    ############################################################################

    print_header "Verifying Installation"

    if COPILOT_VERSION=$(copilot --version 2>/dev/null); then
        print_success "copilot --version: $COPILOT_VERSION"
    else
        print_warning "copilot --version failed (may still work interactively)"
    fi

    print_header "Installation Complete!"

    echo "Components installed:"
    echo "  • Node.js $NODE_VERSION (linux-arm64, patched) at $NODE_INSTALL_DIR"
    echo "  • @github/copilot at $COPILOT_DIR"
    echo "  • Launcher at $PREFIX/bin/copilot"
    echo ""
    echo "To update Copilot, re-run this script after:"
    echo "  npm update -g @github/copilot"
    echo ""
    echo "Next steps:"
    echo "  1. Launch Copilot: copilot"
    echo "  2. Sign in: /login"
    echo "  3. Start coding with AI assistance!"
    echo ""
    print_success "Setup completed successfully!"
}

################################################################################
# SELF-TEST
################################################################################

# Read-only verification of an existing proot install. Useful after upgrades to
# detect regressions (e.g. @github/copilot changing its package layout) without
# mutating the environment. Exits non-zero on the first failure with a clear
# message pointing at the broken stage.
run_self_test() {
    print_header "GitHub Copilot CLI self-test (proot)"

    FAILED=0

    # Run a command directly (no eval). Args after $1 are the command + args.
    # Filters out harmless proot warnings about /proc/self/fd that appear when
    # proot-distro's stdio is captured into a variable.
    run_cmd() {
        local label="$1"
        shift
        local out
        if out="$("$@" 2>&1)"; then
            out="$(printf '%s\n' "$out" | grep -v "proot warning: can't sanitize binding" || true)"
            print_success "$label"
            [ -n "$out" ] && echo "    $out"
            return 0
        else
            out="$(printf '%s\n' "$out" | grep -v "proot warning: can't sanitize binding" || true)"
            print_error "$label"
            [ -n "$out" ] && echo "    $out"
            FAILED=$((FAILED + 1))
            return 1
        fi
    }

    # Run a shell command inside the proot. $2 is passed as the single argument
    # to `sh -c`, so quoting follows normal sh rules (no eval).
    proot_run() {
        local label="$1"
        local cmd="$2"
        run_cmd "$label" proot-distro login "$PROOT_DISTRO" -- /bin/sh -c "$cmd"
    }

    run_cmd   "proot-distro available"          command -v proot-distro
    run_cmd   "Termux launcher present"         test -x "$PREFIX/bin/copilot"
    run_cmd   "$PROOT_DISTRO container usable"  proot-distro login "$PROOT_DISTRO" -- /bin/true

    proot_run "Debian /usr/bin/node present"      "test -x /usr/bin/node"
    proot_run "Node reports linux platform" \
        '/usr/bin/node -e "if (process.platform !== \"linux\") { console.error(\"got \" + process.platform); process.exit(1) }"'
    proot_run "Internal copilot wrapper present"  "test -x /usr/local/bin/copilot-cli"
    proot_run "@github/copilot installed" \
        'test -f "$(/usr/bin/npm root -g)/@github/copilot/npm-loader.js"'

    # Platform package check (matches what install_via_proot installs)
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64|amd64)   PLATFORM_PKG="@github/copilot-linux-x64" ;;
        aarch64|arm64)  PLATFORM_PKG="@github/copilot-linux-arm64" ;;
        *) PLATFORM_PKG="" ;;
    esac
    if [ -n "$PLATFORM_PKG" ]; then
        proot_run "Platform package $PLATFORM_PKG installed" \
            "test -d \"\$(/usr/bin/npm root -g)/$PLATFORM_PKG\""
    fi

    proot_run "copilot --version runs"  "/usr/local/bin/copilot-cli --version"

    echo ""
    if [ "$FAILED" -eq 0 ]; then
        print_success "Self-test passed"
        exit 0
    else
        print_error "Self-test failed ($FAILED check(s))"
        print_info "Re-run the installer to repair: bash setup.sh proot"
        exit 1
    fi
}

################################################################################
# RUN SELECTED STRATEGY
################################################################################

case "$STRATEGY" in
    proot)
        install_via_proot
        ;;
    glibc)
        install_via_glibc
        ;;
    self-test)
        run_self_test
        ;;
    *)
        echo "Unknown strategy: $STRATEGY" >&2
        echo "Usage: bash setup.sh [proot|glibc|auto|self-test]" >&2
        exit 1
        ;;
esac

exit 0

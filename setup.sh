#!/bin/bash

# GitHub Copilot CLI Setup for Termux (Pure Native - No PRoot)
#
# Since v1.0.48, Copilot CLI ships a self-contained Node.js Single Executable
# Application (SEA) binary (@github/copilot-linux-arm64/copilot) and native
# Rust addons (runtime.node, cli-native.node, copilot-runtime) compiled against
# glibc, which is incompatible with Android's Bionic libc.
#
# This setup runs Copilot CLI purely in Termux (no proot, no patchelf corruption,
# no separate Node.js download) using Termux's native glibc dynamic linker
# (ld-linux-aarch64.so.1) directly on @github/copilot-linux-arm64/copilot.
#
# Usage:
#   bash setup.sh              # Install/update Copilot CLI
#   bash setup.sh self-test    # Verify existing installation
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
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
GLIBC_PREFIX="${PREFIX}/glibc"
LD_SO="${GLIBC_PREFIX}/lib/ld-linux-aarch64.so.1"
PRELOAD_CJS="${GLIBC_PREFIX}/etc/copilot-termux-preload.cjs"
PLATFORM_PKG="@github/copilot-linux-arm64"
COPILOT_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/copilot/pkg/linux-arm64"

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
# INSTALLATION (PURE TERMUX NATIVE)
################################################################################

install_native() {
    print_header "GitHub Copilot CLI on Termux (Pure Native - No PRoot)"

    echo "This script installs GitHub Copilot CLI purely in Termux using"
    echo "Termux's native glibc dynamic linker (no proot container required)."
    echo ""
    echo "What it does:"
    echo "  1. Installs glibc-runner and required Termux packages"
    echo "  2. Installs @github/copilot and @github/copilot-linux-arm64 via npm"
    echo "  3. Extracts the bundled Copilot SEA runtime into ~/.cache/copilot"
    echo "  4. Installs Termux runtime preload hook and launcher at \$PREFIX/bin/copilot"
    echo ""
    echo "Architecture: $ARCH"
    echo "Termux: ${TERMUX_VERSION:-unknown}"
    echo ""

    if [ -t 0 ]; then
        read -p "Press Enter to continue or Ctrl+C to abort..."
    fi

    ############################################################################
    # Step 1: Install system dependencies
    ############################################################################

    print_step "Step 1/5: Installing system dependencies"

    SOURCES_LIST="$PREFIX/etc/apt/sources.list"
    if grep -q "grimler.se/termux-glibc" "$SOURCES_LIST" 2>/dev/null; then
        print_info "Removing stale grimler.se glibc repo..."
        sed -i '/grimler\.se\/termux-glibc/d' "$SOURCES_LIST"
    fi

    pkg update -y || print_warning "pkg update had issues, continuing..."
    pkg install -y termux-keyring 2>/dev/null || true

    ensure_pkg ca-certificates
    mkdir -p "$PREFIX/etc/tls/certs"
    ensure_pkg nodejs node
    ensure_pkg ripgrep rg

    # Install glibc repository
    print_info "Adding glibc repository..."
    pkg install -y glibc-repo 2>/dev/null || {
        print_warning "glibc-repo package not found in main repo, adding manually..."
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
        exit 1
    fi

    # Fix permissions and verify ld.so
    chmod +x "$LD_SO" 2>/dev/null || true
    chmod +x "$GLIBC_PREFIX/bin/ld.so" 2>/dev/null || true

    if [ ! -f "$LD_SO" ]; then
        print_error "glibc dynamic linker not found at $LD_SO"
        exit 1
    fi
    print_success "glibc dynamic linker found at $LD_SO"

    ############################################################################
    # Step 2: Install Copilot CLI and platform binary
    ############################################################################

    print_step "Step 2/5: Installing @github/copilot and $PLATFORM_PKG via npm"

    if npm install -g --include=optional @github/copilot; then
        print_success "@github/copilot installed"
    else
        print_error "Failed to install @github/copilot"
        exit 1
    fi

    # Because Termux reports process.platform === "android", npm skips optional
    # dependencies targeting linux. Install @github/copilot-linux-arm64 with --force.
    NPM_ROOT="$(npm root -g)"
    COPILOT_BIN="$NPM_ROOT/$PLATFORM_PKG/copilot"

    if [ ! -x "$COPILOT_BIN" ]; then
        print_info "Installing platform package $PLATFORM_PKG with --force..."
        npm install -g --force "$PLATFORM_PKG" || {
            print_error "Failed to install platform package $PLATFORM_PKG"
            exit 1
        }
    fi

    if [ ! -x "$COPILOT_BIN" ]; then
        print_error "Copilot native binary not found at $COPILOT_BIN"
        exit 1
    fi
    print_success "Copilot native binary installed at $COPILOT_BIN"

    ############################################################################
    # Step 3: Create Termux runtime preload hook
    ############################################################################

    print_step "Step 3/5: Creating Termux runtime preload hook"

    mkdir -p "$(dirname "$PRELOAD_CJS")"
    cat > "$PRELOAD_CJS" << 'EOF'
// GitHub Copilot CLI Termux Native Preload Hook
const cp = require('node:child_process');
const fs = require('node:fs');

const PREFIX = process.env.PREFIX || '/data/data/com.termux/files/usr';
const GLIBC_PREFIX = `${PREFIX}/glibc`;
const LD_SO = `${GLIBC_PREFIX}/lib/ld-linux-aarch64.so.1`;
const GLIBC_LIB = `${GLIBC_PREFIX}/lib`;
const TERMUX_EXEC_SO = `${PREFIX}/lib/libtermux-exec-ld-preload.so`;
const BASH_BIN = `${PREFIX}/bin/bash`;
const SH_BIN = `${PREFIX}/bin/sh`;
const COPILOT_LAUNCHER = `${PREFIX}/bin/copilot`;

// 1. Point process.execPath and argv[0] to the Termux launcher
Object.defineProperty(process, 'execPath', {
  value: COPILOT_LAUNCHER,
  writable: true,
  configurable: true,
});
if (process.argv[0] && process.argv[0].includes('ld-linux-aarch64')) {
  process.argv[0] = COPILOT_LAUNCHER;
}

// 2. Ensure SHELL and COPILOT_BASH_PATH point to Termux bash
if (!process.env.SHELL || !fs.existsSync(process.env.SHELL)) {
  process.env.SHELL = BASH_BIN;
}
if (!process.env.COPILOT_BASH_PATH) {
  process.env.COPILOT_BASH_PATH = BASH_BIN;
}

// 3. Rewrite /bin/* and /usr/bin/* paths and wrap glibc ELF binaries in child_process
function rewriteFile(file) {
  if (typeof file !== 'string') return file;
  if (file === '/bin/bash' || file === '/usr/bin/bash') return BASH_BIN;
  if (file === '/bin/sh' || file === '/usr/bin/sh') return SH_BIN;
  if (file.startsWith('/bin/') || file.startsWith('/usr/bin/')) {
    const candidate = `${PREFIX}/bin/${file.split('/').pop()}`;
    if (fs.existsSync(candidate)) return candidate;
  }
  return file;
}

function isGlibcElf(file) {
  if (typeof file !== 'string') return false;
  return file.endsWith('/copilot-runtime') || (file.endsWith('/copilot') && file !== COPILOT_LAUNCHER);
}

const origSpawn = cp.ChildProcess.prototype.spawn;
cp.ChildProcess.prototype.spawn = function (options) {
  if (options && typeof options === 'object') {
    if (isGlibcElf(options.file)) {
      const target = options.file;
      options.file = LD_SO;
      options.args = [LD_SO, '--library-path', GLIBC_LIB, target, ...(options.args ? options.args.slice(1) : [])];
    } else {
      const rewritten = rewriteFile(options.file);
      if (rewritten !== options.file) {
        if (Array.isArray(options.args) && options.args[0] === options.file) {
          options.args[0] = rewritten;
        }
        options.file = rewritten;
      }
      if (Array.isArray(options.envPairs) && fs.existsSync(TERMUX_EXEC_SO)) {
        const hasPreload = options.envPairs.some((p) => p.startsWith('LD_PRELOAD='));
        if (!hasPreload) {
          options.envPairs.push(`LD_PRELOAD=${TERMUX_EXEC_SO}`);
        }
      }
    }
  }
  return origSpawn.call(this, options);
};

const origSpawnSync = cp.spawnSync;
cp.spawnSync = function (file, args, options) {
  if (isGlibcElf(file)) {
    const actualArgs = Array.isArray(args) ? args : [];
    const actualOpts = (!Array.isArray(args) && args) ? args : options;
    return origSpawnSync.call(this, LD_SO, ['--library-path', GLIBC_LIB, file, ...actualArgs], actualOpts);
  }
  return origSpawnSync.call(this, rewriteFile(file), args, options);
};
EOF
    print_success "Preload hook created at $PRELOAD_CJS"

    ############################################################################
    # Step 4: Extract bundled package and patch index.js
    ############################################################################

    print_step "Step 4/5: Extracting bundled Copilot package"

    if env -u LD_PRELOAD COPILOT_SEA_EXTRACT_ONLY=1 "$LD_SO" --library-path "$GLIBC_PREFIX/lib" "$COPILOT_BIN"; then
        print_success "Bundled package extracted to $COPILOT_CACHE_DIR"
    else
        print_error "Failed to extract bundled package from $COPILOT_BIN"
        exit 1
    fi

    for INDEX_JS in "$COPILOT_CACHE_DIR"/*/index.js; do
        if [ -f "$INDEX_JS" ] && ! grep -q "copilot-termux-preload.cjs" "$INDEX_JS"; then
            sed -i "/createRequire(import.meta.url);/a require(\"$PRELOAD_CJS\");" "$INDEX_JS"
            print_success "Injected Termux preload hook into $INDEX_JS"
        fi
    done

    ############################################################################
    # Step 5: Create copilot launcher
    ############################################################################

    print_step "Step 5/5: Creating copilot launcher"

    rm -f "$PREFIX/bin/copilot"
    cat > "$PREFIX/bin/copilot" << EOF
#!/data/data/com.termux/files/usr/bin/bash
# GitHub Copilot CLI launcher for Termux (Pure Native - No PRoot)
# Generated by copilot-termux-setup

PREFIX="\${PREFIX:-/data/data/com.termux/files/usr}"
GLIBC_PREFIX="\${PREFIX}/glibc"
LD_SO="\${GLIBC_PREFIX}/lib/ld-linux-aarch64.so.1"
PRELOAD_CJS="\${GLIBC_PREFIX}/etc/copilot-termux-preload.cjs"
COPILOT_BIN="\${PREFIX}/lib/node_modules/@github/copilot-linux-arm64/copilot"
COPILOT_CACHE_DIR="\${XDG_CACHE_HOME:-\$HOME/.cache}/copilot/pkg/linux-arm64"

# Ensure any newly extracted/updated Copilot version has the Termux preload hook
if [ -d "\$COPILOT_CACHE_DIR" ]; then
    for idx in "\$COPILOT_CACHE_DIR"/*/index.js; do
        if [ -f "\$idx" ] && ! grep -q "copilot-termux-preload.cjs" "\$idx" 2>/dev/null; then
            sed -i "/createRequire(import.meta.url);/a require(\\"\$PRELOAD_CJS\\");" "\$idx" 2>/dev/null || true
        fi
    done
fi

export SSL_CERT_FILE="\$PREFIX/etc/tls/cert.pem"
export SSL_CERT_DIR="\$PREFIX/etc/tls/certs"
export NODE_EXTRA_CA_CERTS="\$PREFIX/etc/tls/cert.pem"
export SHELL="\${SHELL:-\$PREFIX/bin/bash}"
export COPILOT_BASH_PATH="\$PREFIX/bin/bash"
unset LD_PRELOAD

exec "\$LD_SO" --library-path "\$GLIBC_PREFIX/lib" "\$COPILOT_BIN" "\$@"
EOF
    chmod +x "$PREFIX/bin/copilot"
    print_success "copilot launcher created at $PREFIX/bin/copilot"

    ############################################################################
    # Verify
    ############################################################################

    print_header "Verifying Installation"

    if COPILOT_VERSION=$("$PREFIX/bin/copilot" --version 2>&1); then
        print_success "copilot --version:"
        echo "$COPILOT_VERSION"
    else
        print_error "copilot --version failed:"
        echo "$COPILOT_VERSION"
        exit 1
    fi

    print_header "Installation Complete!"

    echo "Components installed (Pure Termux - No PRoot):"
    echo "  • @github/copilot-linux-arm64 at $COPILOT_BIN"
    echo "  • Extracted runtime at $COPILOT_CACHE_DIR"
    echo "  • Preload hook at $PRELOAD_CJS"
    echo "  • Launcher at $PREFIX/bin/copilot"
    echo ""
    echo "To update Copilot, re-run:"
    echo "  bash setup.sh"
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

run_self_test() {
    print_header "GitHub Copilot CLI self-test (Pure Native)"

    FAILED=0
    NPM_ROOT="$(npm root -g)"
    COPILOT_BIN="$NPM_ROOT/$PLATFORM_PKG/copilot"

    run_cmd() {
        local label="$1"
        shift
        local out
        if out="$("$@" 2>&1)"; then
            print_success "$label"
            [ -n "$out" ] && echo "    $out"
            return 0
        else
            print_error "$label"
            [ -n "$out" ] && echo "    $out"
            FAILED=$((FAILED + 1))
            return 1
        fi
    }

    run_cmd "glibc linker exists" test -f "$LD_SO"
    run_cmd "Copilot SEA binary present" test -x "$COPILOT_BIN"
    run_cmd "Preload hook present" test -f "$PRELOAD_CJS"
    run_cmd "Termux launcher present" test -x "$PREFIX/bin/copilot"
    run_cmd "copilot --binary-version runs" "$PREFIX/bin/copilot" --binary-version
    run_cmd "copilot --version runs" "$PREFIX/bin/copilot" --version

    echo ""
    if [ "$FAILED" -eq 0 ]; then
        print_success "Self-test passed"
        exit 0
    else
        print_error "Self-test failed ($FAILED check(s))"
        print_info "Re-run the installer to repair: bash setup.sh"
        exit 1
    fi
}

################################################################################
# MAIN
################################################################################

ACTION="${1:-install}"

case "$ACTION" in
    install|native|run)
        install_native
        ;;
    self-test)
        run_self_test
        ;;
    *)
        echo "Usage: bash setup.sh [install|self-test]" >&2
        exit 1
        ;;
esac

exit 0

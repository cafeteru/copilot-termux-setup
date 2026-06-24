#!/bin/bash

# GitHub Copilot CLI Setup for Termux (Android)
#
# Since v1.0.48, Copilot CLI ships a Rust addon (runtime.node) compiled against
# glibc, which is incompatible with Android's Bionic libc. This script works
# around the issue by using Termux's glibc-runner package to execute a standard
# linux-arm64 Node.js binary under the glibc dynamic linker.
#
# Based on: https://github.com/github/copilot-cli/issues/3333

# Ensure running under Termux
if [ -z "${TERMUX_VERSION:-}" ]; then
  echo "Error: This setup script must be run inside Termux (TERMUX_VERSION not set). Exiting." >&2
  exit 1
fi

set -e  # Exit on error
set -u  # Exit on undefined variable

# Only aarch64 is supported (vast majority of modern Android devices)
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
  echo "Error: Only aarch64/arm64 is supported. Detected: $ARCH" >&2
  exit 1
fi

# Configuration
NODE_VERSION="${NODE_VERSION:-v22.16.0}"
NODE_DIR="$HOME/node-linux"
GLIBC_PREFIX="/data/data/com.termux/files/usr/glibc"
COPILOT_DIR="${PREFIX}/lib/node_modules/@github/copilot"

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
# MAIN INSTALLATION SCRIPT
################################################################################

print_header "GitHub Copilot CLI on Termux"

echo "This script will set up GitHub Copilot CLI on Termux using the"
echo "glibc compatibility layer (no proot required)."
echo ""
echo "What it does:"
echo "  1. Installs Node.js, glibc-repo, and glibc-runner"
echo "  2. Downloads official linux-arm64 Node.js binary"
echo "  3. Installs @github/copilot via npm"
echo "  4. Creates wrapper scripts to run Copilot through glibc"
echo "  5. Patches hardcoded /bin/bash paths for Termux"
echo ""
echo "Termux ${TERMUX_VERSION:-unknown} (aarch64)"
echo "Node.js target: $NODE_VERSION"
echo ""

if [ -t 0 ]; then
    read -p "Press Enter to continue or Ctrl+C to abort..."
fi

################################################################################
# STEP 1: Update packages and install dependencies
################################################################################

print_step "Step 1/7: Installing system dependencies"

print_info "Running pkg update..."
pkg update -y || print_warning "pkg update had issues, continuing..."

ensure_pkg nodejs node
ensure_pkg curl curl
ensure_pkg tar tar
ensure_pkg ripgrep rg

# Install glibc compatibility packages
print_info "Adding glibc repository..."
pkg install -y glibc-repo 2>/dev/null || {
  # If glibc-repo isn't available as a package, add the repo manually
  print_warning "glibc-repo package not found, adding repository manually..."
  GLIBC_LIST="$PREFIX/etc/apt/sources.list.d/glibc.list"
  mkdir -p "$PREFIX/etc/apt/sources.list.d"
  if [ ! -f "$GLIBC_LIST" ] || ! grep -q "termux-glibc" "$GLIBC_LIST" 2>/dev/null; then
    cat > "$GLIBC_LIST" << 'REPO'
# The glibc termux repository, with cloudflare cache
deb https://packages-cf.termux.dev/apt/termux-glibc/ glibc stable
REPO
    print_info "Repository added to $GLIBC_LIST"
    pkg update -y || true
  else
    print_info "glibc repository already configured"
  fi
}

print_info "Installing glibc-runner..."
if pkg install -y glibc-runner; then
    print_success "glibc-runner installed"
else
    print_error "Failed to install glibc-runner. This is required."
    echo "Try: pkg install glibc-repo && pkg install glibc-runner" >&2
    exit 1
fi

# Verify glibc dynamic linker exists
LD_SO="$GLIBC_PREFIX/lib/ld-linux-aarch64.so.1"
if [ ! -f "$LD_SO" ]; then
    print_error "glibc dynamic linker not found at $LD_SO"
    echo "Ensure glibc-runner is properly installed." >&2
    exit 1
fi
print_success "glibc dynamic linker found"

################################################################################
# STEP 2: Download linux-arm64 Node.js binary
################################################################################

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

# Verify the binary runs under glibc
if "$LD_SO" "$NODE_INSTALL_DIR/bin/node" -e "console.log('ok')" 2>/dev/null | grep -q "ok"; then
    print_success "Node.js binary works under glibc"
else
    print_error "Node.js binary failed to run under glibc dynamic linker"
    exit 1
fi

################################################################################
# STEP 3: Install @github/copilot via npm
################################################################################

print_step "Step 3/7: Installing @github/copilot globally via npm"

if npm install -g @github/copilot; then
    print_success "@github/copilot installed"
else
    print_error "Failed to install @github/copilot"
    exit 1
fi

# Verify install path
if [ ! -d "$COPILOT_DIR" ]; then
    # Try to find it
    COPILOT_DIR="$(npm root -g)/@github/copilot"
    if [ ! -d "$COPILOT_DIR" ]; then
        print_error "Cannot find Copilot install directory"
        exit 1
    fi
fi

print_info "Copilot installed at: $COPILOT_DIR"

################################################################################
# STEP 4: Create node-wrapper (fixes child_process.fork)
################################################################################

print_step "Step 4/7: Creating node-wrapper script"

# When node runs under ld.so, process.execPath points to ld-linux-aarch64.so.1
# instead of node. This breaks child_process.fork() in interactive mode.
cat > "$NODE_INSTALL_DIR/bin/node-wrapper" << EOF
#!/data/data/com.termux/files/usr/bin/bash
GLIBC_PREFIX="$GLIBC_PREFIX"
REAL_NODE="\$(dirname "\$0")/node"
LD_SO="\$GLIBC_PREFIX/lib/ld-linux-aarch64.so.1"
export PATH="\$GLIBC_PREFIX/bin:\$PATH"
unset LD_PRELOAD
exec "\$LD_SO" "\$REAL_NODE" "\$@"
EOF
chmod +x "$NODE_INSTALL_DIR/bin/node-wrapper"
print_success "node-wrapper created"

################################################################################
# STEP 5: Create preload script (fixes process.execPath)
################################################################################

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

################################################################################
# STEP 6: Create copilot launcher wrapper
################################################################################

print_step "Step 6/7: Creating copilot launcher"

# Remove any existing copilot binary/symlink from npm
rm -f "$PREFIX/bin/copilot"

cat > "$PREFIX/bin/copilot" << EOF
#!/data/data/com.termux/files/usr/bin/bash
# GitHub Copilot CLI launcher for Termux (glibc wrapper)
# Generated by copilot-termux-setup

export SSL_CERT_FILE="/data/data/com.termux/files/usr/etc/tls/cert.pem"
export SSL_CERT_DIR="/data/data/com.termux/files/usr/etc/tls/certs"
export NODE_EXTRA_CA_CERTS="/data/data/com.termux/files/usr/etc/tls/cert.pem"
export NODE_OPTIONS="--no-warnings"

GLIBC_PREFIX="$GLIBC_PREFIX"
NODE_LINUX_DIR="$NODE_INSTALL_DIR"
LINUX_NODE="\$NODE_LINUX_DIR/bin/node"
PRELOAD="\$NODE_LINUX_DIR/copilot-preload.js"
COPILOT="$COPILOT_DIR/npm-loader.js"

LD_SO="\$GLIBC_PREFIX/lib/ld-linux-aarch64.so.1"
export PATH="\$GLIBC_PREFIX/bin:\$PATH"
unset LD_PRELOAD

exec "\$LD_SO" "\$LINUX_NODE" -r "\$PRELOAD" "\$COPILOT" "\$@"
EOF
chmod +x "$PREFIX/bin/copilot"
print_success "copilot launcher created at $PREFIX/bin/copilot"

################################################################################
# STEP 7: Patch hardcoded /bin/bash paths
################################################################################

print_step "Step 7/7: Patching hardcoded shell paths for Termux"

# The CLI hardcodes /bin/bash which doesn't exist on Termux.
# Bash is at $PREFIX/bin/bash. Patch to use $SHELL with fallback.
PATCHED=0
for JS_FILE in "$COPILOT_DIR/app.js" "$COPILOT_DIR/sdk/index.js"; do
    if [ -f "$JS_FILE" ]; then
        if grep -q '"/bin/bash"' "$JS_FILE"; then
            sed -i 's|"/bin/bash"|process.env.SHELL\|\|"/bin/bash"|g' "$JS_FILE"
            print_success "Patched $(basename "$JS_FILE")"
            PATCHED=$((PATCHED+1))
        else
            print_info "$(basename "$JS_FILE") already patched or no hardcoded bash path"
        fi
    fi
done

# Also symlink ripgrep to Copilot's expected path if needed
SYSTEM_RG="$(command -v rg 2>/dev/null || true)"
if [ -n "$SYSTEM_RG" ]; then
    COPILOT_RG_DIR="$COPILOT_DIR/ripgrep/bin/linux-arm64"
    if [ ! -e "$COPILOT_RG_DIR/rg" ]; then
        mkdir -p "$COPILOT_RG_DIR"
        ln -sf "$SYSTEM_RG" "$COPILOT_RG_DIR/rg"
        print_success "Linked system rg to Copilot expected path"
    else
        print_info "Copilot ripgrep path already configured"
    fi
fi

################################################################################
# VERIFICATION
################################################################################

print_header "Verifying Installation"

# Test that copilot --version works
if COPILOT_VERSION=$(copilot --version 2>/dev/null); then
    print_success "copilot --version: $COPILOT_VERSION"
else
    print_warning "copilot --version failed (may still work in interactive mode)"
    print_info "Try running: copilot --help"
fi

################################################################################
# SUMMARY
################################################################################

print_header "Installation Complete!"

echo "Components installed:"
echo "  • Node.js $NODE_VERSION (linux-arm64) at $NODE_INSTALL_DIR"
echo "  • glibc-runner (dynamic linker at $LD_SO)"
echo "  • @github/copilot at $COPILOT_DIR"
echo "  • Launcher wrapper at $PREFIX/bin/copilot"
echo ""
echo "Files created:"
echo "  • $NODE_INSTALL_DIR/bin/node-wrapper"
echo "  • $NODE_INSTALL_DIR/copilot-preload.js"
echo "  • $PREFIX/bin/copilot"
echo ""
echo -e "${YELLOW}NOTE:${NC} After updating Copilot (npm update -g @github/copilot),"
echo "      re-run this script to recreate the wrapper and patches."
echo ""
echo "Next steps:"
echo "  1. Launch Copilot: copilot"
echo "  2. Sign in: /login"
echo "  3. Start coding with AI assistance!"
echo ""

print_success "Setup completed successfully!"

exit 0

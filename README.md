# GitHub Copilot CLI Setup for Termux (Pure Native - No PRoot)

Setup script to install **GitHub Copilot CLI** directly on **Termux** (Android/aarch64) without PRoot or containers.

## Background

GitHub Copilot CLI ships a self-contained Node.js Single Executable Application (`@github/copilot-linux-arm64/copilot`) and native Rust addons (`runtime.node`, `cli-native.node`, `copilot-runtime`) compiled against **glibc**, which is incompatible with Android's Bionic libc.

Why the upstream `glibc` strategy failed on modern Android (Android 14/15+):
1. Running `patchelf` on Node/SEA binaries corrupts ELF program headers (`PHDR`), causing `Segmentation fault` (exit 139) on Android 14+.
2. Termux's `LD_PRELOAD` (`libtermux-exec`) is compiled for Bionic and crashes glibc processes if not unset before invoking `ld-linux-aarch64.so.1`, while child processes spawned by Copilot need `/bin/bash` (`COPILOT_BASH_PATH` / `SHELL`) and `LD_PRELOAD` restored.
3. `@github/copilot` now ships as a self-extracting SEA binary in `@github/copilot-linux-arm64/copilot` (extracting to `~/.cache/copilot/pkg/linux-arm64/<version>/`), rather than plain JS files in `@github/copilot`.

This script runs `@github/copilot-linux-arm64/copilot` directly via Termux's native glibc dynamic linker (`$PREFIX/glibc/lib/ld-linux-aarch64.so.1`) without `proot` and without `patchelf`.

## Requirements

- **Termux** on an **aarch64/arm64** Android device
- Internet connection

## Installation

```bash
cd copilot-termux-setup
bash setup.sh
```

### Verify an existing install

```bash
bash setup.sh self-test
```

## Usage

```bash
copilot
```

On first launch, use `/login` to authenticate with your GitHub account.

## Updating Copilot

```bash
bash setup.sh
```

## License

MIT

# GitHub Copilot CLI Setup for Termux

This repository contains a setup script to install and configure the **GitHub Copilot CLI** on **Termux** (Android/aarch64). 

## Background

Since v1.0.48, GitHub Copilot CLI ships a Rust native addon (`runtime.node`) compiled against **glibc**, which is incompatible with Android's Bionic libc. This script works around the issue by using Termux's `glibc-runner` package to execute a standard linux-arm64 Node.js binary under the glibc dynamic linker — no proot or chroot required.

Based on the workaround from [github/copilot-cli#3333](https://github.com/github/copilot-cli/issues/3333).

## Requirements

- **Termux** on an **aarch64/arm64** Android device
- Internet connection for downloading packages

## What it does

1. Installs Node.js (Termux), `glibc-repo`, and `glibc-runner`
2. Downloads an official **linux-arm64** Node.js binary
3. Installs `@github/copilot` globally via npm
4. Creates wrapper scripts to launch Copilot through glibc's `ld-linux-aarch64.so.1`
5. Patches hardcoded `/bin/bash` paths for Termux compatibility
6. Links system `ripgrep` to Copilot's expected path

## Installation

```bash
git clone https://github.com/YOUR_USER/copilot-termux-setup.git
cd copilot-termux-setup
bash setup.sh
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `NODE_VERSION` | `v22.16.0` | linux-arm64 Node.js version to download |

Example:
```bash
NODE_VERSION=v24.14.1 ./setup.sh
```

## Usage

```bash
copilot
```

On first launch, use `/login` to authenticate with your GitHub account.

## After updating Copilot

When you run `npm update -g @github/copilot`, the wrapper at `$PREFIX/bin/copilot` gets overwritten and patches are lost. Re-run the setup script:

```bash
./setup.sh
```

## Troubleshooting

- **"glibc-runner not found"**: Run `pkg install glibc-repo` first, then `pkg install glibc-runner`
- **"Failed to start bash process"**: The `/bin/bash` patch may not have applied. Check that `app.js` uses `process.env.SHELL` instead of a hardcoded path.
- **Signal 9 / OOM kills during Thinking phase**: Android may kill the process due to memory limits. Try closing other apps or using a device with more RAM.
- **SSL/TLS errors**: Ensure Termux CA certificates are up to date: `pkg install ca-certificates`

## License

MIT

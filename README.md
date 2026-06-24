# GitHub Copilot CLI Setup for Termux

Setup script to install **GitHub Copilot CLI** on **Termux** (Android/aarch64).

## Background

Since v1.0.48, GitHub Copilot CLI ships a Rust native addon (`runtime.node`) compiled against **glibc**, incompatible with Android's Bionic libc. This script provides two strategies to work around this:

- **proot-distro** (default for Android 14+): Runs Copilot inside a Debian proot environment. Most reliable, works on all devices.
- **glibc-native** (for older Android): Uses `patchelf` to run a linux-arm64 Node.js with Termux's glibc layer. Lighter but may not work on devices with strict SELinux (Android 14+).

Based on [github/copilot-cli#3333](https://github.com/github/copilot-cli/issues/3333).

## Requirements

- **Termux** on an **aarch64/arm64** Android device
- Internet connection

## Installation

```bash
git clone https://github.com/cafeteru/copilot-termux-setup.git
cd copilot-termux-setup
bash setup.sh
```

The script auto-detects your Android version and picks the best strategy.

### Force a specific strategy

```bash
bash setup.sh proot    # Use proot-distro (recommended for Android 14+)
bash setup.sh glibc    # Use glibc-native (lighter, older devices)
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `NODE_VERSION` | `v22.16.0` | Node.js version (glibc strategy only) |
| `PROOT_DISTRO` | `debian` | Linux distro for proot strategy |

## Usage

```bash
copilot
```

On first launch, use `/login` to authenticate with your GitHub account.

## After updating Copilot

```bash
# proot strategy:
proot-distro login debian -- npm update -g @github/copilot

# glibc strategy:
npm update -g @github/copilot && bash setup.sh glibc
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Permission denied" on all binaries | Close Termux completely and reopen. If persistent, use `bash setup.sh proot` |
| "glibc-runner not found" | `pkg install glibc-repo && pkg install glibc-runner`, or use proot strategy |
| "Could not find a PHDR" | The glibc-native strategy won't work; use `bash setup.sh proot` |
| Signal 9 / OOM during Thinking | Android kills the process due to RAM limits. Close other apps |
| SSL/TLS errors | `pkg install ca-certificates` |

## License

MIT

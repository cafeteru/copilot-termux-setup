# GitHub Copilot CLI Setup for Termux

This repository contains a setup script to install and configure the **GitHub Copilot CLI** on **Termux** (Android). It automates the installation of system dependencies, builds required native modules, and sets up the environment for a smooth experience.

## Overview

The `setup.sh` script performs the following tasks:
- Installs Node.js and build tools (clang, make, python, rust).
- Installs system libraries (glib, libvips, pkg-config).
- Installs the `@github/copilot` CLI globally.
- Compiles and configures native Node.js modules:
  - **node-pty**: For pseudo-terminal support.
  - **sharp**: For image processing.
  - **keytar**: For secure credential storage.
- Sets up a clipboard wrapper using `termux-api`.
- Configures `ripgrep` for code search.

## Installation

1.  Clone this repository or download the `setup.sh` file to your Termux home directory.
2.  Make the script executable:
    ```bash
    chmod +x setup.sh
    ```
3.  Run the setup script:
    ```bash
    ./setup.sh
    ```

The script will guide you through the installation process. It may take some time to compile the native modules.

## Usage

Once the installation is complete, you can start the GitHub Copilot CLI by running:

```bash
copilot
```

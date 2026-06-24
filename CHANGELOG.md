# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

### Added
- Dual installation strategy: `proot-distro` for reliable execution on modern Android and `glibc-native` for lighter setups on older devices.
- Automatic strategy selection based on Android SDK version.
- Termux launcher at `$PREFIX/bin/copilot` that enters the proot environment automatically.
- Internal proot wrapper at `/usr/local/bin/copilot-cli` to avoid recursive launcher resolution.
- `bash setup.sh self-test` subcommand that verifies a proot install end-to-end without mutating state.
- README link to this changelog.
- Repository documentation updates covering installation, updates, and troubleshooting.

### Changed
- Reworked the installer to match the current `@github/copilot` package layout, which now ships platform-specific optional packages instead of the older Node-only flow.
- Switched the proot installation flow to force Debian's own `/usr/bin/node` and `/usr/bin/npm` instead of allowing Termux's Android Node.js binary to leak through `PATH`.
- Updated the proot launcher to call the internal wrapper by absolute path.
- Made `bash setup.sh proot` safe to rerun against an existing container.
- Updated the README to reflect the final working behavior and recovery steps.

### Fixed
- Dead or outdated glibc repository handling.
- Missing executable-bit workflow confusion by documenting `bash setup.sh` usage.
- Non-interactive apt handling inside proot.
- Missing `bash` inside the proot environment.
- Heredoc delimiter mismatch that caused the rest of the script to be parsed into the launcher block.
- Recursive `copilot` launcher loop caused by Termux paths being visible inside proot.
- Broken no-argument launcher execution caused by an unnecessary `shift`.
- False platform detection where Copilot saw `android arm64` instead of `linux arm64`.
- Missing optional platform package installation for `@github/copilot`.
- Overly broad `proot-distro install ... || true` behavior that hid real install failures.
- Hardcoded `debian` launcher value even though `PROOT_DISTRO` is configurable.

### Known Limitations
- The `glibc-native` path may still fail on newer Android releases because SELinux can block glibc loader execution.
- The proot strategy depends on network access to external package sources during setup.
- Copilot CLI behavior can still be constrained by Android memory pressure during larger sessions.

### Possible Improvements
- Add an explicit `--update` mode that refreshes Copilot and regenerates wrappers without re-running the full install flow.
- Reduce dependence on NodeSource if Debian's packaged Node.js becomes sufficient for the required Copilot version.
- Add clearer handling for package-source warnings such as the Termux glibc repository signature notice.
- Consider logging setup output to a file for easier diagnosis on-device.

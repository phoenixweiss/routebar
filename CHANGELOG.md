# Changelog

All notable user-visible changes to RouteBar are documented in this file.
English is the canonical language for release notes.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Draft release-note verification now reads the draft through GitHub CLI instead
  of the public tag endpoint, which does not expose unpublished releases.

## [0.2.4] - 2026-09-26

### Added

- A tag-driven macOS release workflow now builds and verifies an Apple silicon
  DMG and SHA-256 checksum before publishing a GitHub Release.
- Continuous integration now runs the complete project checks on development,
  release, and pull-request changes.

### Changed

- GitHub Release notes now come from the matching dated section of this changelog.
- Release preparation now updates the current-download links in both READMEs, and
  local app installation and DMG packaging share the same verified bundle builder.

## [0.2.3] - 2026-09-26

### Changed

- The RouteBar menu bar mark now uses a larger optical scale and slightly
  stronger strokes to match the visual weight of neighboring system icons.

## [0.2.2] - 2026-09-26

### Fixed

- Background reopen requests and status refreshes no longer activate RouteBar
  or move its main window over the current Space or full-screen application.

## [0.2.1] - 2026-09-26

### Fixed

- The macOS app no longer creates or restores an empty `RouteBar Settings`
  window during foreground or background launch.

## [0.2.0] - 2026-09-25

### Changed

- The macOS app icon now uses a warm light tile and a larger RouteBar mark for
  clearer recognition in the Dock and at small sizes.
- The main status window now uses the RouteBar lockup, bundled Manrope type,
  larger text, clearer information hierarchy, and a more compact native layout.
- Window buttons now match the intended control size, and the menu-bar entry uses
  a persistent native status item so it remains available alongside the Dock icon.

## [0.1.2] - 2026-09-25

### Changed

- The macOS app and menu bar now use the approved RouteBar identity instead of
  generic system symbols.

## [0.1.1] - 2026-09-25

### Fixed

- Clarified the pre-release compatibility promise for the versioned YAML schema.

## [0.1.0] - 2026-09-25

### Added

- A strict versioned YAML configuration for profiles, route groups, HTTPS checks,
  and separate connectivity-only endpoints.
- Fresh physical gateway, VPN interface, and IPv4 DNS discovery for every plan.
- Read-only route planning in the CLI and a native macOS status app with a menu
  bar summary, full window, and optional Dock presence.
- Fail-closed reconciliation of explicit `/32` routes with root-owned state.
- One-time adoption of matching routes that existed before RouteBar installation.
- A system launch daemon that reconciles routes every 30 seconds.
- Guarded installation and removal scripts for the native menu and system daemon.
- Unit coverage for configuration, network discovery, route inspection, planning,
  reconciliation, cleanup, daemon status, and live route status.

### Security

- RouteBar never changes the default route or broadens exceptions to subnets.
- Conflicting or modified static routes are left untouched and reported instead
  of being overwritten or removed.
- Runtime state, the installed helper, and the launch daemon are owned by root;
  the public repository contains only fictional network data.
- Privileged route state is restricted to a fixed root-owned path instead of a
  caller-selected location.

[Unreleased]: https://github.com/phoenixweiss/routebar/compare/v0.2.4...HEAD
[0.2.4]: https://github.com/phoenixweiss/routebar/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/phoenixweiss/routebar/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/phoenixweiss/routebar/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/phoenixweiss/routebar/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/phoenixweiss/routebar/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/phoenixweiss/routebar/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/phoenixweiss/routebar/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/phoenixweiss/routebar/releases/tag/v0.1.0

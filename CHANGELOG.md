# Changelog

All notable user-visible changes to RouteBar are documented in this file.
English is the canonical language for release notes.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-10-15

### Added

- A native rules editor creates, renames and deletes bypass groups, edits exact
  domains and profile memberships, and saves validated YAML without manual copying.
  It rejects duplicates, preserves unrelated settings and comments, follows existing
  symlinks, guards external edits and creates private backups before atomic saves.
  Saving and route application are reported separately; unsupported YAML layouts
  are refused rather than re-serialized. The experimental HAR-copy interface has
  been replaced by this editor.
  Contextual save/create actions include pending domain input and protect drafts
  when closing, switching groups or recovering from external file changes.

### Changed

- Route group headers now expand into one destination per line, replacing the
  collapsed summary without repeating it. Routing warnings remain visible.
- Both windows use consistent, readable button states in light and dark mode.

## [0.4.1] - 2026-10-10

### Fixed

- The local TLS test fixture now imports temporary identities into process memory
  using macOS 15-compatible APIs, keeping CI certificates out of the Keychain.
- DNS failures are isolated per bypass domain, with unresolved names shown in the
  window and read-only plan; healthy routes continue to reconcile without reusing stale IPs.
- Connectivity checks refresh their kernel-routed source address after DHCP or
  network changes, and HTTPS checks use bounded, verified TLS/HTTP transport.

### Added

- The first published DMG for the 0.4 series includes the manual Connectivity
  section and read-only TCP, TLS, SMTP STARTTLS and HTTPS development commands.
  Checks do not authenticate, change routes or activate windows in the background.
- Transport endpoints and HTTPS checks support individual bounded timeouts;
  check-only groups support HTTPS checks, transport endpoints or both.

## [0.4.0] - 2026-10-10

Source tag only: the macOS 15 test fixture failed before DMG publication.
These application changes are included in the 0.4.1 public release.

### Fixed

- A DNS failure for one bypass domain no longer blocks reconciliation of healthy
  domains and fixed addresses. Unresolved domains are shown in the route group
  and read-only plan; obsolete owned routes are removed rather than reusing stale IPs.
- Connectivity checks select a fresh kernel-routed source address for every
  connection instead of reusing stale macOS path addresses after a DHCP or network
  change. DNS, source selection, TLS and protocol work share one deadline.
- HTTPS checks use the same source-aware verified TLS transport, with bounded
  HTTP/1.1 HEAD response headers, instead of a URLSession path that can retain an
  obsolete local address. Malformed HTTP replies are reported separately.

### Added

- A manual Connectivity section reports each configured TCP, TLS, SMTP STARTTLS
  and HTTPS check separately from route status, without blocking the interface,
  changing routes, activating windows or running checks on a timer. Results are
  marked out of date after detected network, profile or check configuration changes.
- A read-only `check-tcp` development command reports TCP connectivity for each
  check-only endpoint without changing routes or sending application data. This
  command checks TCP transport only, not TLS or STARTTLS handshakes.
- Endpoint configuration supports plain `tcp` and optional `timeout_seconds`
  (0.1–30 seconds, default 5), covering DNS and connection establishment.
- A read-only `check-tls` development command validates implicit TLS handshakes,
  certificate trust and server hostname with one endpoint deadline, without
  authentication or application data. Certificate and handshake failures are
  reported separately; STARTTLS endpoints are not checked by this command.
- A read-only `check-starttls` development command checks SMTP greeting, EHLO,
  advertised STARTTLS and the verified TLS upgrade on the same connection with
  one deadline. Missing support, rejected upgrades and malformed replies are
  distinct failures. No authentication, mail or plaintext fallback is performed.
- A read-only `check-https` development command checks expected HTTP statuses
  with HEAD, verified TLS and a single deadline. It does not follow redirects,
  reuse cookies, authenticate, collect response bodies or change routes.
- Check-only groups can contain HTTPS `checks`, transport endpoints or both.
  HTTPS checks support optional `timeout_seconds` (default 5). Existing bypass
  group checks remain supported; URLs with credentials or fragments are rejected.

## [0.3.1] - 2026-10-01

### Added

- A public brand kit now keeps the RouteBar mark, outlined lockup, macOS app
  icon sources, menu bar symbol, palette, and English and Russian usage notes in
  one documented location.

### Changed

- The READMEs and macOS icon build now use the canonical assets from
  `docs/brand`, with generated PNG and ICNS derivatives checked for drift; the
  obsolete pre-0.3.0 development notice has also been removed. CI and release
  runners install the required SVG renderer before running those checks.

### Fixed

- RouteBar now replaces its `/32` routes when the physical interface receives a
  different local IPv4 address, even if the new network uses the same gateway
  address and interface name, preventing stale routes after changing Wi-Fi.

## [0.3.0] - 2026-09-27

### Added

- The app can register, configure, explicitly apply, reconcile, and safely
  disable its bundled routing daemon without requiring a source checkout.
- Launch at login now uses an app-bundled `SMAppService` LaunchAgent and a fixed
  background launcher instead of installing a plist in the user's Library.
- Updating from the legacy app preserves an enabled launch-at-login setting by
  migrating it to the bundled login item.
- The main window can reload YAML and reconcile routes immediately, with a clear
  applied or rejected result instead of waiting for the next 30-second cycle.
- Automatic routing now reports its last reconciliation result and error, and
  warns when an edited YAML revision has not yet been confirmed by the daemon.
- A compact Diagnostics sheet shows safe runtime state and copies a redacted
  issue report without domains, network addresses, SSIDs, paths, or YAML data.

### Changed

- Local development installs can now restart RouteBar in the background without
  opening its status window over the current Space.
- Route application, automatic reconciliation, cleanup, and daemon removal are
  serialized and fail closed on conflicts or overlapping operations.
- A bundled service version mismatch can be repaired from the app by restarting
  the registered helper while preserving the YAML, selected profile, active
  routes, and RouteBar-owned state.
- The English and Russian READMEs now use the RouteBar mark and describe the
  current app, shipped release, development service flow, and real limitations.

### Fixed

- Window presentation now follows an explicit launch and user-action policy,
  with regression coverage preventing background events from surfacing the app.
- A healthy legacy daemon now appears as normal active automation instead of a
  warning or required migration; the unavailable built-in service remains
  visible as a neutral secondary status.
- The main window keeps a stable layout while the launch-at-login switch is
  updating instead of briefly shifting the surrounding controls.

## [0.2.6] - 2026-09-26

### Fixed

- Draft release-note comparison now ignores the extra trailing newline emitted
  by GitHub CLI while still requiring the complete published body to match.

## [0.2.5] - 2026-09-26

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

[Unreleased]: https://github.com/phoenixweiss/routebar/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/phoenixweiss/routebar/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/phoenixweiss/routebar/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/phoenixweiss/routebar/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/phoenixweiss/routebar/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/phoenixweiss/routebar/compare/v0.2.6...v0.3.0
[0.2.6]: https://github.com/phoenixweiss/routebar/compare/v0.2.5...v0.2.6
[0.2.5]: https://github.com/phoenixweiss/routebar/compare/v0.2.4...v0.2.5
[0.2.4]: https://github.com/phoenixweiss/routebar/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/phoenixweiss/routebar/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/phoenixweiss/routebar/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/phoenixweiss/routebar/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/phoenixweiss/routebar/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/phoenixweiss/routebar/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/phoenixweiss/routebar/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/phoenixweiss/routebar/releases/tag/v0.1.0

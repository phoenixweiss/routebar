# Changelog

All notable user-visible changes to RouteBar are documented in this file.
English is the canonical language for release notes.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

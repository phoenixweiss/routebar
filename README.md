# RouteBar

<p align="center"><img src="Support/RouteBarAppIcon.svg" alt="RouteBar" width="144"></p>

<p align="center"><strong>Keep selected destinations outside the VPN.</strong></p>

<p align="center">
  <a href="https://github.com/phoenixweiss/routebar/actions/workflows/ci.yml"><img src="https://github.com/phoenixweiss/routebar/actions/workflows/ci.yml/badge.svg?branch=dev" alt="CI"></a>
  <a href="https://github.com/phoenixweiss/routebar/releases/latest"><img src="https://img.shields.io/github/v/release/phoenixweiss/routebar?display_name=tag&sort=semver" alt="Latest release"></a>
</p>

<p align="center"><a href="README_RU.md">Русская версия</a></p>

RouteBar is a native macOS menu bar utility that keeps small, explicit groups of
IPv4 destinations outside an active VPN. It resolves configured domains and
maintains only `/32` host routes through the current physical gateway. It does
not replace the VPN client or change the default route.

The app provides a menu bar summary, a regular status window, an optional Dock
icon, launch at login, YAML validation, profile selection, route status, and
explicit controls for automatic routing.

## Download

The latest public release is
[RouteBar 0.2.6](https://github.com/phoenixweiss/routebar/releases/tag/v0.2.6)
for Apple silicon Macs running macOS 13 or later. Download the DMG, open it, and
copy RouteBar to Applications. The release includes a SHA-256 checksum.

The app is ad-hoc signed, but it is not yet Developer ID signed or notarized.
On first launch, Control-click RouteBar, choose **Open**, and confirm the launch.

> **Development status:** the `dev` branch contains the new app-bundled routing
> service and its complete in-app setup, update, reload, and removal flow. This
> flow is covered by automated app-bundle and operation tests, but it has not yet
> shipped in a notarized DMG or completed clean-Mac installation verification.
> Release 0.2.6 still uses the source installer for automatic routing.

## What RouteBar does

- reads strict, versioned YAML from `~/.config/routebar/config.yaml`;
- supports a regular file or a symbolic link managed by a tool such as
  [Yonder](https://github.com/phoenixweiss/yonder);
- groups domains and optional fixed IPv4 addresses into named routing rules;
- resolves every domain again before building a route plan;
- discovers the current physical interface and gateway instead of storing them;
- previews and applies only explicit `/32` host routes;
- reconciles RouteBar-owned routes every 30 seconds after network, DNS, wake, or
  VPN changes;
- reloads edited YAML immediately with a visible applied or rejected result;
- reports the last reconciliation result and warns while an edited YAML revision
  is still waiting for daemon confirmation;
- updates or disables the bundled service without deleting the YAML;
- removes only routes still matching RouteBar's own root-owned state.

## How automatic routing works

1. Put a valid configuration at `~/.config/routebar/config.yaml`.
2. Open RouteBar, choose a profile, and review the read-only route plan.
3. Choose **Enable Automatic Routing** to register the built-in service. This
   step does not change routes.
4. Choose **Apply Routes** to perform the first explicit reconciliation and
   start the 30-second cycle.
5. After editing YAML, choose **Reload Config** to validate and reconcile it
   immediately.
6. Choose **Disable Automatic Routing…** to stop reconciliation, remove only
   RouteBar-owned routes, and disable the service.

RouteBar stops on invalid YAML, an unknown profile, an ambiguous physical
gateway, or an unowned conflicting route. The selected profile and route
ownership state are stored under the fixed root-owned `/var/db/routebar`
directory. The privileged service accepts typed operations only; it does not
execute arbitrary shell commands or accept arbitrary configuration paths.

## Configuration

The configuration remains an ordinary user-owned file:

```text
~/.config/routebar/config.yaml
```

See [the fictional example](examples/routebar.yaml) for the complete schema.
Schema version 1 supports two group modes:

- `bypass-vpn` — domains and optional fixed IPv4 addresses that produce `/32`
  routes;
- `check-only` — connectivity endpoints that never produce routes.

The current route engine is IPv4-only. A records are refreshed and deduplicated;
AAAA records are ignored. HTTPS, TCP, TLS, and STARTTLS checks are represented by
the schema but are not executed by the app yet.

Profiles currently require an explicit selection for the bundled service.
Automatic switching by Wi-Fi name remains disabled until SSID access and unknown
network behavior can be verified without weakening the fail-closed model.

## Safety boundary

RouteBar never broadens an exception to a subnet and never changes the default
route. Before every reconciliation it rediscovers the physical gateway, resolves
DNS, and compares the desired plan with routes previously recorded as its own.

An existing route can be adopted only when it exactly matches the current
physical gateway. Cleanup removes a route only while it still matches the
root-owned RouteBar state. Route application, configuration, cleanup, update,
and removal are serialized so overlapping operations fail closed.

## Development

Requirements:

- macOS 13 or newer;
- Swift 6.

Run the complete quality suite and inspect the fictional example plan:

```bash
script/check
swift run routebar plan --config examples/routebar.yaml --profile home
```

Build and install the current app for the signed-in user:

```bash
script/install-app
```

Build an app bundle or local release DMG without installing it:

```bash
script/build-app /tmp/RouteBar.app
script/package-release
```

The source tree retains the legacy daemon installer for migration and release
0.2.6 compatibility:

```bash
script/install-daemon home "$HOME/.config/routebar/config.yaml"
script/uninstall-daemon
```

Remove the app and its launch-at-login registration with:

```bash
script/uninstall-app
```

Uninstalling the app does not silently remove a running routing service or its
routes. Disable automatic routing in the app first when those should be removed.

## Versioning and releases

RouteBar follows Semantic Versioning. `VERSION` is the canonical version source,
and user-visible changes accumulate under `Unreleased` in
[CHANGELOG.md](CHANGELOG.md).

[Bumpster](https://github.com/phoenixweiss/bumpster) manages releases from `dev`
to `main`. A version bump runs `script/check`, closes the changelog section,
updates both README release links, updates `VERSION`, and publishes the matching
tag. The tag-driven workflow builds and verifies the Apple silicon DMG and
SHA-256 checksum, uses the matching changelog section as release notes, verifies
the draft assets, and only then publishes the GitHub Release.

## License

[MIT](LICENSE) © 2026 PAVEL TKACHEV

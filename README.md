# RouteBar

<p align="center"><strong>Keep selected destinations outside the VPN.</strong></p>

<p align="center"><a href="README_RU.md">Русская версия</a></p>

RouteBar is an early macOS utility for managing small, explicit groups
of destinations that should use the current physical network gateway instead of
the active VPN route.

The project combines a human-readable YAML configuration, an automatic
root-owned reconciliation process, and a native status app available from both
the menu bar and a regular window. RouteBar is not a VPN client and does not
replace or reconfigure the system default route.

## Download

The current release is
[RouteBar 0.2.6](https://github.com/phoenixweiss/routebar/releases/tag/v0.2.6) for
Apple silicon Macs running macOS 13 or later. Download the DMG, open it, and copy
RouteBar to Applications.

The app bundle is ad-hoc signed for integrity, but it is not yet Developer ID
signed or notarized. macOS therefore requires explicit approval on first launch:
Control-click RouteBar, choose **Open**, and confirm the launch. The published
SHA-256 checksum is included in `SHA256SUMS.txt`.

The DMG installs the native status app. The root-owned reconciliation daemon still
requires the source installer described under [Automatic reconciliation](#automatic-reconciliation),
because its installation must name an explicit profile and configuration path.

## Roadmap

The current development build already:

- group domains and optional fixed IP addresses under named rules;
- resolve every configured domain to its current IPv4 addresses;
- discover the active physical interface and gateway after every network change;
- install only explicit host routes and track only routes created by RouteBar;
- reconcile routes every 30 seconds after gateway, DNS, wake, or VPN changes;
- keep mail transport definitions separate from route-bypass rules;
- show current network, route, and automation state in a native menu and window.

Focused TCP, TLS, STARTTLS, and HTTP health checks remain on the roadmap.

## Configuration

The proposed default configuration path is:

```text
~/.config/routebar/config.yaml
```

The file remains ordinary user-owned YAML. It may be a symbolic link, so the
source can live in a folder synchronized by an external cloud client. A tool such
as [Yonder](https://github.com/phoenixweiss/yonder) can keep the source in that
storage and expose it at the expected local path.

See [the example configuration](examples/routebar.yaml) for the current shape.
The schema remains pre-release throughout the 0.x series and may change between
minor versions.

Schema version 1 is IPv4-only: every current A record is refreshed and
deduplicated for each plan, fixed addresses must be IPv4, and AAAA records are
intentionally ignored.

## Safety boundary

RouteBar must never broaden an exception to a provider subnet or change the
default route for convenience. Before applying a change, it should rediscover the
current physical gateway, resolve DNS again, and compare the desired routes with
the routes it previously created.

The native app runs without elevated privileges and does not change routes. A
separate root-owned executable exposes only narrow operations for planning,
applying, adopting, removing, and inspecting RouteBar-owned host routes. It
accepts a configuration path and a profile identifier, not arbitrary shell
commands. Privileged state always uses the fixed root-owned path
`/var/db/routebar/state.json`.

## Current development build

The current build provides:

- strict versioned YAML decoding and semantic validation;
- physical IPv4 gateway discovery that ignores VPN and bridge defaults;
- fresh IPv4 DNS resolution and a `/32` host-route preview;
- fail-closed reconciliation of RouteBar-owned routes;
- safe one-time adoption of matching routes created manually before installation;
- a root-owned launch daemon that reconciles every 30 seconds;
- cleanup that removes only routes still matching RouteBar's state;
- a native menu bar summary and a full status window for the network, route groups,
  and daemon;
- separate display of mail and other connectivity-only checks.

HTTPS and mail endpoint checks are represented in the configuration but are not
executed automatically yet. The launch daemon also uses one explicitly selected
profile; automatic SSID-based switching remains on the roadmap because a system
daemon may not have access to the Wi-Fi name.

## Development

English is the canonical project language. User-facing Russian documentation is
maintained alongside it. User-visible changes are recorded in the
[changelog](CHANGELOG.md).

Requirements for the development build:

- macOS 13 or newer;
- a Swift 6 toolchain.

Run the checks and inspect the example plan:

```bash
script/check
swift run routebar plan --config examples/routebar.yaml --profile home
```

The `--profile` override selects a known configuration profile explicitly. Without
it, automatic profile selection uses an exact SSID match and fails closed if the
SSID is unavailable or ambiguous.

Build, install, and open the native app for the current user:

```bash
script/install-app
```

Build the same app bundle or release DMG without installing it:

```bash
script/build-app /tmp/RouteBar.app
script/package-release
```

The app is installed at `~/Applications/RouteBar.app` and starts automatically
at login in the menu bar. Choose **Open Window** in the menu or launch RouteBar
from Spotlight or Finder to open the full status window. **Show in Dock** keeps a
Dock icon available when the menu bar is crowded. The app reads the configuration
path and selected profile from the installed system daemon, falling back to
`~/.config/routebar/config.yaml` when the daemon is not installed.

Remove only the app and its user LaunchAgent with:

```bash
script/uninstall-app
```

This does not stop the system daemon or remove any routes.

## Automatic reconciliation

Review the read-only plan before installation:

```bash
swift run routebar plan --profile home
```

Install the optimized local build and its system launch daemon with a profile ID
and an optional absolute configuration path:

```bash
script/install-daemon home "$HOME/.config/routebar/config.yaml"
```

The installer validates the configuration and plan before requesting elevated
privileges. It then records already-present routes only when they exactly match
the current physical gateway, performs one reconciliation, and starts the
30-second system job. Runtime state is root-owned at
`/var/db/routebar/state.json`.

Remove the daemon, its state, and only routes that still match that state:

```bash
script/uninstall-daemon
```

Both scripts fail closed if an existing launch daemon or route does not match the
expected RouteBar ownership data.

## Versioning and releases

RouteBar follows Semantic Versioning. `VERSION` is the canonical version source,
and release notes accumulate under `Unreleased` in `CHANGELOG.md`.

The project uses [Bumpster](https://github.com/phoenixweiss/bumpster) with `dev`
as the development branch and `main` as the release branch. A Bumpster release
runs `script/check`, moves the pending changelog entries into a dated release,
updates the current-release links in both READMEs, updates `VERSION`, and atomically
publishes both branches and the `vX.Y.Z` tag.

The tag starts the macOS release workflow. It checks the exact tagged source,
builds and verifies an Apple silicon DMG, publishes its SHA-256 checksum, and uses
the matching version section from `CHANGELOG.md` as the GitHub Release notes. The
workflow first uploads a draft, verifies the published asset digests and notes,
and only then makes the GitHub Release public. Local packaging never publishes a
release.

## License

[MIT](LICENSE) © 2026 PAVEL TKACHEV

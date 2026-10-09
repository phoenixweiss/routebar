# RouteBar

<p align="center"><img src="docs/brand/routebar-lockup.svg" alt="RouteBar" width="420"></p>

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
[RouteBar 0.4.0](https://github.com/phoenixweiss/routebar/releases/tag/v0.4.0)
for Apple silicon Macs running macOS 13 or later. Download the DMG, open it, and
copy RouteBar to Applications. The release includes a SHA-256 checksum.

The app is ad-hoc signed, but it is not yet Developer ID signed or notarized.
On first launch, Control-click RouteBar, choose **Open**, and confirm the launch.

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
- provides a compact Diagnostics sheet and a redacted report for issues without
  domains, network addresses, SSIDs, paths, or YAML contents;
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
- `check-only` — transport endpoints and/or HTTPS `checks` that never produce routes.

The current route engine is IPv4-only. A records are refreshed and deduplicated;
AAAA records are ignored. The app's **Connectivity** section runs configured checks
only when you click **Check**. Each endpoint has its own TCP, TLS, SMTP STARTTLS or
HTTPS result, separate from host-route status. Checks use current system routes,
never apply routing rules, authenticate or run on a timer. Results are manual
snapshots; changes to the detected network, profile or check configuration mark
them out of date. HTTPS rows show the host only, not URL paths or query strings.
Before each connection, RouteBar resolves the destination and asks the kernel for
the source address selected by current routing. It binds that address for this
check only, avoiding stale macOS path addresses after DHCP or network changes.
No interface or gateway is pinned; IPv4 is preferred when available so `/32`
exceptions remain effective. The selected address is not saved between checks.
The development CLI can check TCP transport for every `check-only` endpoint:

```sh
swift run routebar check-tcp --config ~/.config/routebar/config.yaml --profile home
```

This opens and closes connections using the current system routing, without
changing routes, authenticating or sending application data. Each endpoint gets
a separate result: reachable, DNS failure, refused, unreachable, timeout or failed.
Exit code `5` means at least one endpoint was not reachable. With a single profile,
`--profile` can be omitted. Endpoints accept `protocol: tcp` and an optional
`timeout_seconds` (0.1–30, default 5); the deadline includes DNS resolution.
For `tls` and `starttls-smtp` endpoints this command checks **TCP only**, not
certificates or protocol handshakes.

To check implicit TLS endpoints (`protocol: tls`):

```sh
swift run routebar check-tls --config ~/.config/routebar/config.yaml --profile home
```

This performs a TLS 1.2-or-newer handshake with macOS certificate trust and
hostname validation, without authenticating or sending application data. The
same endpoint deadline covers DNS, connection and handshake. Certificate failures
are reported separately from TLS handshake errors and transport failures; exit
code `5` means at least one check failed. Only implicit TLS endpoints are checked:
plain TCP and STARTTLS endpoints are skipped. There is no insecure certificate
bypass. Trust evaluation does not fetch missing certificates or revocation data
over the network, so this is not a full online revocation audit.

For SMTP STARTTLS endpoints (`protocol: starttls-smtp`):

```sh
swift run routebar check-starttls --config ~/.config/routebar/config.yaml --profile home
```

This checks the SMTP greeting, EHLO capabilities and STARTTLS response, then
upgrades the same connection to verified TLS 1.2 or newer. Only
`EHLO routebar.invalid` and `STARTTLS` are sent; there is no AUTH, mail or plaintext
fallback. One endpoint deadline covers the entire check. Missing STARTTLS,
rejected upgrades and malformed SMTP replies have separate results, alongside
the TLS and transport errors above. Replies are size-limited and are not logged
or saved. Exit code `5` means at least one check failed. Other endpoint protocols
are skipped. The same certificate-validation limitations as `check-tls` apply.

To check HTTPS URLs from `checks` in either group mode:

```sh
swift run routebar check-https --config ~/.config/routebar/config.yaml --profile home
```

This sends **HEAD**, checks the initial HTTP status against `expected_statuses`
and stops at response headers without collecting the body. It uses verified system
TLS with an HTTP/1.1 request and bounded headers (16 KiB), not a browser session.
Informational responses are skipped; malformed headers have their own error.
It uses current system routing: it does not create routes or apply a bypass
group's route plan. Redirects
are not followed (an expected `302` is reported as `302`), cookies and credentials
are disabled, and URLs with embedded credentials or fragments are rejected.
There is no GET fallback if HEAD is unsupported. Each check accepts optional
`timeout_seconds` (0.1–30, default 5) for the whole request. Certificate, TLS, DNS,
connection, timeout and unexpected-status results are separate; the HTTP status
is included where available. Exit code `5` means at least one check failed.
Certificate validation has the same offline limitations as `check-tls`.
The fictional example includes a HTTPS-only `check-only` group.
The app selects the configured transport for each endpoint; unlike `check-tcp`,
it performs TLS or SMTP STARTTLS when that is the endpoint's protocol.

Profiles currently require an explicit selection for the bundled service.
Automatic switching by Wi-Fi name remains disabled until SSID access and unknown
network behavior can be verified without weakening the fail-closed model.

## Safety boundary

RouteBar never broadens an exception to a subnet and never changes the default
route. Before every reconciliation it rediscovers the physical gateway, resolves
DNS, and compares the desired plan with routes previously recorded as its own.

Domain entries are exact hostnames: a root domain does not include its subdomains
or a separate CDN hostname. A DNS failure skips only that hostname; other resolved
domains and fixed addresses continue to reconcile. The window and read-only plan
show unresolved domains. Previously owned IPs that are no longer desired are
removed through the normal ownership checks, not reused as DNS fallback. Resolution
is retried on the next reconciliation; no alternate DNS server is queried automatically.

An existing route can be adopted only when it exactly matches the current
physical gateway. Cleanup removes a route only while it still matches the
root-owned RouteBar state. Route application, configuration, cleanup, update,
and removal are serialized so overlapping operations fail closed.

## Development

Requirements:

- macOS 13 or newer;
- Swift 6;
- `librsvg` for regenerating and checking committed brand derivatives
  (`brew install librsvg`).

Run the complete quality suite and inspect the fictional example plan:

```bash
script/check
swift run routebar plan --config examples/routebar.yaml --profile home
```

Build and install the current app for the signed-in user:

```bash
script/install-app
```

Use `script/install-app --background` to replace and restart the app without
opening its status window or interrupting another Space.

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

## Brand assets

The public RouteBar mark, lockup, app icon sources, and usage notes live in
[docs/brand](docs/brand/README.md). Generated PNG and macOS ICNS derivatives are
kept with their SVG masters and checked for drift by the normal quality suite.

## License

[MIT](LICENSE) © 2026 PAVEL TKACHEV

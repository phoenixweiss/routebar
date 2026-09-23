# RouteBar

<p align="center"><strong>Keep selected destinations outside the VPN.</strong></p>

<p align="center"><a href="README_RU.md">Русская версия</a></p>

RouteBar is a planned macOS menu bar utility for managing small, explicit groups
of destinations that should use the current physical network gateway instead of
the active VPN route.

The project is designed around a SwiftBar interface, a human-readable YAML
configuration, and a narrowly scoped privileged helper. RouteBar is not a VPN
client and does not replace or reconfigure the system default route.

## Direction

The initial implementation is expected to:

- group domains and optional fixed IP addresses under named rules;
- resolve every configured domain to its current IPv4 addresses;
- discover the active physical interface and gateway after every network change;
- install only explicit host routes and track only routes created by RouteBar;
- reconcile routes after Wi-Fi, gateway, wake, or VPN changes;
- verify routes with focused TCP, TLS, and HTTP checks;
- keep mail transport checks separate from route-bypass rules;
- show the current network, gateway, VPN, groups, and health in SwiftBar.

## Configuration

The proposed default configuration path is:

```text
~/.config/routebar/config.yaml
```

The file remains ordinary user-owned YAML. It may be a symbolic link, so the
source can live in a folder synchronized by an external cloud client. A tool such
as [Yonder](https://github.com/phoenixweiss/yonder) can keep the source in that
storage and expose it at the expected local path.

See [the example configuration](examples/routebar.yaml) for the current proposed
shape. The schema is not stable until the first working release.

## Safety boundary

RouteBar must never broaden an exception to a provider subnet or change the
default route for convenience. Before applying a change, it should rediscover the
current physical gateway, resolve DNS again, and compare the desired routes with
the routes it previously created.

The SwiftBar plugin runs without elevated privileges. A separate root-owned helper
will expose only narrow operations for planning, applying, removing, and inspecting
RouteBar-owned host routes. It must not accept arbitrary shell commands.

## Project status

RouteBar is at the public project-foundation stage. There is no installable build
yet. Architecture, configuration validation, privilege boundaries, and a read-only
route plan come before automatic route changes.

## Development

English is the canonical project language. User-facing Russian documentation will
be maintained alongside it. Dependencies and release tooling will be introduced
only when the implementation requires them.

## License

[MIT](LICENSE) © 2026 PAVEL TKACHEV

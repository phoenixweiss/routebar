# RouteBar brand assets

RouteBar represents a small set of explicit routes passing through a routing
boundary and changing lanes. The identity deliberately avoids shields, locks,
globes, and generic VPN imagery: RouteBar controls narrow host routes; it is not
a VPN or a security product.

## Core assets

| Asset | Use |
| --- | --- |
| `routebar-lockup.svg` | Primary mark and outlined wordmark for repository and editorial use |
| `routebar-mark.svg` | Standalone full-color mark on transparent surfaces |
| `routebar-app-icon.svg` | Canonical macOS app icon source |
| `routebar-app-icon-small.svg` | Optical small-size source for the 16 and 32 pixel ICNS slots |
| `routebar-menu-bar-symbol.svg` | Monochrome reference for the macOS menu bar symbol |
| `macos/RouteBar.icns` | Generated macOS application icon |

PNG companions are included for tools that cannot consume SVG. The lockup uses
an outlined Manrope Semibold wordmark and has no runtime font dependency. The
SVG mark and lockup adapt the deep-teal ink to dark color schemes; their PNG
companions are the light-surface versions.

## Palette

| Role | Hex |
| --- | --- |
| Deep teal ink | `#173F4C` |
| Route green | `#79C943` |
| Route blue | `#2F6BFF` |
| Route coral | `#FF704D` |
| Warm app tile | `#F6F5F1` |
| Dark-surface ink | `#D7E6E9` |

## Usage

- Prefer the lockup when the name must be immediately clear.
- Use the standalone mark only where RouteBar is already identified nearby.
- Use the supplied app icon as a complete asset; do not place the transparent
  mark directly into the macOS icon mask.
- Use the monochrome menu bar symbol as a template image so macOS controls its
  final color. Do not shrink the full-color mark into the menu bar.
- Preserve the route geometry, round caps, relative stroke weights, and palette.
  Do not recolor individual routes or add security-product motifs.

Run `script/build-brand-assets` after changing an SVG master. The normal project
check verifies that committed PNG and ICNS derivatives still match those
masters. See [the Russian guide](README_RU.md) for the localized version.

#!/bin/zsh

# <xbar.title>RouteBar</xbar.title>
# <xbar.version>v0.0.0-dev</xbar.version>
# <xbar.author>Pavel Tkachev</xbar.author>
# <xbar.author.github>phoenixweiss</xbar.author.github>
# <xbar.desc>Read-only preview of explicit host routes outside the VPN.</xbar.desc>
# <xbar.dependencies>routebar</xbar.dependencies>
# <xbar.abouturl>https://github.com/phoenixweiss/routebar</xbar.abouturl>
# <swiftbar.refreshOnOpen>true</swiftbar.refreshOnOpen>
# <swiftbar.environment>[ROUTEBAR_BIN=~/.local/bin/routebar, ROUTEBAR_CONFIG=~/.config/routebar/config.yaml, ROUTEBAR_PROFILE=]</swiftbar.environment>

set -u

routebar_bin="${ROUTEBAR_BIN:-${HOME}/.local/bin/routebar}"
routebar_config="${ROUTEBAR_CONFIG:-${HOME}/.config/routebar/config.yaml}"
routebar_profile="${ROUTEBAR_PROFILE:-}"

routebar_bin="${routebar_bin/#\~/${HOME}}"
routebar_config="${routebar_config/#\~/${HOME}}"

if [[ ! -x "${routebar_bin}" ]]; then
  print 'RouteBar ! | sfimage=exclamationmark.triangle'
  print -- '---'
  print 'RouteBar executable was not found | length=100'
  print "Expected: ${routebar_bin} | font=Menlo size=11"
  exit 0
fi

if [[ -n "${routebar_profile}" ]]; then
  exec "${routebar_bin}" swiftbar --config "${routebar_config}" --profile "${routebar_profile}"
else
  exec "${routebar_bin}" swiftbar --config "${routebar_config}"
fi

#!/usr/bin/env bash
# Run the fork's Linux CLI and module in the official KYBER server image.
# The official image supplies Wine/Maxima runtime files, not our LAN binaries.
set -euo pipefail

bundle_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
game_path=/mnt/battlefront/starwarsbattlefrontii.exe

if [[ -z "${MAXIMA_CREDENTIALS:-}" ]]; then
  echo 'MAXIMA_CREDENTIALS is required for EA login.' >&2
  exit 2
fi
case "${KYBER_LAN:-1}" in
  1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn]) ;;
  *) echo 'This launcher is LAN-only; set KYBER_LAN=1.' >&2; exit 2 ;;
esac
if [[ ! -f "$game_path" ]]; then
  echo "Game executable not found: $game_path" >&2
  exit 2
fi
for file in kyber_cli librust_lib.so maxima-bootstrap wine-helper.exe; do
  if [[ ! -f "$bundle_dir/$file" ]]; then
    echo "Missing fork CLI file: $bundle_dir/$file" >&2
    exit 2
  fi
done
for file in Kyber.dll vivoxsdk.dll ca_root.pem VanillaBundleAggregation.kb; do
  if [[ ! -f "$bundle_dir/lan-module/$file" ]]; then
    echo "Missing fork module file: $bundle_dir/lan-module/$file" >&2
    exit 2
  fi
done

wine_command=${MAXIMA_WINE_COMMAND:-/home/kyber/wine/bin/wine64}
if [[ ! -x "$wine_command" ]]; then
  echo "The official image's Wine runtime was not found: $wine_command" >&2
  exit 2
fi

export KYBER_LAN_ONLY=1
export KYBER_BYPASS_DOCKER_I_REALLY_KNOW_WHAT_I_AM_DOING=1
export WINEPREFIX=${WINEPREFIX:-/root/.local/share/maxima/wine/prefix}
cp "$bundle_dir/lan-module/vivoxsdk.dll" /mnt/battlefront/
# Initialize without interactive Mono/HTML installers or desktop integration.
WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}mscoree,mshtml,winemenubuilder.exe=" \
  "$wine_command" wineboot --init

args=("$bundle_dir/kyber_cli" --skip-updates)
if [[ "${MAXIMA_LOG_LEVEL:-}" == debug ]]; then
  args+=(--debug)
fi
args+=(
  start_server --lan --show-console
  --credentials="$MAXIMA_CREDENTIALS"
  --server-name="${KYBER_SERVER_NAME:-LAN Server}"
  --game-path "$game_path"
  --module-path "$bundle_dir/lan-module"
)
args+=("$@")
exec "${args[@]}"

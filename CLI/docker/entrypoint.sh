#!/bin/bash
set -euo pipefail

export KYBER_BYPASS_DOCKER_I_REALLY_KNOW_WHAT_I_AM_DOING=1
case "${KYBER_LAN:-}" in
  1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn]) export KYBER_LAN_ONLY=1 ;;
esac
for arg in "$@"; do
  if [[ "$arg" == "--lan" ]]; then
    export KYBER_LAN_ONLY=1
  fi
done
echo "Starting KYBER Server named '${KYBER_SERVER_NAME:-unnamed}'"

if [[ -z "${MAXIMA_CREDENTIALS:-}" ]]; then
  echo 'MAXIMA_CREDENTIALS is required for unattended EA login.' >&2
  exit 2
fi
if [[ "${KYBER_LAN_ONLY:-0}" != "1" && -z "${KYBER_TOKEN:-}" ]]; then
  echo 'KYBER_TOKEN is required for a public Kyber server; set KYBER_LAN=1 for LAN-only.' >&2
  exit 2
fi

cp /root/.local/share/kyber/module/vivoxsdk.dll /mnt/battlefront
WINEPREFIX=/root/.local/share/maxima/wine/prefix \
  WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}mscoree,mshtml,winemenubuilder.exe=" \
  /home/kyber/wine/bin/wine64 wineboot --init

args=(
  ./kyber_cli --skip-updates
)

if [[ "${MAXIMA_LOG_LEVEL:-}" == "debug" ]]; then
  args+=(--debug)
fi

args+=(
  start_server
  --show-console
  --credentials="${MAXIMA_CREDENTIALS}"
  --game-path /mnt/battlefront/starwarsbattlefrontii.exe
  --module-path /root/.local/share/kyber/module
)

if [[ "${KYBER_LAN_ONLY:-0}" == "1" ]]; then
  args+=(--lan)
else
  args+=(--token "${KYBER_TOKEN}")
fi

args+=("$@")

exec "${args[@]}"

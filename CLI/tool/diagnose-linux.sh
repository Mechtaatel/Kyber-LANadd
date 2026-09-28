#!/bin/sh
# Run with the same user/environment as the service. Does not launch the game.
set -eu
package_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
printf 'System: %s\n' "$(uname -s)"
printf 'Architecture: %s\n' "$(uname -m)"
getconf GNU_LIBC_VERSION 2>/dev/null || true
printf 'DISPLAY: %s\n' "${DISPLAY-unset (headless)}"
maxima_data=${XDG_DATA_HOME-${HOME:?HOME or XDG_DATA_HOME is required}/.local/share}/maxima
runtime=${MAXIMA_WINE_COMMAND-$maxima_data/wine/umu/umu-run}
printf 'Maxima runtime command: %s\n' "$runtime"
printf 'Maxima prefix: %s\n' "$maxima_data/wine/prefix"
if [ "${MAXIMA_DISABLE_WINE_VERIFICATION+x}" = x ]; then
  printf 'Automatic runtime verification: disabled (variable is present)\n'
else
  printf 'Automatic runtime verification: enabled\n'
fi
if command -v "$runtime" >/dev/null 2>&1; then
  printf 'Runtime executable: found\n'
else
  printf 'Runtime executable: not found in this environment\n'
fi
if [ -f "$maxima_data/wine/proton/version" ]; then
  printf 'Managed Proton version: '
  head -n 1 "$maxima_data/wine/proton/version"
fi
cd "$package_dir"
if [ -f release-manifest.json ]; then
  printf '\nRelease manifest:\n'
  cat release-manifest.json
fi
if command -v sha256sum >/dev/null 2>&1; then
  if [ -f SHA256SUMS ]; then
    printf '\nPackage integrity:\n'
    sha256sum -c SHA256SUMS
  else
    printf '\nComponent hashes (no manifest in this older bundle):\n'
    for component in kyber_cli librust_lib.so maxima-bootstrap wine-helper.exe lan-module/Kyber.dll; do
      if [ -f "$component" ]; then
        sha256sum "$component"
      else
        printf 'Missing: %s\n' "$component"
      fi
    done
  fi
fi
if command -v ss >/dev/null 2>&1; then
  printf '\nLAN UDP sockets (empty until server is listening):\n'
  ss -H -lun '( sport = :25200 or sport = :25202 )'
fi
printf '\nThis report does not verify game startup. Kyber started is a license event.\n'

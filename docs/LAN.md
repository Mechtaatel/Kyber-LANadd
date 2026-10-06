# LAN hosting

This fork adds IPv4 LAN discovery and a LAN-only hosting mode. Rebuild **all three
components** (Kyber.dll, Launcher and CLI) from this branch. Stock Kyber modules
ignore the new `StartServerRequest.lanOnly` field and cannot host this mode.
Regenerate protobuf bindings as described in BUILDING.md before building Dart.

## Launcher

Use **LAN — WITHOUT KYBER SERVICES** on the login screen. When the Kyber status
screen blocks the application, choose **Continue in LAN mode**. EA/Maxima still
handles game ownership, login and launch; this is independent of Kyber services.
The game, Maxima, rebuilt module, module dependencies and all gameplay mods must
already be installed. LAN mode skips Kyber module updates and preloaded-mod
downloads, so it does not replace the locally built module with an upstream one.

Portable fork bundles include a `lan-module` directory next to the launcher/CLI.
For Windows online play, the launcher installs the bundled fork `Kyber.dll` into
`%ProgramData%/Kyber/Module` so Cyrillic localization works there too. The first
stock DLL is saved as `Kyber.dll.lan-add-original` and restored when LAN ADD is
uninstalled. Missing or empty accompanying files are restored from the local
bundle; the launcher does not download a separate official module. The fork's
version is recorded in `LAN-ADD-VERSION`, leaving the upstream `VERSION` intact.
Keep the entire LAN bundle with
Kyber.dll, vivoxsdk.dll, ca_root.pem and VanillaBundleAggregation.kb. Updating the
fork module requires installing a newer complete fork bundle. Do not place the
marker next to an official DLL: a marker alone cannot add LAN support.

LAN ADD launcher updates are checked on startup against published Releases of
`Mechtaatel/Kyber-LANadd` on GitHub, including when using LAN mode. The default
**beta** channel includes prereleases; **stable** includes only stable releases.
Use **Settings → Accounts and Updates → LAN ADD updates** to check manually.
Choose **Install** to download and verify the release's Windows installer, update
the current installation directory and restart. The installer updates both the
launcher and bundled LAN module. Close Battlefront II before installing.
Network failures do not prevent launcher startup or LAN use.

For a new Windows release, update `Launcher/assets/lan_add_version.txt` before
building and publish the matching `v<version>` tag with exactly one asset named
`Kyber-LAN-ADD-<version>-Setup.exe`. The packager rejects a stale version asset;
Inno Setup uses the same version file by default. After resolving Flutter
dependencies, `tools/build-launcher-windows.ps1` builds and packages the Windows
launcher and installer using an existing module; it does not rebuild the DLL.
GitHub supplies the asset's
SHA-256, which the updater checks before running the installer. Draft releases,
releases whose title starts with `[BROKEN]` or `BROKEN`, and releases containing
`<!-- lan-add-update: disabled -->` in their notes are excluded from updates.

Under New Server, **LAN ONLY** is available with OFF/ON buttons.
Leave it disabled for normal public hosting. Both online and LAN-only sessions
use the fork DLL; LAN-only hosts advertise locally and skip Kyber services.
LAN-only hosts do not register with Kyber or connect to Kyber proxies. Players
connect directly to the host. LAN-only sessions do not use Kyber join tokens,
global bans, verified Kyber identities, public statistics or Vivox voice chat.
LAN-only passwords are currently unsupported and are rejected explicitly.
Restart the game when switching between LAN-only and online sessions. A LAN-only
launcher session lists autonomous hosts; public hosts still require online login.

The server browser scans on refresh, merges discovered hosts with public
listings, and labels the region **LAN**. Use **REGION → LAN** to see only local
hosts. Sorting is official servers (including official Battlefront Plus), LAN
servers, friends' servers, then other servers. A public server also found on LAN
appears once and uses its direct LAN address. Discovery packets cannot grant a
server official status. LAN-only hosts are not grouped using public hosting IDs.
The route is checked again before joining. A hybrid public/LAN server still
requires a valid Kyber login and join token; LAN priority does not disable public
server authentication. Use LAN-only hosting for independence from Kyber outages.
The CLI retains its existing bundle-first module selection and is not changed
by this Windows launcher compatibility workaround.
Public API failures retain the last successful public snapshot for up to two
minutes with an on-screen warning; background refresh no longer hides the list.

## Linux CLI

Run the native Linux CLI alongside its Rust library, Maxima bootstrap and
wine-helper.exe, with the Windows Kyber.dll and its dependencies in lan-module.
The CLI already links `maxima-lib`; no separate Maxima application is needed.
The Windows game and DLL still need a Wine-compatible runtime on Linux. The
original Docker image bundles Wine-GE and sets `MAXIMA_WINE_COMMAND` to it.
Preserve the working runtime and prefix of an existing installation; do not
unset those settings merely to try a different runtime. Outside Docker, point
`MAXIMA_WINE_COMMAND` at an installed compatible Wine binary. Without that
override, upstream Maxima may attempt its own runtime installation, which is
not required by the original Docker hosting path or verified for this fork.
Do not set DISPLAY just to suppress Wine diagnostics on a headless server.
If MAXIMA_DISABLE_WINE_VERIFICATION is present (even set to 0), Maxima skips
automatic runtime verification and installation.

For an extracted release bundle:

```sh
./kyber_cli --skip-updates start_server --lan \
  --server-name 'My LAN server' \
  --game-path /mnt/battlefront/starwarsbattlefrontii.exe \
  --module-path /opt/kyber/lan-module \
  --map 'S5_1/Levels/MP/Geonosis_01/Geonosis_01' \
  --mode HeroesVersusVillains
```

`KYBER_LAN=1` (also `KYBER_LAN=True`) or `KYBER_LAN_ONLY=1` enables this
mode. `--no-lan-discovery` or
`KYBER_LAN_DISCOVERY=0` disables discovery. LAN mode needs no Kyber API token and
does not fetch or upload licenses through a Kyber license endpoint. A valid game
license and the normal EA/Maxima startup requirements still apply. Without
`--credentials`, the CLI uses its normal Maxima login flow; provision the account
before using an unattended service.

The upstream Linux setup guide explains how to install Docker and the game.
Its `registry.kyber.gg/kyber-server:latest` image supplies Wine and Maxima,
but contains the official CLI and module, not this fork. No custom image is
distributed. To use that image for LAN, mount the entire extracted fork CLI
bundle and override its entrypoint so the fork binaries run instead:

```sh
unzip kyber-cli-linux-x64.zip
chmod +x kyber-cli-linux-x64/kyber_cli kyber-cli-linux-x64/maxima-bootstrap kyber-cli-linux-x64/wine-helper.exe
docker run --rm --network host \
  -e MAXIMA_CREDENTIALS='email:password' \
  -e KYBER_SERVER_NAME='My LAN server' \
  -e KYBER_MAP_ROTATION='<base64-export-from-fork-launcher>' \
  -e KYBER_LAN=1 \
  -v "$PWD/kyber-cli-linux-x64:/opt/kyber-lan:ro" \
  -v '/absolute/path/to/Battlefront II:/mnt/battlefront' \
  --entrypoint /bin/bash registry.kyber.gg/kyber-server:latest \
  /opt/kyber-lan/run-lan-docker-overlay.sh
```

The overlay script loads our CLI, Rust library, Maxima bootstrap/helper and
Kyber.dll from the same bundle, while the official image supplies Wine. It
does not use the official image's CLI or module. The game mount must be writable
because the launcher copies `vivoxsdk.dll` into it. LAN broadcast discovery
needs `--network host` on Linux. `KYBER_TOKEN` is unnecessary in LAN-only mode;
EA authentication and a valid game license remain required. `KYBER_MAP_ROTATION`
may be omitted for the default map. The fork launcher's base64 export encodes
UTF-8 `mode;map` lines (despite the upstream article describing JSON). For a
mod collection, add `-e KYBER_MOD_FOLDER=/mnt/mods` and mount the collection
directory at `/mnt/mods`. With explicit `--game-path`, the fork validates the
game executable without requiring an EA registry install entry. The `latest`
image may change; this image-overlay path still needs a Linux in-game test.
As in the original CLI, the server reads nested `.fbmod` paths from
`.kbcollection`. Those names must match physical filenames in
`KYBER_MOD_FOLDER` **inside the container**. If the metadata has display names
but the installed `.fbcollection` uses different raw names, run the bundled
`repair-server-collection.py` once on the Linux host to write a corrected
metadata-only `.kbcollection` without changing the mods or CLI behavior:

```sh
python3 repair-server-collection.py /path/to/old.kbcollection \
  --mod-folder /path/to/mounted/mods \
  --output /path/to/repaired.kbcollection
```

Inspect the new file, then move the old `.kbcollection` outside the mounted mod
folder and put the repaired file in its place. Keep exactly one `.kbcollection`
there. The CLI reports exact expected paths if
the names still differ. Client-only cosmetic mods can differ;
level-affecting game resources must be compatible. If the
same host is listed on physical LAN and
Radmin, use the physical-LAN address unless UDP 25200 is also allowed through
the VPN firewall; discovery on 25202 alone does not prove the game route works.
For a long-running service, replace `--rm` with `-d --restart unless-stopped`
and use `docker logs -f` to inspect startup. Avoid enabling verbose CLI logging
while passing EA credentials on the command line.

If using Docker `--env-file`, write `MAXIMA_CREDENTIALS=email:password`
without shell quotes: Docker preserves those quotes as part of the value.
For a value already exported by your shell, use `-e MAXIMA_CREDENTIALS`.
Do not print the credentials when diagnosing login failures.

### Persistent service example

Adapt these paths and the service user to your installation. Store
`MAXIMA_CREDENTIALS=persona:password` in `/etc/kyber/lan.env`, readable only by the
administrator. Ensure the service user owns its configured Maxima/Wine prefix
and has access to the game and modules.

```ini
# /etc/systemd/system/kyber-lan.service
[Unit]
Description=Kyber LAN server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=kyber
WorkingDirectory=/opt/kyber
Environment=KYBER_LAN_ONLY=1
EnvironmentFile=/etc/kyber/lan.env
ExecStart=/opt/kyber/kyber_cli --skip-updates start_server --lan --server-name=LAN --module-path=/opt/kyber/lan-module --game-path=/mnt/battlefront/starwarsbattlefrontii.exe --credentials=${MAXIMA_CREDENTIALS}
Restart=always
RestartSec=10
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
```

Install and start with `systemctl daemon-reload` and
`systemctl enable --now kyber-lan`; inspect logs with `journalctl -u kyber-lan -f`.

## Network requirements

Allow inbound UDP **25200** (game) and **25202** (discovery) from your trusted LAN
on the host. Do not forward these ports on the internet router. Discovery uses
limited IPv4 broadcast plus loopback, and accepts private, link-local and
loopback IPv4 sources. Radmin 26/8 is also supported when the local machine has
a 26/8 adapter; a directed 26.255.255.255 probe supplements limited broadcast.
26/8 is not an RFC1918 private network. Restrict firewall rules to trusted VPN
peers as well as your physical LAN. IPv6, routed VLANs, broadcast-blocking Wi-Fi
isolation and VPNs that do not carry broadcasts are not covered. One discoverable server
per machine/network namespace is supported with these fixed ports.

The query is ASCII `KYBER-LAN-1:` followed by a random 16-byte nonce. The response
echoes that query and appends a `kyber_api.Server` protobuf. The launcher takes
the IP from the UDP sender, sanitizes privilege/grouping metadata, deduplicates
the response, and discards it on the next scan if the host no longer responds.
The game thread polls a nonblocking discovery socket, bounds work per tick and
limits responses. The nonce correlates responses; it does not authenticate hosts.

## Manual release checks

Before releasing binaries, test on two physical machines:

1. Block access to Kyber services, enter LAN mode and launch an unmodded host.
2. On another machine, refresh the browser, select REGION → LAN and join.
3. Verify player count, map rotation, reconnect and host disappearance on refresh.
4. Repeat with matching gameplay mods and a Linux/Wine host (including restart).
5. Restore normal mode and check official/LAN/friend ordering and public joins.

## Linux bundle ABI check

Pin the Dart package, Rust crate and FRB generator to **2.11.1** together.
Run `dart tool/check_frb_version.dart` inside CLI before packaging. Windows
cross-compilation and ELF inspection alone are not a Linux runtime test.

New release bundles include SHA256SUMS and release-manifest.json. Verify them
before installing the package. The cross-built CLI requires glibc 2.30 or newer.
Use `sh diagnose-linux.sh` under the service user's environment to report the
runtime selection, package hashes and listening LAN ports without starting the
game or changing the prefix. It does not inspect credentials or dump the full
environment. A successful help command is not a successful game launch.

Older bundles' `Kyber started` message is emitted on the game's license request.
The updated CLI labels that event explicitly as not confirming server readiness.
Server readiness
requires map startup and the discovery-listening log; an access violation after
the license event remains a startup failure.

The earlier experimental managed Proton/umu patch is removed. It was not part
of the original Docker hosting path and was not shown to cure the BFII crash.
Keep DISPLAY and WAYLAND_DISPLAY unset for the headless test. For systemd, use
the service's existing runtime environment. The game launch remains unverified
on Linux, including without mods.

## Unicode localization mods

Localization replacements support Cyrillic (including Ё/ё), other scripts and
UTF-16 surrogate pairs. The module rebuilds the string table and histogram;
invalid or oversized input leaves the original localization intact and is
reported in the module log. This fixes text encoding, not missing glyphs in a
mod's custom font. A specific Russian localization mod still needs in-game
verification.

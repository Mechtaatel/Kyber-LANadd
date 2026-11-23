# LAN hosting

This fork adds IPv4 LAN discovery and a LAN-only hosting mode. Build Kyber.dll
once and package the same DLL with the launcher and server bundle. Rebuild Dart
clients when their code or the launcher/module protocol changes. Stock Kyber modules
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
The Windows installer puts the fork module in `%ProgramData%/Kyber/LAN-Modules`.
For online play, the launcher downloads updates for the selected official
module channel into `%ProgramData%/Kyber/Module`. Downloads are staged and
validated before replacing the installed files.
The LAN bundle supplies Kyber.dll, vivoxsdk.dll, ca_root.pem and VanillaBundleAggregation.kb.
To publish a DLL-only update, create a release in `Mechtaatel/Kyber-LANadd`
with a new tag such as `lan-module-v1.0.0` and attach the compiled `Kyber.dll`
under that exact filename. Leave **Set as the latest release** unchecked to keep
the launcher installer on the repository's latest-release page. For a test build, use a tag such as
`lan-module-v1.1.0-beta.1` and mark the release as a prerelease. Keep the
launcher version unchanged. The Windows launcher checks the selected channel
before starting a LAN game when automatic updates are enabled. It verifies
the DLL against the asset size and SHA-256 supplied by GitHub. If GitHub is
unreachable, the installed module remains available for play.
For Linux hosting, replace the server bundle's DLL and restart the game server.

LAN ADD launcher updates are checked on startup against published Releases of
`Mechtaatel/Kyber-LANadd` on GitHub, including when using LAN mode. The default
**beta** channel includes prereleases; **stable** includes only stable releases.
Use **Settings → Accounts and Updates → LAN ADD updates** to check manually.
Choose **Install** to download and verify the release's Windows installer, update
the current installation directory and restart. A fresh install includes the base LAN module. Reinstalling the
launcher preserves independently updated LAN modules. Close Battlefront II before installing.
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
Leave it disabled for normal public hosting. Online sessions use the current
official module. LAN-only hosts use the bundled fork DLL, advertise locally
and skip Kyber services.
LAN-only hosts do not register with Kyber or connect to Kyber proxies. Players
connect directly to the host. LAN-only sessions do not use Kyber join tokens,
global bans, verified Kyber identities, public statistics or Vivox voice chat.
LAN-only passwords are currently unsupported and are rejected explicitly.
Restart the game when switching between LAN-only and online sessions. A LAN-only
launcher session lists autonomous hosts and public hosts that explicitly enable
independent LAN admission. Other public hosts still require online login.

The server browser scans on refresh, merges discovered hosts with public
listings, and labels the region **LAN**. Use **REGION → LAN** to see only local
hosts. Sorting is official servers (including official Battlefront Plus), LAN
servers, friends' servers, then other servers. A public server also found on LAN
appears once and uses its direct LAN address. Discovery packets cannot grant a
server official status. LAN-only hosts are not grouped using public hosting IDs.
The route is checked again before joining. By default, a hybrid public/LAN server
requires a valid Kyber login and join token. Hosts can explicitly enable the
independent admission route described below without removing public hosting.
The CLI uses the bundled LAN module if present.
Public API failures retain the last successful public snapshot for up to two
minutes with an on-screen warning; background refresh no longer hides the list.

### Independent LAN admission on a public host

Set `KYBER_LAN_INDEPENDENT=1` in the game process environment and leave LAN
discovery enabled. A host without a password advertises an independent LAN entry
using the existing `lan_only=1` protocol. Released LAN ADD 1.8.3 clients already
support it: select the LAN entry, which connects directly without requesting a
Kyber join token, server details, proxies, public stats or voice credentials.
There are no discovery tickets, expiry timers or client-module upgrades required.
Updating the server DLL is sufficient for this route. The public Kyber entry
continues using Kyber account authentication; an invalid Kyber token never falls
back to guest admission. The independent route accepts guest joins on the game
listener, so keep direct UDP access restricted to the intended LAN/VPN peers.

The server assigns a random, separate session identity; clients cannot claim another player's EA/Kyber ID or
obtain owner privileges by nickname. Plugins that grant roles must verify local
sessions independently, for example using the existing Discord link-code flow.
Kyber parties, account entitlements, global bans and public statistics cannot be
verified for this independent session. EA ownership and matching mods remain
required. This route must be enabled only on a trusted private network.

In released 1.8.3, use **LAN — WITHOUT KYBER SERVICES** on the EA login screen
when Kyber cannot be reached. New launcher sources also provide automatic fallback
after a bounded wait. `Start-LAN.cmd` in portable Windows bundles forces LAN mode
immediately. Once running, restart the game to switch
between a public Kyber session and an independent LAN session. To leave forced
LAN mode, close the game and launcher, then run `kyber_launcher.exe` directly.
With independent
admission enabled, a server whose initial public registration fails still starts
locally and retries public registration in the background.

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
same host is listed on physical LAN and Radmin, allow its configured game UDP
port on the interface used by players.
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

Gameplay and discovery share one UDP socket, **25200** by default. Change
**Host → Server → UDP Port**, pass `--server-port 30000` to `start_server`, or set
`KYBER_SERVER_PORT=30000` in the container. Each instance on the same host needs
its own available port. Allow that UDP port on the interface used by players.

The browser broadcasts on the default port and checks 25202 for older hosts.
For a custom port or a network that does not carry broadcasts, use **+** beside
Refresh and enter the reachable IPv4 address and game port, e.g.
`192.168.0.155:30000`. Confirmed addresses are saved and checked on refresh.
With UDP port forwarding, enter the external port. Local-only hosts accept
private LAN and supported VPN peers. For an independently accessible public
host, enable `KYBER_LAN_INDEPENDENT=1` and forward its UDP port if needed.

Discovery uses a random 16-byte nonce prefixed with `KYBER-LAN-1:`. The game
socket consumes these requests before gameplay parsing. Non-local clients echo
a server-issued cookie before receiving server metadata. The launcher checks
the reply address, port and nonce and measures the discovery round-trip time.

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

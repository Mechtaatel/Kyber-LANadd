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

Under New Server, **LAN ONLY (NO KYBER SERVICES)** is available as an opt-in
toggle. Leave it disabled for normal public hosting. Both public and LAN-only hosts advertise locally;
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

## Linux CLI

Run the rebuilt CLI alongside its Rust library and Maxima bootstrap, with the
rebuilt Windows Kyber.dll and its dependencies installed for Wine:

```sh
./kyber_cli --skip-updates start_server --lan \
  --server-name 'My LAN server' \
  --game-path /mnt/battlefront/starwarsbattlefrontii.exe \
  --module-path /opt/kyber/module \
  --map 'S5_1/Levels/MP/Geonosis_01/Geonosis_01' \
  --mode HeroesVersusVillains
```

`KYBER_LAN_ONLY=1` also enables this mode. `--no-lan-discovery` or
`KYBER_LAN_DISCOVERY=0` disables discovery. LAN mode needs no Kyber API token and
does not fetch or upload licenses through a Kyber license endpoint. A valid game
license and the normal EA/Maxima startup requirements still apply. Without
`--credentials`, the CLI uses its normal Maxima login flow; provision the account
before using an unattended service.

For the existing Docker entrypoint set `KYBER_LAN_ONLY=1`; `KYBER_TOKEN` is then
optional. On Linux use host networking (`--network host`) so LAN broadcasts reach
Wine. Merely publishing UDP ports through Docker NAT is insufficient for
broadcast discovery. Existing game/module volumes and EA credentials still apply.

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
ExecStart=/opt/kyber/kyber_cli --skip-updates start_server --lan --server-name=LAN --module-path=/opt/kyber/module --game-path=/mnt/battlefront/starwarsbattlefrontii.exe --credentials=${MAXIMA_CREDENTIALS}
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
loopback IPv4 sources. IPv6, routed VLANs, broadcast-blocking Wi-Fi isolation
and VPNs that do not carry broadcasts are not covered. One discoverable server
per machine/network namespace is supported with these fixed ports.

The query is ASCII `KYBER-LAN-1:` followed by a random 16-byte nonce. The response
echoes that query and appends a `kyber_api.Server` protobuf. The launcher takes
the IP from the UDP sender, sanitizes privilege/grouping metadata, deduplicates
the response, and discards it on the next scan if the host no longer responds.
The game thread polls a nonblocking discovery socket, bounds work per tick and
limits responses. The nonce correlates responses; it does not authenticate hosts.

## Verification

After generating protobuf bindings:

```sh
cd tools/lan_tests
dart pub get
dart test
```

Tests exercise a real loopback UDP responder, malformed/stale replies, metadata
sanitization, deduplication, stopped hosts, address validation and the host flag's
protobuf round trip, plus official/LAN/friend priority. Before releasing binaries,
test on two physical machines:

1. Block access to Kyber services, enter LAN mode and launch an unmodded host.
2. On another machine, refresh the browser, select REGION → LAN and join.
3. Verify player count, map rotation, reconnect and host disappearance on refresh.
4. Repeat with matching gameplay mods and a Linux/Wine host (including restart).
5. Restore normal mode and check official/LAN/friend ordering and public joins.

The automated protocol tests do not substitute for an in-game multiplayer test.

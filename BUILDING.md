# Building KYBER

## Prerequisites

- Clone the repository with `--recurse-submodules` or run `git submodule --init --recursive`
- Download and install [Protoc](https://github.com/protocolbuffers/protobuf/releases) and ensure `protoc` is in your `PATH`

------

## Dart/Flutter Projects (Launcher, CLI, Packages)

### Prequisites
- [Flutter](https://flutter.dev) (master channel)
- [Rust](https://rustup.rs) (nightly toolchain)
- [Melos](https://melos.invertase.dev): `dart pub global activate melos`

### Bootstrapping (Required for Launcher & CLI)

Bootstrap the workspace from the repository root:

```bash
melos bootstrap
```

This installs dependencies, generates proto bindings, and runs code generation.

## Launcher (Flutter)

### Generating FFI Bindings

First you need to generate the FFI bindings:
```bash
cd Launcher
dart run tool/ffigen.dart
```

### Run in Debug Mode

From the launcher directory, run:
```bash
flutter run
```

### Build Release Binaries

From the launcher directory, run:
```bash
flutter build <platform>
```

If the Windows workspace path contains parentheses (for example, under Program
Files x86), first run `tools/prepare-windows-build.ps1` from the repository root.
It adjusts generated Cargokit batch files so native plugin builds handle that
path correctly. Run `flutter pub get` in Launcher before this step.

For this fork's Windows LAN launcher, Kyber.dll and Linux CLI release archives,
run one command from the repository root in PowerShell:

```powershell
./tools/build-lan-release.ps1
```

The script uses build caches on D:, verifies the FRB versions and reused CLI
inputs first, builds Kyber.dll once and copies that same binary into both
packages, builds the launcher, and writes a new pair of ZIPs
under `artifacts/`. Use `-ResolveDependencies` after dependency changes and
`-RebuildCli` after CLI/Rust changes. Add `-RegenerateBindings` when changing
the Rust API exposed through FRB; Dart-only changes reuse the existing bindings.
If a CLI build stopped after Rust completed, resume with `-RebuildCli
-SkipCliRustBuild` only when the prebuilt Rust library still matches the Rust
and Maxima sources. This skips Cargo but rebuilds the Dart executable.
If DLL compilation has already completed,
resume with `-SkipDllBuild`. If the launcher also completed and only packaging
needs to be repeated, add `-SkipLauncherBuild`. These explicit resume switches
reuse existing outputs; use them only if the corresponding sources have not
changed. Package DLL copies are checked against the source DLL's SHA256.
Each bundle includes `release-manifest.json` and `SHA256SUMS`; Linux bundles
also include `diagnose-linux.sh`. The manifest records
packaging provenance, not proof of an in-game test. Override path parameters if
your tool or Maxima installation differs. It never overwrites an existing
release directory.

For Windows-to-Linux CLI cross-builds the script compiles Rust in a short path
under ToolsRoot, then passes the compiled library into Dart's native build hook.
This avoids Zig's linker failure when Cargo places archives under a workspace
path containing spaces. The temporary hook configuration is removed after use.

### Building the Installer

To build the installer on Windows, you can use [Inno Setup](https://jrsoftware.org/isinfo.php) with the provided `installer.iss` script located in the `installer` folder.

## CLI (Flutter)

### Building the CLI

```bash
cd CLI
flutter pub get
dart tool/prepare_maxima.dart
flutter_rust_bridge_codegen generate
dart build cli bin/kyber_cli.dart
```

This will output the binary to `build/cli/<platform>/bundle/bin/`.

The CLI carries its Linux launch/PID compatibility fix in `CLI/patches/`. The preparation step
applies it idempotently to the pinned submodule and fails on conflicting local
edits. The Dart native build hook and CI also apply it automatically. Seeing
this submodule as modified after building is expected; the tracked patch is the
reproducible source of those changes. No upstream submodule commit is required.

### Using the Built CLI

To run the CLI, make sure to copy the rust library from `build/cli/<platform>/bundle/lib/` next to the binary.

The `maxima-lib` library is linked into `librust_lib`; there is no separate
Maxima application to install for the CLI. Build its bootstrap/helper binaries
first, then copy the following files next to the CLI binary:

#### Windows
- `maxima-service.exe`
- `maxima-bootstrap.exe`

#### Linux
- `maxima-bootstrap`
- `wine-helper.exe` (Maxima's Windows process/injection helper)

------

## Module (C++)

### Building the KYBER Module

The KYBER Module can only be compiled on Windows, with MSVC.

First, install [bazelisk](https://github.com/bazelbuild/bazelisk/releases/download/v1.25.0/bazelisk-windows-amd64.exe) and drop it into your `PATH` as `bazel.exe`.

There is a bug with the gRPC client version we're using in combination with Bazel's long build paths, which makes some build paths extend past the legacy Windows path limit. To work around this, make a folder named `bz` at the root of your drive. We'll be using this folder to store bazel's intermediary files.

Ensure you have [MSYS2](https://www.msys2.org/) installed to `C:\msys64`.

Run `bazel --output_user_root="C:\bz" build --config=release Kyber`. This will take a while. Once it's done, you should have `Module/bazel-bin/Kyber.dll`. You may alternatively run the `build.bat` file in the root by running `.\build.bat` and modifying the path to the correct drive.

**Important:** The module requires the `--config=release` flag. Building without it (i.e., in debug mode) will lead to crashes.

### Using the Built Module

Once built, copy `Module/bazel-bin/Kyber.dll` to `C:/ProgramData/Kyber/Module/Kyber.dll` to test your changes with the Launcher or CLI.

### Code Completion

The KYBER module is primarily developed using Visual Studio Code with the clangd extension. `compile_commands.json` can be generated by running `clangd/refresh.bat` while inside the `Module` folder.

------

## API (Go)

Requires Go 1.24+ and protoc with Go plugins:

```bash
go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
```

Build:

Linux:
```bash
cd API
./scripts/gen-proto.sh
go build -o kyber-api ./cmd/server
```

Windows:
```bash
cd API
scripts\gen-proto.bat
go build -o kyber-api.exe ./cmd/server
```

------

## Proxy (Rust)

Requires Rust nightly and protoc.

```bash
cd Proxy
cargo build --release
```

Output: `target/release/kyber_proxy`

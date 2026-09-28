param(
    [string]$Name = ('lan-radmin-' + (Get-Date -Format 'yyyyMMdd-HHmmss')),
    [string]$ToolsRoot = 'D:\dev\kyber-tools',
    [string]$BazelRoot = 'D:\bz',
    [string]$PubCache = 'D:\dev\Dart\PubCache',
    [string]$CargoHome = 'D:\dev\Rust\.cargo',
    [string]$RustupHome = 'D:\dev\Rust\.rustup',
    [string]$MaximaWindows = 'D:\Program Files (x86)\KYBER Launcher LAN',
    [string]$MaximaLinux = 'D:\dev\kyber-tools\maxima-linux64\extracted',
    [string]$RuntimeDirectory = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\14.44.35112\x64\Microsoft.VC143.CRT',
    [string]$ModuleDependencies = 'C:\ProgramData\Kyber\Module',
    [ValidateRange(1, 16)][int]$BazelJobs = 2,
    [switch]$ResolveDependencies,
    [switch]$RebuildCli,
    [switch]$SkipCliRustBuild,
    [switch]$RegenerateBindings,
    [switch]$SkipDllBuild,
    [switch]$SkipLauncherBuild
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$flutter = Join-Path $ToolsRoot 'flutter\bin\flutter.bat'
$dart = Join-Path $ToolsRoot 'flutter\bin\cache\dart-sdk\bin\dart.exe'
$wingetBazel = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\Bazel.Bazelisk_Microsoft.Winget.Source_8wekyb3d8bbwe\bazelisk.exe'
$bazelCommand = Get-Command bazelisk.exe -ErrorAction SilentlyContinue
$bazel = if ($bazelCommand) { $bazelCommand.Source } else { $wingetBazel }
$tempDir = Join-Path $ToolsRoot 'build-temp'
$cliBundle = Join-Path $repo 'CLI\build\cli\linux_x64\bundle'
$moduleDll = Join-Path $repo 'Module\bazel-bin\Kyber.dll'
$wineHelper = Join-Path $MaximaLinux 'wine-helper.exe'
if ($Name -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Release name may contain only letters, digits, underscores and hyphens' }
if ($RegenerateBindings -and !$RebuildCli) { throw '-RegenerateBindings requires -RebuildCli' }
if ($SkipCliRustBuild -and !$RebuildCli) { throw '-SkipCliRustBuild requires -RebuildCli' }
$releaseDir = Join-Path $repo "artifacts\$Name"
if (Test-Path -LiteralPath $releaseDir) { throw "Release directory already exists: $releaseDir" }

function Assert-File([string]$Path) {
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing file: $Path" }
}
function Assert-Directory([string]$Path) {
    if (!(Test-Path -LiteralPath $Path -PathType Container)) { throw "Missing directory: $Path" }
}
function Invoke-Checked([string]$Label, [scriptblock]$Action) {
    Write-Host "==> $Label"
    & $Action
    if ($LASTEXITCODE -ne 0) { throw "$Label failed (exit code $LASTEXITCODE)" }
}

Assert-File $flutter
Assert-File $dart
if (!$SkipDllBuild) { Assert-File $bazel }
Assert-Directory $PubCache
Assert-Directory $CargoHome
Assert-Directory $RustupHome
Assert-Directory $MaximaWindows
Assert-Directory $MaximaLinux
Assert-Directory $ModuleDependencies
Assert-File $wineHelper
New-Item -ItemType Directory -Force -Path $BazelRoot, $tempDir | Out-Null

# Flutter/Cargokit and the Linux linker need a short, space-free workspace path.
# A pre-existing K: mapping must point to this repository; never replace it.
$mapping = (subst | Select-String '^K:\\: => (.+)$' | Select-Object -First 1)
$madeMapping = $false
if ($mapping) {
    $mappedRepo = $mapping.Matches[0].Groups[1].Value.TrimEnd('\')
    if ($mappedRepo -ine $repo.TrimEnd('\')) {
        throw "K: points to $mappedRepo, expected $repo"
    }
} else {
    & subst.exe 'K:' $repo
    if ($LASTEXITCODE -ne 0) { throw 'Could not create K: workspace mapping' }
    $madeMapping = $true
}

$oldEnvironment = @{}
foreach ($key in @(
    'PUB_CACHE', 'CARGO_HOME', 'RUSTUP_HOME', 'TEMP', 'TMP', 'PROTOC', 'PATH',
    'CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER',
    'CC_x86_64_unknown_linux_gnu', 'AR_x86_64_unknown_linux_gnu', 'KYBER_ZIG_EXE',
    'KYBER_REPO_REAL', 'KYBER_REPO_ALIAS'
)) {
    $oldEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
}
try {
    $env:PUB_CACHE = $PubCache
    $env:CARGO_HOME = $CargoHome
    $env:RUSTUP_HOME = $RustupHome
    $env:TEMP = $tempDir
    $env:TMP = $tempDir
    $env:PROTOC = Join-Path $ToolsRoot 'protoc\bin\protoc.exe'
    $env:PATH = (@(
        (Join-Path $ToolsRoot 'flutter\bin'),
        (Join-Path $ToolsRoot 'flutter\bin\cache\dart-sdk\bin'),
        (Join-Path $ToolsRoot 'protoc\bin'),
        (Join-Path $CargoHome 'bin'),
        $ToolsRoot,
        $oldEnvironment['PATH']
    ) -join [IO.Path]::PathSeparator)
    Assert-File $env:PROTOC

    # Validate the reused CLI before spending time compiling the DLL/launcher.
    Push-Location 'K:\CLI'
    try {
        if ($ResolveDependencies) { Invoke-Checked 'CLI dependencies' { & $dart pub get } }
        if ($RegenerateBindings) {
            $codegen = Join-Path $CargoHome 'bin\flutter_rust_bridge_codegen.exe'
            Assert-File $codegen
            $codegenVersion = & $codegen --version
            if ($LASTEXITCODE -ne 0 -or $codegenVersion -notmatch '\b2\.11\.1\b') {
                throw "Expected FRB generator 2.11.1, found: $codegenVersion"
            }
            Invoke-Checked 'FRB code generation' { & $codegen generate --no-auto-upgrade-dependency }
        }
        Invoke-Checked 'FRB version check' { & $dart tool\check_frb_version.dart }
        if ($RebuildCli) {
            # Keep the linker path stable: Cargo fingerprints this environment
            # value and would otherwise rebuild the entire dependency graph.
            $zigCc = Join-Path $tempDir 'zig-linux-cc.exe'
            $cargoTarget = Join-Path $ToolsRoot 'cargo-linux-target'
            $prebuiltRustLibrary = Join-Path $cargoTarget 'x86_64-unknown-linux-gnu\release\librust_lib.so'
            $zigCcSource = Join-Path $repo 'tools\zig-linux-cc.rs'
            $zigAr = Join-Path $ToolsRoot 'zig-0.16.0\zigar.cmd'
            $env:KYBER_ZIG_EXE = Join-Path $ToolsRoot 'zig-0.16.0\zig.exe'
            $env:KYBER_REPO_REAL = $repo
            $env:KYBER_REPO_ALIAS = 'K:'
            Assert-File $zigCcSource
            Assert-File $zigAr
            Assert-File $env:KYBER_ZIG_EXE
            Invoke-Checked 'Linux linker wrapper' {
                & (Join-Path $CargoHome 'bin\rustc.exe') '+nightly-2026-04-06' --edition=2021 $zigCcSource -o $zigCc
            }
            $env:CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER = $zigCc
            $env:CC_x86_64_unknown_linux_gnu = $zigCc
            $env:AR_x86_64_unknown_linux_gnu = $zigAr
            if ($SkipCliRustBuild) {
                Assert-File $prebuiltRustLibrary
                Write-Host "==> Reusing prebuilt Linux Rust library: $prebuiltRustLibrary"
            } else {
                Push-Location 'K:\CLI\rust'
                try {
                    Invoke-Checked 'Linux Rust library' {
                        & (Join-Path $CargoHome 'bin\cargo.exe') build --release --package rust_lib --target x86_64-unknown-linux-gnu --target-dir $cargoTarget
                    }
                } finally { Pop-Location }
            }
            Assert-File $prebuiltRustLibrary
            $hookEnvironment = Join-Path $repo 'CLI\.dart_tool\kyber-build-environment.json'
            if (Test-Path -LiteralPath $hookEnvironment) {
                throw "Build environment file already exists; inspect it before retrying: $hookEnvironment"
            }
            try {
                $variables = @{
                    CARGO_HOME = $CargoHome
                    RUSTUP_HOME = $RustupHome
                    PROTOC = $env:PROTOC
                    CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER = $zigCc
                    CC_x86_64_unknown_linux_gnu = $zigCc
                    AR_x86_64_unknown_linux_gnu = $zigAr
                    KYBER_ZIG_EXE = $env:KYBER_ZIG_EXE
                    KYBER_REPO_REAL = $env:KYBER_REPO_REAL
                    KYBER_REPO_ALIAS = $env:KYBER_REPO_ALIAS
                    KYBER_PREBUILT_RUST_LIB = $prebuiltRustLibrary
                }
                [IO.File]::WriteAllText($hookEnvironment, ($variables | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
                Invoke-Checked 'Linux CLI cross-build' { & $dart build cli --target-os linux --target-arch x64 }
            } finally {
                if (Test-Path -LiteralPath $hookEnvironment) {
                    Remove-Item -LiteralPath $hookEnvironment
                }
            }
        }
    } finally { Pop-Location }
    Assert-File (Join-Path $cliBundle 'bin\kyber_cli')
    Assert-File (Join-Path $cliBundle 'lib\librust_lib.so')
    if (!$RebuildCli) {
        $cliExecutableTime = (Get-Item -LiteralPath (Join-Path $cliBundle 'bin\kyber_cli')).LastWriteTimeUtc
        $cliLibraryTime = (Get-Item -LiteralPath (Join-Path $cliBundle 'lib\librust_lib.so')).LastWriteTimeUtc
        $dartSources = Get-ChildItem -Path (Join-Path $repo 'CLI\bin'), (Join-Path $repo 'CLI\lib'),
            (Join-Path $repo 'Packages\kyber\lib'), (Join-Path $repo 'Packages\kyber_collection\lib') -Recurse -File
        $dartSources += Get-Item -LiteralPath (Join-Path $repo 'CLI\pubspec.yaml'), (Join-Path $repo 'CLI\pubspec.lock'),
            (Join-Path $repo 'Packages\kyber\pubspec.yaml'), (Join-Path $repo 'Packages\kyber_collection\pubspec.yaml')
        if ($dartSources | Where-Object LastWriteTimeUtc -GT $cliExecutableTime | Select-Object -First 1) {
            throw 'Linux CLI source is newer than the bundled executable; rerun with -RebuildCli.'
        }
        $rustSources = Get-ChildItem -Path (Join-Path $repo 'CLI\rust\src'),
            (Join-Path $repo 'CLI\hook'), (Join-Path $repo 'CLI\patches'),
            (Join-Path $repo 'CLI\ThirdParty\Maxima\maxima-lib\src') -Recurse -File
        $rustSources += Get-Item -LiteralPath (Join-Path $repo 'CLI\rust\Cargo.toml'),
            (Join-Path $repo 'CLI\tool\prepare_maxima.dart'),
            (Join-Path $repo 'CLI\rust\Cargo.lock'), (Join-Path $repo 'CLI\rust\rust-toolchain.toml'),
            (Join-Path $repo 'CLI\ThirdParty\Maxima\maxima-lib\Cargo.toml')
        if ($rustSources | Where-Object LastWriteTimeUtc -GT $cliLibraryTime | Select-Object -First 1) {
            throw 'Linux Rust source is newer than librust_lib.so; rerun with -RebuildCli.'
        }
    }

    if ($SkipDllBuild) {
        Assert-File $moduleDll
        Write-Host "==> Reusing existing Kyber.dll: $moduleDll"
    } else {
        Push-Location 'K:\Module'
        try {
            # One build; the packager copies this exact DLL into both bundles.
            Invoke-Checked 'Kyber.dll' { & $bazel "--output_user_root=$BazelRoot" --batch build --config=release "--jobs=$BazelJobs" Kyber }
        } finally { Pop-Location }
        Assert-File $moduleDll
    }

    if ($SkipLauncherBuild) {
        Assert-File (Join-Path $repo 'Launcher\build\windows\x64\runner\Release\data\app.so')
        Write-Host '==> Reusing existing Windows Launcher (explicit resume)'
    } else {
        Push-Location 'K:\Launcher'
        try {
            if ($ResolveDependencies) {
                Invoke-Checked 'Flutter dependencies' { & $flutter pub get }
            } else {
                Assert-File (Join-Path $repo '.dart_tool\package_config.json')
            }
            & (Join-Path $repo 'tools\prepare-windows-build.ps1')
            Invoke-Checked 'Windows Launcher' { & $flutter build windows --release --no-pub }
        } finally { Pop-Location }
    }

    & (Join-Path $repo 'tools\package-lan-release.ps1') `
        -ModuleDll $moduleDll `
        -ModuleDependencies $ModuleDependencies `
        -MaximaWindows $MaximaWindows `
        -MaximaLinux $MaximaLinux `
        -RuntimeDirectory $RuntimeDirectory `
        -WineHelper $wineHelper `
        -Name $Name
    if ($LASTEXITCODE -ne 0) { throw 'Packaging failed' }
    Write-Host "Release: $releaseDir"
} finally {
    foreach ($entry in $oldEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }
    if ($madeMapping) { & subst.exe 'K:' /D | Out-Null }
}

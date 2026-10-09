param(
    [Parameter(Mandatory=$true)][string]$MaximaDirectory,
    [Parameter(Mandatory=$true)][string]$ModuleDirectory,
    [string]$RuntimeDirectory = 'C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Redist/MSVC/14.44.35112/x64/Microsoft.VC143.CRT',
    [string]$Name = 'kyber-launcher-lan-add-20260928-complete'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if ($Name -notmatch '^[a-zA-Z0-9._-]+$') { throw 'Invalid package name' }
$release = Join-Path $repo 'Launcher/build/windows/x64/runner/Release'
$destination = Join-Path $repo "artifacts/$Name"
$archive = "$destination.zip"
if ((Test-Path -LiteralPath $destination) -or (Test-Path -LiteralPath $archive)) {
    throw 'Output already exists; choose another package name'
}
$requiredRelease = @('kyber_launcher.exe', 'flutter_windows.dll', 'rust_lib.dll', 'data/app.so', 'data/icudtl.dat', 'data/flutter_assets/AssetManifest.bin')
$requiredMaxima = @('maxima-bootstrap.exe', 'maxima-service.exe')
$requiredModule = @('Kyber.dll', 'vivoxsdk.dll', 'ca_root.pem', 'VanillaBundleAggregation.kb', 'LAN-MODULE', 'VERSION')
$requiredRuntime = @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')
$nativeAssets = Join-Path $repo 'Launcher/build/native_assets/windows'
if (!(Test-Path -LiteralPath (Join-Path $nativeAssets 'rust_lib.dll') -PathType Leaf)) {
    throw 'Fresh Rust native assets are missing; rebuild the launcher.'
}
foreach ($asset in Get-ChildItem -LiteralPath $nativeAssets -Filter '*.dll' -File) {
    $installedAsset = Join-Path $release $asset.Name
    if (!(Test-Path -LiteralPath $installedAsset -PathType Leaf) -or
        (Get-FileHash -LiteralPath $installedAsset -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $asset.FullName -Algorithm SHA256).Hash) {
        throw "Native library $($asset.Name) is missing or stale in the release directory; rebuild the launcher."
    }
}
$sourceVersionPath = Join-Path $repo 'Launcher/assets/lan_add_version.txt'
$builtVersionPath = Join-Path $release 'data/flutter_assets/assets/lan_add_version.txt'
if (!(Test-Path -LiteralPath $builtVersionPath -PathType Leaf)) {
    throw 'LAN ADD version asset is missing from the build; rebuild the launcher.'
}
$sourceVersion = [IO.File]::ReadAllText($sourceVersionPath).Trim()
$builtVersion = [IO.File]::ReadAllText($builtVersionPath).Trim()
if ($sourceVersion -ne $builtVersion) {
    throw "Built LAN ADD version $builtVersion does not match source $sourceVersion; rebuild the launcher."
}
foreach ($group in @(
    @{ Root=$release; Files=$requiredRelease },
    @{ Root=$MaximaDirectory; Files=$requiredMaxima },
    @{ Root=$ModuleDirectory; Files=$requiredModule },
    @{ Root=$RuntimeDirectory; Files=$requiredRuntime }
)) {
    foreach ($name in $group.Files) {
        $path = Join-Path $group.Root $name
        if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required component: $path" }
    }
}
New-Item -ItemType Directory -Path $destination | Out-Null
Get-ChildItem -LiteralPath $release | Where-Object Name -ne 'lan-module' | Copy-Item -Destination $destination -Recurse
foreach ($name in $requiredMaxima) {
    Copy-Item -LiteralPath (Join-Path $MaximaDirectory $name) -Destination $destination
}
$module = New-Item -ItemType Directory -Path (Join-Path $destination 'lan-module')
foreach ($name in $requiredModule) {
    Copy-Item -LiteralPath (Join-Path $ModuleDirectory $name) -Destination $module.FullName
}
# The launcher's own voice service loads Vivox next to the executable.
Copy-Item -LiteralPath (Join-Path $ModuleDirectory 'vivoxsdk.dll') -Destination $destination
# Never overwrite freshly built Flutter/Rust/plugin DLLs when the runtime
# source is an existing installation rather than the MSVC redist directory.
Get-ChildItem -LiteralPath $RuntimeDirectory -Filter '*.dll' | Where-Object {
    $_.Name -match '^(msvcp140(?:_[a-z0-9_]+)?|vcruntime140(?:_[a-z0-9_]+)?|concrt140|vccorlib140)\.dll$'
} | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $destination
    Copy-Item -LiteralPath $_.FullName -Destination $module.FullName
}
Copy-Item -LiteralPath (Join-Path $repo 'LICENSE') -Destination $destination
Copy-Item -LiteralPath (Join-Path $repo 'docs/LAN.md') -Destination $destination
# Release directories can retain BUILD-INFO from an earlier local build.
# Record the actual packaged launcher and DLL rather than copying that claim.
$packagedDll = Join-Path $module.FullName 'Kyber.dll'
$moduleBytes = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($packagedDll))
$engineVersions = @([regex]::Matches($moduleBytes, '2\.0\.0-beta\d+') | ForEach-Object {
    $_.Value
} | Sort-Object -Unique)
$buildInfo = [ordered]@{
    packagedAtUtc = [DateTime]::UtcNow.ToString('o')
    sourceCommit = (& git -C $repo rev-parse HEAD).Trim()
    sourceDirty = @(& git -C $repo status --porcelain).Count -gt 0
    launcherVersion = (Get-Item -LiteralPath (Join-Path $destination 'kyber_launcher.exe')).VersionInfo.ProductVersion
    lanAddVersion = $builtVersion
    moduleVersion = [IO.File]::ReadAllText((Join-Path $module.FullName 'VERSION')).Trim()
    moduleEngineVersionLiterals = $engineVersions
    moduleSha256 = (Get-FileHash -LiteralPath $packagedDll -Algorithm SHA256).Hash.ToLowerInvariant()
    gameConnectionTested = $false
}
[IO.File]::WriteAllText((Join-Path $destination 'BUILD-INFO.json'), ($buildInfo | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
$sums = @(Get-ChildItem -LiteralPath $destination -File -Recurse | Sort-Object FullName | ForEach-Object {
    $relative = $_.FullName.Substring($destination.Length + 1).Replace('\', '/')
    "$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $relative"
})
[IO.File]::WriteAllLines((Join-Path $destination 'SHA256SUMS'), $sums, [Text.UTF8Encoding]::new($false))
Compress-Archive -Path (Join-Path $destination '*') -DestinationPath $archive
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($archive)
try {
    foreach ($name in ($requiredRelease + $requiredMaxima + $requiredRuntime + @('vivoxsdk.dll') + @(($requiredModule + $requiredRuntime) | ForEach-Object { "lan-module/$_" }))) {
        if (!$zip.GetEntry($name)) { throw "Missing packaged component: $name" }
    }
} finally { $zip.Dispose() }
Get-Item -LiteralPath $archive | Select-Object FullName, Length
Get-FileHash -LiteralPath $archive -Algorithm SHA256

param(
    [Parameter(Mandatory=$true)][string]$MaximaDirectory,
    [Parameter(Mandatory=$true)][string]$ModuleDirectory,
    [string]$RuntimeDirectory = 'C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Redist/MSVC/14.44.35112/x64/Microsoft.VC143.CRT',
    [string]$Name = 'kyber-launcher-lan-add-20260928-complete'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if ($Name -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Invalid package name' }
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
Get-ChildItem -LiteralPath $RuntimeDirectory -Filter '*.dll' | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $destination
    Copy-Item -LiteralPath $_.FullName -Destination $module.FullName
}
Copy-Item -LiteralPath (Join-Path $repo 'LICENSE') -Destination $destination
$sums = @(Get-ChildItem -LiteralPath $destination -File -Recurse | Sort-Object FullName | ForEach-Object {
    $relative = $_.FullName.Substring($destination.Length + 1).Replace('\', '/')
    "$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $relative"
})
[IO.File]::WriteAllLines((Join-Path $destination 'SHA256SUMS'), $sums, [Text.UTF8Encoding]::new($false))
Compress-Archive -Path (Join-Path $destination '*') -DestinationPath $archive
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($archive)
try {
    foreach ($name in ($requiredRelease + $requiredMaxima + $requiredRuntime + @(($requiredModule + $requiredRuntime) | ForEach-Object { "lan-module/$_" }))) {
        if (!$zip.GetEntry($name)) { throw "Missing packaged component: $name" }
    }
} finally { $zip.Dispose() }
Get-Item -LiteralPath $archive | Select-Object FullName, Length
Get-FileHash -LiteralPath $archive -Algorithm SHA256

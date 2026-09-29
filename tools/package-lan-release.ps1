param(
    [Parameter(Mandatory=$true)][string]$ModuleDll,
    [Parameter(Mandatory=$true)][string]$ModuleDependencies,
    [Parameter(Mandatory=$true)][string]$MaximaWindows,
    [Parameter(Mandatory=$true)][string]$MaximaLinux,
    [Parameter(Mandatory=$true)][string]$WineHelper,
    [string]$RuntimeDirectory = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\14.44.35112\x64\Microsoft.VC143.CRT',
    [string]$Name = 'lan-radmin-frb2111-20260923'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if ($Name -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Invalid release name' }
$output = Join-Path $repo "artifacts/$Name"
if (Test-Path -LiteralPath $output) { throw "Release directory already exists: $output" }
$launcher = Join-Path $repo 'Launcher/build/windows/x64/runner/Release'
$cli = Join-Path $repo 'CLI/build/cli/linux_x64/bundle'
$required = @(
    $ModuleDll,
    "$ModuleDependencies/vivoxsdk.dll", "$ModuleDependencies/ca_root.pem",
    "$ModuleDependencies/VanillaBundleAggregation.kb",
    "$launcher/kyber_launcher.exe", "$launcher/flutter_windows.dll", "$launcher/rust_lib.dll",
    "$launcher/data/app.so", "$launcher/data/icudtl.dat",
    "$cli/bin/kyber_cli", "$cli/lib/librust_lib.so",
    "$MaximaWindows/maxima-bootstrap.exe", "$MaximaWindows/maxima-service.exe",
    "$MaximaLinux/maxima-bootstrap", $WineHelper,
    "$RuntimeDirectory/msvcp140.dll", "$RuntimeDirectory/vcruntime140.dll",
    "$RuntimeDirectory/vcruntime140_1.dll"
)
foreach ($file in $required) {
    if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing component: $file" }
}
Push-Location "$repo/CLI"
try {
    dart tool/check_frb_version.dart
    if ($LASTEXITCODE -ne 0) { throw 'FRB versions do not match' }
} finally { Pop-Location }
$win = New-Item -ItemType Directory -Path "$output/kyber-launcher-windows-x64"
$linux = New-Item -ItemType Directory -Path "$output/kyber-cli-linux-x64"
Get-ChildItem -LiteralPath $launcher | Where-Object {
    $_.Name -ne 'lan-module'
} | Copy-Item -Destination $win.FullName -Recurse
Copy-Item -LiteralPath "$cli/bin/kyber_cli", "$cli/lib/librust_lib.so", "$MaximaLinux/maxima-bootstrap", $WineHelper -Destination $linux.FullName
Copy-Item -LiteralPath "$MaximaWindows/maxima-bootstrap.exe", "$MaximaWindows/maxima-service.exe" -Destination $win.FullName
Get-ChildItem -LiteralPath $RuntimeDirectory -Filter '*.dll' | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $win.FullName
}
Copy-Item -LiteralPath "$repo/CLI/tool/diagnose-linux.sh" -Destination $linux.FullName
Copy-Item -LiteralPath "$repo/CLI/tool/run-lan-docker-overlay.sh" -Destination $linux.FullName
Copy-Item -LiteralPath "$repo/tools/repair-server-collection.py" -Destination $linux.FullName
$moduleHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ModuleDll).Hash
$revision = & git -C $repo rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Could not read source revision' }
$sourceChanges = @(& git -C $repo status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Could not read source status' }
foreach ($bundle in @($win.FullName, $linux.FullName)) {
    $module = New-Item -ItemType Directory -Path "$bundle/lan-module"
    Copy-Item -LiteralPath $ModuleDll -Destination "$($module.FullName)/Kyber.dll"
    $copiedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath "$($module.FullName)/Kyber.dll").Hash
    if ($copiedHash -ne $moduleHash) { throw "Kyber.dll copy verification failed: $bundle" }
    foreach ($dependency in @('vivoxsdk.dll', 'ca_root.pem', 'VanillaBundleAggregation.kb')) {
        Copy-Item -LiteralPath "$ModuleDependencies/$dependency" -Destination $module.FullName
    }
    if ($bundle -eq $win.FullName) {
        Get-ChildItem -LiteralPath $RuntimeDirectory -Filter '*.dll' | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $module.FullName
        }
    }
    Copy-Item -LiteralPath "$repo/Module/LAN-MODULE" -Destination $module.FullName
    Copy-Item -LiteralPath "$repo/Module/LAN-MODULE" -Destination "$($module.FullName)/VERSION"
    Copy-Item -LiteralPath "$repo/docs/LAN.md", "$repo/LICENSE" -Destination $bundle
}
foreach ($bundle in @($win, $linux)) {
    # Record exact packaged bytes. The source check does not claim a Linux
    # runtime test, and HEAD alone is insufficient for an uncommitted build.
    $files = @(Get-ChildItem -LiteralPath $bundle.FullName -Recurse -File | Sort-Object FullName | ForEach-Object {
        [ordered]@{
            path = $_.FullName.Substring($bundle.FullName.Length + 1).Replace('\', '/')
            size = $_.Length
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
        }
    })
    $manifest = [ordered]@{
        release = $Name
        bundle = $bundle.Name
        packaged_at_utc = [DateTime]::UtcNow.ToString('o')
        source_head_at_packaging = $revision.Trim()
        source_dirty_at_packaging = $sourceChanges.Count -gt 0
        frb_source_version = '2.11.1'
        linux_game_launch_verified = $false
        files = $files
    }
    $encoding = [Text.UTF8Encoding]::new($false)
    $manifestPath = Join-Path $bundle.FullName 'release-manifest.json'
    [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6), $encoding)
    $sums = @($files | ForEach-Object { "$($_.sha256)  $($_.path)" })
    $sums += (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath).Hash.ToLowerInvariant() + '  release-manifest.json'
    [IO.File]::WriteAllText((Join-Path $bundle.FullName 'SHA256SUMS'), ($sums -join "`n") + "`n", $encoding)
    Compress-Archive -LiteralPath $bundle.FullName -DestinationPath "$output/$($bundle.Name).zip"
}
Get-FileHash -Algorithm SHA256 -LiteralPath "$output/kyber-launcher-windows-x64.zip", "$output/kyber-cli-linux-x64.zip"

param(
    [string]$Name,
    [string]$InstallerName,
    [string]$ToolsRoot = 'D:\dev\kyber-tools',
    [string]$PubCache = 'D:\dev\Dart\PubCache',
    [string]$CargoHome = 'D:\dev\Rust\.cargo',
    [string]$RustupHome = 'D:\dev\Rust\.rustup',
    [string]$MaximaDirectory = 'D:\Program Files (x86)\KYBER Launcher LAN',
    [string]$ModuleDirectory = 'D:\Program Files (x86)\KYBER Launcher LAN\lan-module',
    [string]$RuntimeDirectory = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\14.44.35112\x64\Microsoft.VC143.CRT',
    [string]$InstallerCompiler = 'D:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    [switch]$SkipLauncherBuild
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$version = [IO.File]::ReadAllText((Join-Path $repo 'Launcher/assets/lan_add_version.txt')).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?$') { throw 'Invalid LAN ADD release version' }
if (!$Name) { $Name = "kyber-lan-add-$version-windows" }
if ($Name -notmatch '^[a-zA-Z0-9._-]+$') { throw 'Invalid package name' }
$flutter = Join-Path $ToolsRoot 'flutter/bin/flutter.bat'
$setupName = if ($InstallerName) { $InstallerName } else { "Kyber-LAN-ADD-$version-Setup" }
if ($setupName -notmatch '^[a-zA-Z0-9._-]+$') { throw 'Invalid installer output name' }
$setupPath = Join-Path $repo "artifacts/$setupName.exe"
foreach ($file in @($flutter, $InstallerCompiler)) {
    if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing build tool: $file" }
}
if (Test-Path -LiteralPath $setupPath) { throw "Installer already exists: $setupPath" }
$mapping = (subst | Select-String '^K:\\: => (.+)$' | Select-Object -First 1)
$madeMapping = $false
if ($mapping) {
    if ($mapping.Matches[0].Groups[1].Value.TrimEnd('\') -ine $repo.TrimEnd('\')) {
        throw 'K: is mapped to another directory'
    }
} else {
    & subst.exe 'K:' $repo
    if ($LASTEXITCODE -ne 0) { throw 'Could not create K: workspace mapping' }
    $madeMapping = $true
}
$previousEnvironment = @{}
foreach ($key in @('PUB_CACHE', 'CARGO_HOME', 'RUSTUP_HOME', 'TEMP', 'TMP', 'PROTOC', 'PATH')) {
    $previousEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
}
try {
    $env:PUB_CACHE = $PubCache
    $env:CARGO_HOME = $CargoHome
    $env:RUSTUP_HOME = $RustupHome
    $env:TEMP = Join-Path $ToolsRoot 'build-temp'
    $env:TMP = $env:TEMP
    $env:PROTOC = Join-Path $ToolsRoot 'protoc/bin/protoc.exe'
    $env:PATH = ((Join-Path $CargoHome 'bin'), (Join-Path $ToolsRoot 'flutter/bin'),
        (Join-Path $ToolsRoot 'protoc/bin'), $previousEnvironment['PATH']) -join [IO.Path]::PathSeparator
    New-Item -ItemType Directory -Force -Path $env:TEMP | Out-Null
    if (!$SkipLauncherBuild) {
        Write-Host "Building LAN ADD $version"
        Push-Location 'K:\Launcher'
        try {
            & (Join-Path $repo 'tools/prepare-windows-build.ps1')
            & $flutter build windows --release --no-pub
            if ($LASTEXITCODE -ne 0) { throw "Windows launcher build failed: $LASTEXITCODE" }
        } finally { Pop-Location }
    }
    Write-Host 'Packaging the Windows launcher and module'
    & (Join-Path $repo 'tools/package-launcher-windows.ps1') `
        -MaximaDirectory $MaximaDirectory -ModuleDirectory $ModuleDirectory `
        -RuntimeDirectory $RuntimeDirectory -Name $Name
    $bundle = Join-Path $repo "artifacts/$Name"
    Write-Host "Compiling $setupName.exe"
    & $InstallerCompiler '/Q' "/DBundleSourceDir=$bundle" "/DSetupOutputName=$setupName" `
        (Join-Path $repo 'Launcher/installer/lan-add-beta1.iss')
    if ($LASTEXITCODE -ne 0) { throw "Installer compilation failed: $LASTEXITCODE" }
    Get-Item -LiteralPath $setupPath | Format-List FullName, Length
    Get-FileHash -LiteralPath $setupPath -Algorithm SHA256 | Format-List
} finally {
    foreach ($entry in $previousEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }
    if ($madeMapping) { & subst.exe 'K:' /D | Out-Null }
}

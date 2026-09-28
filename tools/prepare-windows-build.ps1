# Cargokit's bundled .cmd writes a generated pubspec inside a parenthesized
# batch block. Delayed expansion avoids interpreting `(x86)` in the workspace
# path as CMD control syntax. Patch only ephemeral links of packages in pubspec.
$ErrorActionPreference = 'Stop'
$links = Join-Path $PSScriptRoot '../Launcher/windows/flutter/ephemeral/.plugin_symlinks'
if (!(Test-Path -LiteralPath $links -PathType Container)) {
    throw "Flutter plugin links are missing; run flutter pub get in Launcher first."
}
$old = 'echo     path: %BUILD_TOOL_PKG_DIR_POSIX%'
$new = 'echo     path: !BUILD_TOOL_PKG_DIR_POSIX!'
$patched = 0
foreach ($plugin in Get-ChildItem -LiteralPath $links -Directory) {
    $runner = Join-Path $plugin.FullName 'cargokit/run_build_tool.cmd'
    if (!(Test-Path -LiteralPath $runner -PathType Leaf)) { continue }
    $source = [IO.File]::ReadAllText($runner)
    if ($source.Contains($old)) {
        $encoding = [Text.UTF8Encoding]::new($false)
        [IO.File]::WriteAllText($runner, $source.Replace($old, $new), $encoding)
        $patched++
    }
}
Write-Output "Prepared $patched Cargokit build script(s) for a workspace path containing parentheses."

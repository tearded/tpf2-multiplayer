<# Builds the committed checkout; never installs into a live game. #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'
$repoRoot = Split-Path $PSScriptRoot -Parent
Set-Location $repoRoot
$packageVersion = (Get-Content installer/VERSION -Raw).Trim()
if ($packageVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'installer/VERSION must contain X.Y.Z' }
$versionParts = $packageVersion.Split('.') | ForEach-Object { [int]$_ }
if ($versionParts[0] -gt 255 -or $versionParts[1] -gt 255 -or $versionParts[2] -gt 65535) { throw 'Version exceeds MSI version limits' }
$lobbySource = Get-Content netpunch/lobby.py -Raw
if ($lobbySource -notmatch ('(?m)^LOBBY_VERSION = "' + [regex]::Escape($packageVersion) + '"\r?$')) { throw 'LOBBY_VERSION and installer/VERSION must match' }
if ($env:GITHUB_REF -like 'refs/tags/*' -and $env:GITHUB_REF -cne "refs/tags/v$packageVersion") { throw 'Release tag must equal v<installer/VERSION>' }
if ($env:GITHUB_REF -like 'refs/tags/*' -and -not (Test-Path -LiteralPath "docs/releases/$packageVersion.md")) { throw 'A release needs docs/releases/<version>.md, including known issues and validation' }

python tools/luacheck.py
if ($LASTEXITCODE -ne 0) { throw 'Lua syntax checks failed' }
foreach ($testName in @('crossing_replay_test.py','bridge_companion_test.py','edge_demolition_test.py','track_fresh_test.py','delay_hold_test.py','preview_test.py')) {
    $testPath = Join-Path tools $testName
    if (Test-Path -LiteralPath $testPath) {
        python $testPath
        if ($LASTEXITCODE -ne 0) { throw "Regression failed: $testName" }
    }
}
python tools/relay_selftest.py
if ($LASTEXITCODE -ne 0) { throw 'Relay self-test failed' }
$env:TPF2_BUILD_NO_DEPLOY = '1'
$withPreviews = Test-Path -LiteralPath native/src/preview_plugin.cpp
if ($withPreviews) {
    if (-not (Test-Path mod/mp_lockstep_1/res/scripts/mp/previews.lua) -or
        (Get-Content mod/mp_lockstep_1/res/config/game_script/lockstep.lua -Raw) -notmatch 'mp\.previews' -or
        (Get-Content mod/mp_lockstep_1/res/scripts/mp/net.lua -Raw) -notmatch 'LSPREVIEW') { throw 'Preview DLL and Lua integration must ship together' }
    if (Test-Path tools/preview_native_test.cpp) {
        New-Item -ItemType Directory -Force native/out | Out-Null
        cmd /d /c 'call tools\msvc_env.bat && cl /nologo /std:c++17 /EHsc /W4 tools\preview_native_test.cpp /Fe:native\out\preview-native-test.exe /Fo:native\out\preview-native-test.obj && native\out\preview-native-test.exe'
        if ($LASTEXITCODE -ne 0) { throw 'Native preview regression failed' }
    }
}
& ./installer/build_msi.ps1 -Version $packageVersion -AcceptWixEula -IncludePreviews:$withPreviews
if ($LASTEXITCODE -ne 0) { throw 'Installer build failed' }
& ./tools/validate_release_package.ps1 -Version $packageVersion -IncludePreviews:$withPreviews
$packagePath = Join-Path $repoRoot 'installer/out/TpF2Multiplayer.msi'
$packageHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $repoRoot 'installer/out/SHA256SUMS.txt'), "$packageHash  TpF2Multiplayer.msi`n")
$sourceCommit = (git rev-parse HEAD).Trim()
[ordered]@{version=$packageVersion; commit=$sourceCommit; repository=$env:GITHUB_REPOSITORY; previews=$withPreviews; sha256=$packageHash; builtUtc=[DateTime]::UtcNow.ToString('o')} |
    ConvertTo-Json | Set-Content -Encoding utf8 installer/out/build-info.json
if ($env:GITHUB_OUTPUT) { "version=$packageVersion" | Add-Content -LiteralPath $env:GITHUB_OUTPUT }
if ($env:GITHUB_STEP_SUMMARY) { "Built and hash-verified TpF2Multiplayer.msi **$packageVersion** from commit $sourceCommit. Preview plugin: $withPreviews. No game installation or play test performed." | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY }

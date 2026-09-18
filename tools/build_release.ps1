<# Builds the committed checkout; never installs into a live game. #>
[CmdletBinding()]
param([ValidateRange(1,4)][int]$TestJobs = 4)
$ErrorActionPreference = 'Stop'
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'
$repoRoot = Split-Path $PSScriptRoot -Parent
Set-Location $repoRoot
$packageVersion = (Get-Content installer/VERSION -Raw).Trim()
if ($packageVersion -notmatch '^\d+\.\d+(\.\d+){0,2}$') { throw 'installer/VERSION must contain two to four numeric parts' }
$versionParts = $packageVersion.Split('.') | ForEach-Object { [int]$_ }
if ($versionParts[0] -gt 255 -or $versionParts[1] -gt 255 -or ($versionParts.Count -ge 3 -and $versionParts[2] -gt 65535) -or ($versionParts.Count -eq 4 -and $versionParts[3] -gt 65535)) { throw 'Version exceeds MSI version limits' }
$lobbySource = Get-Content netpunch/lobby.py -Raw
if ($lobbySource -notmatch ('(?m)^LOBBY_VERSION = "' + [regex]::Escape($packageVersion) + '"\r?$')) { throw 'LOBBY_VERSION and installer/VERSION must match' }
if ($env:GITHUB_REF -like 'refs/tags/*' -and $env:GITHUB_REF -cne "refs/tags/v$packageVersion") { throw 'Release tag must equal v<installer/VERSION>' }
if ($env:GITHUB_REF -like 'refs/tags/*' -and -not (Test-Path -LiteralPath "docs/releases/$packageVersion.md")) { throw 'A release needs docs/releases/<version>.md, including known issues and validation' }

$releaseClock = [Diagnostics.Stopwatch]::StartNew()
$env:TPF2_BUILD_NO_DEPLOY = '1'
# Initialize once; native builds and compiler tests inherit the same x64 tools.
# msvc_env.bat already validates and reuses this environment on subsequent calls.
$compilerEnvironment = cmd /d /c 'call tools\msvc_env.bat && set'
if ($LASTEXITCODE -ne 0) { throw 'MSVC environment initialization failed' }
foreach ($environmentLine in $compilerEnvironment) {
    $separator = $environmentLine.IndexOf('=')
    if ($separator -gt 0) {
        [Environment]::SetEnvironmentVariable($environmentLine.Substring(0, $separator), $environmentLine.Substring($separator + 1), 'Process')
    }
}
python tools/run_release_tests.py --jobs $TestJobs
if ($LASTEXITCODE -ne 0) { throw 'Release regressions failed; see per-test logs above' }
Write-Host ('[timing] regressions: {0:N1}s' -f $releaseClock.Elapsed.TotalSeconds)
$packageClock = [Diagnostics.Stopwatch]::StartNew()
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
python tools/updater_test.py
if ($LASTEXITCODE -ne 0) { throw 'Built MSI updater conversion regression failed' }
$packagePath = Join-Path $repoRoot 'installer/out/TpF2Multiplayer.msi'
$packageHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $repoRoot 'installer/out/SHA256SUMS.txt'), "$packageHash  TpF2Multiplayer.msi`n")
$sourceCommit = (git rev-parse HEAD).Trim()
[ordered]@{version=$packageVersion; commit=$sourceCommit; repository=$env:GITHUB_REPOSITORY; previews=$withPreviews; sha256=$packageHash; builtUtc=[DateTime]::UtcNow.ToString('o')} |
    ConvertTo-Json | Set-Content -Encoding utf8 installer/out/build-info.json
if ($env:GITHUB_OUTPUT) { "version=$packageVersion" | Add-Content -LiteralPath $env:GITHUB_OUTPUT }
if ($env:GITHUB_STEP_SUMMARY) { "Built and hash-verified TpF2Multiplayer.msi **$packageVersion** from commit $sourceCommit. Preview plugin: $withPreviews. No game installation or play test performed." | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY }

Write-Host ('[timing] build/package/validation: {0:N1}s; total: {1:N1}s' -f $packageClock.Elapsed.TotalSeconds, $releaseClock.Elapsed.TotalSeconds)

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [switch]$IncludePreviews
)
$ErrorActionPreference = 'Stop'
$packageRepo = Split-Path $PSScriptRoot -Parent
$packageMsi = Join-Path $packageRepo 'installer/out/TpF2Multiplayer.msi'
$packageEngine = New-Object -ComObject WindowsInstaller.Installer
$packageDb = $packageEngine.OpenDatabase($packageMsi,0)
$packageQuery = $packageDb.OpenView('SELECT `Property`, `Value` FROM `Property`')
$packageQuery.Execute()
$packageProperties = @{}
while ($packageRow = $packageQuery.Fetch()) { $packageProperties[$packageRow.StringData(1)] = $packageRow.StringData(2) }
$packageQuery.Close()
if ($packageProperties.ProductVersion -ne $Version -or $packageProperties.ProductName -ne 'TpF2 Multiplayer' -or $packageProperties.UpgradeCode -ne '{80DBF679-F058-410E-9BAD-87731AC96633}') { throw 'MSI metadata does not match the launcher contract' }
$extractRoot = Join-Path $env:TEMP ('tpf2-ci-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $extractRoot | Out-Null
$extractLog = Join-Path $extractRoot 'extract.log'
$extractProcess = Start-Process msiexec.exe -ArgumentList @('/a',"`"$packageMsi`"",'/qn',"TARGETDIR=`"$extractRoot`"",'/L*v',"`"$extractLog`"") -WindowStyle Hidden -PassThru -Wait
if ($extractProcess.ExitCode -ne 0) { throw "MSI extraction failed: $extractLog" }
$payloadRoot = Join-Path $extractRoot 'PFiles/Steam/steamapps/common/Transport Fever 2'
$expectedFiles = @{}
foreach ($dllName in @('alut.dll','tpf2_pluginhost.dll','tpf2_bridge_mp.dll','tpf2_menu.dll','tpf2_slice.dll')) { $expectedFiles[$dllName] = Join-Path $packageRepo "native/out/$dllName" }
$expectedFiles['netpunch/netpunch.exe'] = Join-Path $packageRepo 'netpunch/dist/netpunch.exe'
$expectedFiles['tpf2_slice.cfg'] = Join-Path $packageRepo 'installer/cfg/tpf2_slice.cfg'
if ($IncludePreviews) { $expectedFiles['plugins/tpf2_previews.dll'] = Join-Path $packageRepo 'native/out/tpf2_previews.dll' }
$modSourceRoot = Join-Path $packageRepo 'mod/mp_lockstep_1'
foreach ($modFile in Get-ChildItem -LiteralPath $modSourceRoot -Recurse -File) {
    $relativeMod = $modFile.FullName.Substring($modSourceRoot.Length).TrimStart('\','/').Replace('\','/')
    $expectedFiles["mods/mp_lockstep_1/$relativeMod"] = $modFile.FullName
}
$actualFiles = @(Get-ChildItem -LiteralPath $payloadRoot -Recurse -File)
if ($actualFiles.Count -ne $expectedFiles.Count) { throw "Unexpected payload file count: $($actualFiles.Count), expected $($expectedFiles.Count)" }
foreach ($relativePayload in $expectedFiles.Keys) {
    $extractedFile = Join-Path $payloadRoot $relativePayload
    if (-not (Test-Path -LiteralPath $extractedFile)) { throw "Payload file missing: $relativePayload" }
    if ((Get-FileHash -LiteralPath $extractedFile).Hash -ne (Get-FileHash -LiteralPath $expectedFiles[$relativePayload]).Hash) { throw "Payload hash mismatch: $relativePayload" }
}
Write-Output "MSI $Version verified: $($expectedFiles.Count) files match the complete build. Extracted only; no game installed."

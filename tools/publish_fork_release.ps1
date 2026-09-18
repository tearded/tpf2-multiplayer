<# Runs only for an intentionally pushed version tag, after the build job passed. #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_REPOSITORY -cne 'tearded/tpf2-multiplayer' -or $env:GITHUB_EVENT_NAME -ne 'push' -or $env:GITHUB_REF -notmatch '^refs/tags/v\d+\.\d+(\.\d+){0,2}$') { throw 'Publication requires a version tag push in the fork' }
$releaseTag = $env:GITHUB_REF.Substring('refs/tags/'.Length)
$releaseVersion = $releaseTag.Substring(1)
$releaseRepo = Split-Path $PSScriptRoot -Parent
Set-Location $releaseRepo
$buildInfo = Get-Content installer/out/build-info.json -Raw | ConvertFrom-Json
$releaseMsi = Join-Path $releaseRepo 'installer/out/TpF2Multiplayer.msi'
$releaseHash = (Get-FileHash -LiteralPath $releaseMsi).Hash.ToLowerInvariant()
if ($buildInfo.version -ne $releaseVersion -or $buildInfo.commit -ne $env:GITHUB_SHA -or $buildInfo.sha256 -ne $releaseHash) { throw 'Build provenance or package hash mismatch' }
$notesFile = Join-Path $releaseRepo "docs/releases/$releaseVersion.md"
if (-not (Test-Path -LiteralPath $notesFile)) { throw 'Release notes are required' }
$releaseNotes = (Get-Content -LiteralPath $notesFile -Raw) + "`n`nFork release from commit $($buildInfo.commit).`n`nSHA-256 (TpF2Multiplayer.msi): $releaseHash`n"
$notesOut = Join-Path $env:RUNNER_TEMP 'tpf2-release-notes.md'
[IO.File]::WriteAllText($notesOut,$releaseNotes)
$releaseList = gh api "repos/$env:GITHUB_REPOSITORY/releases?per_page=100" | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect existing releases' }
$existingRelease = @($releaseList | Where-Object tag_name -eq $releaseTag)
if ($existingRelease.Count -gt 0) { throw 'This version already has a release or draft. Existing assets are never replaced; use a new version or review the failed draft.' }
foreach ($publishedRelease in @($releaseList | Where-Object { -not $_.draft -and -not $_.prerelease -and $_.tag_name -match '^v\d+\.\d+(\.\d+){0,2}$' })) {
    if ([version]$publishedRelease.tag_name.Substring(1) -ge [version]$releaseVersion) { throw 'A launcher release must be newer than every published fork release' }
}
gh release create $releaseTag --repo $env:GITHUB_REPOSITORY --verify-tag --draft --title "Fork $releaseVersion" --notes-file $notesOut installer/out/TpF2Multiplayer.msi installer/out/SHA256SUMS.txt installer/out/build-info.json
if ($LASTEXITCODE -ne 0) { throw 'Creating the draft release failed' }
# The tag endpoint only returns published releases. Locate the authenticated
# draft by its numeric ID before checking its assets.
$draftList = gh api "repos/$env:GITHUB_REPOSITORY/releases?per_page=100" | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the created draft' }
$createdDraft = @($draftList | Where-Object { $_.tag_name -eq $releaseTag -and $_.draft })
if ($createdDraft.Count -ne 1) { throw 'Expected exactly one matching draft' }
$releaseData = gh api "repos/$env:GITHUB_REPOSITORY/releases/$($createdDraft[0].id)" | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $releaseData.draft -or $releaseData.tag_name -ne $releaseTag) { throw 'Draft verification failed' }
$releaseAsset = @($releaseData.assets | Where-Object name -eq 'TpF2Multiplayer.msi')
if ($releaseAsset.Count -ne 1 -or $releaseAsset[0].digest -ne "sha256:$releaseHash") { throw 'GitHub asset digest mismatch; release stays a draft' }
$verifyFolder = Join-Path $env:RUNNER_TEMP ('release-verify-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $verifyFolder | Out-Null
gh release download $releaseTag --repo $env:GITHUB_REPOSITORY --pattern TpF2Multiplayer.msi --dir $verifyFolder
if ($LASTEXITCODE -ne 0 -or (Get-FileHash -LiteralPath (Join-Path $verifyFolder 'TpF2Multiplayer.msi')).Hash.ToLowerInvariant() -ne $releaseHash) { throw 'Release download verification failed; release stays a draft' }
gh release edit $releaseTag --repo $env:GITHUB_REPOSITORY --draft=false --latest
if ($LASTEXITCODE -ne 0) { throw 'Publishing the verified draft failed' }
# Hosted runner IPs share the small anonymous API quota. Use the job token for
# this read; /releases/latest still excludes drafts and prereleases.
$activeRelease = gh api "repos/$env:GITHUB_REPOSITORY/releases/latest" | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $activeRelease.draft -or $activeRelease.prerelease -or $activeRelease.tag_name -ne $releaseTag -or @($activeRelease.assets | Where-Object { $_.name -eq 'TpF2Multiplayer.msi' -and $_.digest -eq "sha256:$releaseHash" }).Count -ne 1) { throw 'Public launcher feed verification failed' }
"Launcher release **$releaseVersion** is available: $($activeRelease.html_url)" | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY

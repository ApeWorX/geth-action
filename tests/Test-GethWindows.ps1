$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'scripts/GethWindows.psm1') -Force

function Assert-Equal($Expected, $Actual, $Message) {
    if ($Expected -ne $Actual) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

function Assert-Throws([scriptblock] $Script, [string] $Pattern, [string] $Message) {
    try {
        & $Script
    }
    catch {
        if ($_.Exception.Message -notmatch $Pattern) {
            throw "$Message Wrong error: $($_.Exception.Message)"
        }
        return
    }
    throw "$Message Expected an exception."
}

Assert-Equal '1.17.5' (ConvertTo-GethVersion -Version 'v1.17.5') 'Leading-v normalization failed.'
Assert-Equal '1.17.5' (ConvertTo-GethVersion -Version 'latest' -LatestVersion 'v1.17.5') 'Latest normalization failed.'

$listingContent = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/windows-builds.xml') -Raw
[xml] $listing = ConvertTo-GethBuildListing -Content $listingContent
$selected = Find-GethWindowsBlobName -Listing $listing -Version '1.17.5'
Assert-Equal 'geth-windows-amd64-1.17.5-3868a49b.zip' $selected 'Exact artifact selection failed.'

$unicodeBomListing = ConvertTo-GethBuildListing -Content (([char] 0xFEFF) + $listingContent)
Assert-Equal 'geth-windows-amd64-1.17.5-3868a49b.zip' (Find-GethWindowsBlobName -Listing $unicodeBomListing -Version '1.17.5') 'Unicode BOM handling failed.'

$misdecodedBom = -join @([char] 0x00EF, [char] 0x00BB, [char] 0x00BF)
$windowsPowerShellListing = ConvertTo-GethBuildListing -Content ($misdecodedBom + $listingContent)
Assert-Equal 'geth-windows-amd64-1.17.5-3868a49b.zip' (Find-GethWindowsBlobName -Listing $windowsPowerShellListing -Version '1.17.5') 'Windows PowerShell BOM handling failed.'

Assert-Throws { ConvertTo-GethBuildListing -Content 'not XML' } 'was not valid XML' 'Invalid listing check failed.'

[xml] $noMatch = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/windows-builds-no-match.xml') -Raw
Assert-Equal $null (Find-GethWindowsBlobName -Listing $noMatch -Version '1.17.5') 'Unrelated blobs should not match.'
Assert-Equal $null (Find-GethWindowsBlobName -Listing ([xml] '<EnumerationResults />') -Version '1.17.5') 'Missing Blobs should not throw.'
Assert-Equal $null (Find-GethWindowsBlobName -Listing ([xml] '<EnumerationResults><Blobs /></EnumerationResults>') -Version '1.17.5') 'Missing Blob should not throw.'

$testDir = Join-Path ([System.IO.Path]::GetTempPath()) ("geth-action-test-" + [guid]::NewGuid())
try {
    $archiveSource = Join-Path $testDir 'source'
    $archivePath = Join-Path $testDir 'missing-geth.zip'
    New-Item -ItemType Directory -Path $archiveSource -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $archiveSource 'README.txt') -Value 'no executable here'
    Compress-Archive -Path (Join-Path $archiveSource '*') -DestinationPath $archivePath
    Assert-Throws { Expand-GethWindowsArchive -ArchivePath $archivePath -DestinationPath (Join-Path $testDir 'extract') } 'contains no geth\.exe' 'Missing executable check failed.'
}
finally {
    Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'All Windows installer tests passed.'

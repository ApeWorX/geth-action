Set-StrictMode -Version Latest

function ConvertTo-GethVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Version,

        [string] $LatestVersion
    )

    if ($Version -eq 'latest') {
        if ([string]::IsNullOrWhiteSpace($LatestVersion)) {
            throw "LatestVersion is required when Version is 'latest'."
        }

        $Version = $LatestVersion
    }

    return $Version -replace '^v', ''
}

function Find-GethWindowsBlobName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [xml] $Listing,

        [Parameter(Mandatory = $true)]
        [string] $Version
    )

    $escapedVersion = [regex]::Escape($Version)
    $artifactPattern = "^geth-windows-amd64-$escapedVersion-[0-9a-f]{8}\.zip$"
    $nameNodes = $Listing.SelectNodes('/EnumerationResults/Blobs/Blob/Name')

    if ($null -eq $nameNodes) {
        return $null
    }

    foreach ($nameNode in $nameNodes) {
        $name = $nameNode.InnerText
        if ($name -cmatch $artifactPattern) {
            return $name
        }
    }

    return $null
}

function Expand-GethWindowsArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $ArchivePath,

        [Parameter(Mandatory = $true)]
        [string] $DestinationPath
    )

    New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $DestinationPath -Force
    $gethExe = Get-ChildItem -LiteralPath $DestinationPath -Filter 'geth.exe' -File -Recurse |
        Select-Object -First 1

    if ($null -eq $gethExe) {
        throw "The downloaded Geth archive contains no geth.exe: $ArchivePath"
    }

    return $gethExe.FullName
}

function Install-GethWindows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Version,

        [string] $InstallDir = 'C:\tools\geth',

        [Parameter(Mandatory = $true)]
        [string] $GitHubPath
    )

    $baseUrl = 'https://gethstore.blob.core.windows.net/builds'
    $prefix = "geth-windows-amd64-$Version-"
    $encodedPrefix = [uri]::EscapeDataString($prefix)
    $listingEndpoint = "$baseUrl`?restype=container&comp=list&prefix=$encodedPrefix"
    $workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("geth-action-" + [guid]::NewGuid())
    $archivePath = Join-Path $workDir 'geth.zip'
    $extractPath = Join-Path $workDir 'extract'

    New-Item -ItemType Directory -Path $workDir -Force | Out-Null

    try {
        Write-Host "Discovering the official Windows artifact for Geth $Version..."
        try {
            $response = Invoke-WebRequest -Uri $listingEndpoint -UseBasicParsing -ErrorAction Stop
            [xml] $listing = $response.Content
            $blobName = Find-GethWindowsBlobName -Listing $listing -Version $Version
        }
        catch {
            throw "Could not discover Geth version $Version using prefix '$prefix' at $listingEndpoint. $($_.Exception.Message)"
        }

        if ([string]::IsNullOrWhiteSpace($blobName)) {
            throw "Could not find Geth version $Version using prefix '$prefix' at $listingEndpoint. The listing contained no exact Windows amd64 archive match."
        }

        $downloadUrl = "$baseUrl/$([uri]::EscapeDataString($blobName))"
        Write-Host "Downloading $blobName..."
        Invoke-WebRequest -Uri $downloadUrl -OutFile $archivePath -UseBasicParsing -ErrorAction Stop

        $sourceExe = Expand-GethWindowsArchive -ArchivePath $archivePath -DestinationPath $extractPath
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        $installedExe = Join-Path $InstallDir 'geth.exe'
        Copy-Item -LiteralPath $sourceExe -Destination $installedExe -Force

        $versionOutput = & $installedExe version 2>&1 | Out-String
        Write-Host $versionOutput.TrimEnd()
        $reportedVersion = [regex]::Match($versionOutput, '(?m)^Version:\s*v?([0-9]+\.[0-9]+\.[0-9]+)').Groups[1].Value
        if ($reportedVersion -ne $Version) {
            throw "Installed geth.exe reported version '$reportedVersion'; expected '$Version'."
        }

        $InstallDir | Out-File -FilePath $GitHubPath -Encoding utf8 -Append
        $env:PATH = "$InstallDir;$env:PATH"
        return $installedExe
    }
    finally {
        if (Test-Path -LiteralPath $workDir) {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Export-ModuleMember -Function ConvertTo-GethVersion, Find-GethWindowsBlobName, Expand-GethWindowsArchive, Install-GethWindows

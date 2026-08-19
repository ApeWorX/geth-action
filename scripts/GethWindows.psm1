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

function ConvertTo-GethBuildListing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Content
    )

    # Windows PowerShell 5 may decode a UTF-8 BOM as the three visible
    # Windows-1252 characters "ï»¿". Either form makes the XML cast fail.
    $Content = $Content.TrimStart([char] 0xFEFF)
    $misdecodedBom = -join @([char] 0x00EF, [char] 0x00BB, [char] 0x00BF)
    if ($Content.StartsWith($misdecodedBom)) {
        $Content = $Content.Substring($misdecodedBom.Length)
    }

    try {
        return [xml] $Content
    }
    catch {
        throw "The Geth build listing response was not valid XML. $($_.Exception.Message)"
    }
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
            [xml] $listing = ConvertTo-GethBuildListing -Content $response.Content
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

        # Capture stdout only. Windows PowerShell 5 turns redirected native
        # stderr into ErrorRecord objects, which become terminating errors when
        # the runner sets ErrorActionPreference to Stop.
        $versionOutput = & $installedExe version | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "Installed geth.exe exited with code $LASTEXITCODE while reporting its version."
        }

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

Export-ModuleMember -Function ConvertTo-GethVersion, ConvertTo-GethBuildListing, Find-GethWindowsBlobName, Expand-GethWindowsArchive, Install-GethWindows

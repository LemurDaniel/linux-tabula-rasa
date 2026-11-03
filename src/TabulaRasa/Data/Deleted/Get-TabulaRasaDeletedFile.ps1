# NOTE:
#   Requires: Linux, root, sleuthkit (fls).
#
#   (Get-TabulaRasaDeletedFile -Path /dev/sdb1).Files | Select-Object -First 20

function Get-TabulaRasaDeletedFile {
    <#
    .SYNOPSIS
        Lists files that are marked deleted in the file system of a partition but still on the disk.

    .DESCRIPTION
        Reads the file system metadata with sleuthkit (fls), the partition is not mounted.
        Works for NTFS, FAT, exFAT, ext2/3/4, HFS+ and ISO 9660.

        IsSupported is $false when fls cannot read the file system (e.g. after a quick format,
        an encrypted or an unknown file system). The deep signature scan still works there.

    .EXAMPLE
        PS> $result = Get-TabulaRasaDeletedFile -Path /dev/sdb1
        PS> $result.Files | Select-Object -First 20
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        <#
        [Required]
        The device path of the partition, e.g. '/dev/sdb1'.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.String]
        $Path,

        <#
        [Optional]
        The number of files returned in Files, TotalCount still counts all. Default is 1000.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [ValidateRange(1, 1000000)]
        [System.Int32]
        $MaxCount = 1000
    )

    # fls writes its own error to stderr and exits non-zero on an unreadable file system.
    $BodyLines = fls -r -d -m / $Path 2>$null
    if ($LASTEXITCODE -NE 0) {
        Write-Verbose "[Get-TabulaRasaDeletedFile] fls cannot read '$Path' (exit code $LASTEXITCODE) -> unsupported."
        return [PSCustomObject]@{
            Path        = $Path
            IsSupported = $false
            TotalCount  = 0
            Files       = @()
        }
    }

    $Files = @($BodyLines | ConvertFrom-TabulaRasaFlsBody)

    Write-Verbose "[Get-TabulaRasaDeletedFile] '$Path': $($Files.Count) deleted files found."
    return [PSCustomObject]@{
        Path        = $Path
        IsSupported = $true
        TotalCount  = $Files.Count
        Files       = @($Files | Select-Object -First $MaxCount)
    }
}

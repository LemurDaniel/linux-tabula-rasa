# NOTE:
#   Requires: nothing, pure parsing of fls body lines.
#
#   fls -r -d -m / /dev/sdb1 | ConvertFrom-TabulaRasaFlsBody

function ConvertFrom-TabulaRasaFlsBody {
    <#
    .SYNOPSIS
        Turns the body file lines of 'fls -r -d -m /' (sleuthkit) into deleted file entries.

    .DESCRIPTION
        One body line has 11 '|'-separated fields:
        MD5|name|inode|mode|UID|GID|size|atime|mtime|ctime|crtime

        The name may contain '|' itself, so the 9 fixed fields are taken from the end.
        Folders (mode 'd/d...') are skipped, only files are returned.
        Empty orphans (/$OrphanFiles/... with size 0) are skipped too: ext4 clears name and size
        on delete, such an entry says nothing. The deep signature scan still finds the content.

        Shape change:
        '0|/Users/x/IMG_0042.jpg (deleted)|1234-128-1|r/rrwxrwxrwx|0|0|2483011|1700000000|1699000000|1699000000|1698000000'
        => [PSCustomObject]@{ Path = '/Users/x/IMG_0042.jpg'; SizeBytes = 2483011; LastWriteTime = 2023-11-03 08:26:40 (local) }

    .EXAMPLE
        PS> fls -r -d -m / /dev/sdb1 | ConvertFrom-TabulaRasaFlsBody
    #>

    [CmdletBinding()]
    param (
        <#
        [Required]
        Body file lines from fls.
        #>
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true
        )]
        [AllowEmptyString()]
        [System.String]
        $Line
    )

    PROCESS {
        $fields = $Line.Split('|')
        if ($fields.Count -LT 11) {
            Write-Verbose "[ConvertFrom-TabulaRasaFlsBody] Line has $($fields.Count) fields instead of 11 -> skipping."
            return
        }

        # [MD5] [name ...] [inode, mode, UID, GID, size, atime, mtime, ctime, crtime]
        $tail = $fields[-9..-1]
        $name = $fields[1..($fields.Count - 10)] -join '|'
        $mode = $tail[1]

        if ($mode -LIKE 'd/*') {
            return
        }

        $sizeBytes = [System.Int64] $tail[4]
        if ($name -LIKE '/$OrphanFiles/*' -AND $sizeBytes -EQ 0) {
            return
        }

        $mtime = [System.Int64] $tail[6]

        [PSCustomObject]@{
            Path          = $name -replace ' \(deleted(-realloc)?\)$', ''
            SizeBytes     = $sizeBytes
            LastWriteTime = $mtime -GT 0 ? [System.DateTimeOffset]::FromUnixTimeSeconds($mtime).LocalDateTime : $null
        }
    }
}

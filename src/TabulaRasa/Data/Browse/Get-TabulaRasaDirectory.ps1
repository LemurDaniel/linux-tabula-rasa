function Get-TabulaRasaDirectory {
    <#
    .SYNOPSIS
        Lists the entries of a folder inside a mounted partition, folders first.

    .DESCRIPTION
        The relative path may come from a browser, so it is checked before anything is read:
        - The resolved path must stay inside the mount point ('..' cannot escape).
        - No segment may be a symbolic link, a link could point into the live system.
        Symbolic links are listed, but marked IsLink and never opened as folders.

    .EXAMPLE
        PS> Get-TabulaRasaDirectory -MountPoint /run/tabula-rasa/mnt/sdb1 -RelativePath 'Users/Daniel'
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        <#
        [Required]
        The mount point from Mount-TabulaRasaPartition.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.String]
        $MountPoint,

        <#
        [Optional]
        The folder below the mount point, '/'-separated. Default is the root of the partition.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [AllowEmptyString()]
        [System.String]
        $RelativePath = ''
    )

    # Validations
    $Root    = [System.IO.Path]::GetFullPath($MountPoint).TrimEnd('/')
    $FullPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($Root, $RelativePath.TrimStart('/'))).TrimEnd('/')

    if ($FullPath -NE $Root -AND -NOT $FullPath.StartsWith("$Root/", [System.StringComparison]::Ordinal)) {
        throw [System.UnauthorizedAccessException]::new("Path '$RelativePath' must stay inside the mount point '$Root'.")
    }

    # Walk every segment below the root, a link anywhere on the way is refused.
    $current = $Root
    foreach ($segment in $FullPath.Substring($Root.Length).Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $current = "$current/$segment"
        if ($null -NE (Get-Item -LiteralPath $current -Force).LinkType) {
            throw [System.UnauthorizedAccessException]::new("Path '$RelativePath' must not pass the symbolic link '$segment'.")
        }
    }

    # Entries
    return Get-ChildItem -LiteralPath $FullPath -Force
    | ForEach-Object {
        $isLink = $null -NE $_.LinkType
        [PSCustomObject]@{
            Name          = $_.Name
            RelativePath  = $_.FullName.Substring($Root.Length).TrimStart('/')
            IsDirectory   = $_.PSIsContainer -AND -NOT $isLink
            IsLink        = $isLink
            SizeBytes     = $_.PSIsContainer ? 0 : [System.Int64] $_.Length
            LastWriteTime = $_.LastWriteTime
        }
    }
    | Sort-Object -Property @{ Expression = 'IsDirectory'; Descending = $true }, Name
}

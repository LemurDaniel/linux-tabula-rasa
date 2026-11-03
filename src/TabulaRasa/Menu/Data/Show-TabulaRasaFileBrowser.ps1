# NOTE:
#   Requires: PwshSpectreConsole, an interactive console, Linux and root to mount the partition.
#
#   Show-TabulaRasaFileBrowser -Disk (Get-TabulaRasaDisk | Select-Object -First 1)

function Show-TabulaRasaFileBrowser {
    <#
    .SYNOPSIS
        Walks the folders of a partition, mounted read-only for the time of the browsing.

    .DESCRIPTION
        Folders open on selection, files only show their size and date. Nothing is copied or opened.
        The partition is unmounted again when the user leaves, also on errors and Ctrl+C.

    .EXAMPLE
        PS> Show-TabulaRasaFileBrowser -Disk (Get-TabulaRasaDisk | Select-Object -First 1)
    #>

    [CmdletBinding()]
    param (
        <#
        [Required]
        The disk from Get-TabulaRasaDisk.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [PSCustomObject]
        $Disk
    )

    $PAGE_SIZE = 20

    $Partition = Select-TabulaRasaPartition -Disk $Disk -MountableOnly
    if ($null -EQ $Partition) {
        return
    }

    try {
        $Mount = Mount-TabulaRasaPartition -Path $Partition.Path -FileSystem $Partition.FileSystem
        $relativePath = ''

        while ($true) {
            Clear-Host
            Write-SpectreRule -Title (Get-SpectreEscapedText -Text "$($Partition.Path)/$relativePath") -Color Orange1

            $entries = @(Get-TabulaRasaDirectory -MountPoint $Mount.MountPoint -RelativePath $relativePath)
            $choices = @(
                [PSCustomObject]@{ Label = '[grey]<- Back[/]'; Entry = $null; Action = 'Back' }
                if ($relativePath -NE '') {
                    [PSCustomObject]@{ Label = '[grey]..[/]'; Entry = $null; Action = 'Up' }
                }
                foreach ($entry in $entries) {
                    $name = Get-SpectreEscapedText -Text $entry.Name
                    [PSCustomObject]@{
                        Label  = $entry.IsDirectory ? "[blue]$name/[/]" : "$name  [grey]$(Format-TabulaRasaSize -Bytes $entry.SizeBytes)  $($entry.LastWriteTime.ToString('yyyy-MM-dd'))[/]"
                        Entry  = $entry
                        Action = $entry.IsDirectory ? 'Open' : 'File'
                    }
                }
            )

            $choice = Read-SpectreSelection -Message "$($entries.Count) entries" -Choices $choices -ChoiceLabelProperty Label -PageSize $PAGE_SIZE -EnableSearch
            switch ($choice.Action) {
                'Back' { return }
                'Up'   { $relativePath = ($relativePath -split '/' | Select-Object -SkipLast 1) -join '/' }
                'Open' { $relativePath = $choice.Entry.RelativePath }
                'File' { }
            }
        }
    }
    finally {
        # Releases the mount from Mount-TabulaRasaPartition, a wipe needs the partition free.
        Dismount-TabulaRasaPartition -Path $Partition.Path
    }
}

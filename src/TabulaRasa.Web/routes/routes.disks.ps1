# NOTE:
#   Loaded by Use-PodeRoutes in Start-TabulaRasaServer. All routes need the session token.
#
#   GET /api/disks                         Every wipeable disk with its wipe plan.
#   GET /api/disks/:name/partitions        The partitions of a disk.
#   GET /api/disks/:name/browse?partition=&path=
#                                          One folder of a partition, mounted read-only for the request.

#
#   Chapters:
#     DISK ROUTES   Disk list, partitions and the read-only file browser.
#

# ===========================================================================
# =============================   DISK ROUTES   =============================
# ===========================================================================
#
#   GET /api/disks              Disks with method, confirmation and warning.
#   GET .../partitions          Partitions with file system and IsMountable.
#   GET .../browse              Mounts, lists one folder, unmounts again.
#

Add-PodeRoute -Method Get -Path '/api/disks' -ScriptBlock {
    $Disks = @(Get-TabulaRasaDisk) | ForEach-Object {
        $wipeInfo = Resolve-TabulaRasaWipeMethod -Kind $_.Kind
        $_ | Select-Object -Property *, @{ Name = 'Wipe'; Expression = { $wipeInfo } }
    }
    Write-PodeJsonResponse -Depth 4 -Value @{ disks = @($Disks) }
}

Add-PodeRoute -Method Get -Path '/api/disks/:name/partitions' -ScriptBlock {
    $Disk = Resolve-TabulaRasaWebDisk -Name $WebEvent.Parameters['name']
    if ($null -EQ $Disk) {
        Write-TabulaRasaWebError -StatusCode 404 -Message "Disk '$($WebEvent.Parameters['name'])' must be plugged in."
        return
    }
    Write-PodeJsonResponse -Depth 4 -Value @{ partitions = @(Get-TabulaRasaPartition -Path $Disk.Path) }
}

Add-PodeRoute -Method Get -Path '/api/disks/:name/browse' -ScriptBlock {
    $MAX_ENTRIES = 1000

    $Disk = Resolve-TabulaRasaWebDisk -Name $WebEvent.Parameters['name']
    if ($null -EQ $Disk) {
        Write-TabulaRasaWebError -StatusCode 404 -Message "Disk '$($WebEvent.Parameters['name'])' must be plugged in."
        return
    }

    $partitionName = [System.String] $WebEvent.Query['partition']
    $Partition     = Get-TabulaRasaPartition -Path $Disk.Path | Where-Object -Property Name -CEQ -Value $partitionName
    if ($null -EQ $Partition -OR -NOT $Partition.IsMountable) {
        Write-TabulaRasaWebError -StatusCode 404 -Message "Partition '$partitionName' must exist on '$($Disk.Path)' with a readable file system."
        return
    }

    # Mounted only for this request: nothing stays mounted when the browser walks away.
    try {
        $mount   = Mount-TabulaRasaPartition -Path $Partition.Path -FileSystem $Partition.FileSystem
        $Entries = @(Get-TabulaRasaDirectory -MountPoint $mount.MountPoint -RelativePath ([System.String] $WebEvent.Query['path']))
    }
    catch [System.UnauthorizedAccessException] {
        Write-TabulaRasaWebError -StatusCode 403 -Message $_.Exception.Message
        return
    }
    catch [System.InvalidOperationException] {
        Write-TabulaRasaWebError -StatusCode 409 -Message $_.Exception.Message
        return
    }
    finally {
        Dismount-TabulaRasaPartition -Path $Partition.Path
    }

    Write-PodeJsonResponse -Depth 4 -Value @{
        totalCount = $Entries.Count
        entries    = @($Entries | Select-Object -First $MAX_ENTRIES)
    }
}
